"""데모 상태 관리 — producer 스레드 + Kafka tail 스레드 + 테이블 초기화.

Flask 앱이 이 싱글턴(STATE)을 통해 발행 시작/정지/초기화하고,
4단계(client/kafka/staging/fact) 데이터를 읽습니다.
"""
import json
import threading
import time
from collections import deque

from config import CFG
from order_generator import make_order
from producer import build_producer, to_message

MAXBUF = 12  # 각 버퍼에 보관할 최근 메시지 수


class DemoState:
    def __init__(self):
        self._lock = threading.Lock()
        self.client_buf = deque(maxlen=MAXBUF)
        self.kafka_buf = deque(maxlen=MAXBUF)
        self.sent = 0

        self.interval = 3.0            # 기본: 3초에 1건
        self._prod_running = False
        self._prod_thread = None

        self._tail_running = False
        self._tail_thread = None
        self.kafka_error = None

        # ClickPipe 상태 캐시 (매 폴링마다 API 호출 방지)
        self._pipe_cache = {"state": None, "name": CFG.clickpipe_name, "ts": 0}

    # ---------------- producer ----------------
    def start_producer(self, interval=None):
        with self._lock:
            if interval:
                self.interval = max(0.2, float(interval))
            if self._prod_running:
                return {"running": True, "interval": self.interval, "resumed": False}
            self._prod_running = True
            self._prod_thread = threading.Thread(target=self._produce_loop, daemon=True)
            self._prod_thread.start()
        self._ensure_tail()
        return {"running": True, "interval": self.interval, "resumed": True}

    def stop_producer(self):
        with self._lock:
            self._prod_running = False
        return {"running": False}

    def set_interval(self, interval):
        with self._lock:
            self.interval = max(0.2, float(interval))
        return {"interval": self.interval}

    def _produce_loop(self):
        prod = build_producer()
        try:
            while self._prod_running:
                order = make_order()
                prod.send(CFG.kafka_topic, to_message(order))
                prod.flush()
                with self._lock:
                    self.sent += 1
                    self.client_buf.appendleft({
                        "order_id": order["order_id"][:8],
                        "order_status": order["order_status"],
                        "customer_id": order["customer_id"],
                        "n_lines": len(order["order_lines"]),
                    })
                # interval 동안 잘게 쪼개 대기 (정지/속도변경 즉시 반영)
                waited, iv = 0.0, self.interval
                while self._prod_running and waited < iv:
                    step = min(0.1, iv - waited)
                    time.sleep(step)
                    waited += step
                    iv = self.interval
        finally:
            prod.close()

    # ---------------- kafka tail ----------------
    def _ensure_tail(self):
        with self._lock:
            if self._tail_running:
                return
            self._tail_running = True
            self._tail_thread = threading.Thread(target=self._tail_loop, daemon=True)
            self._tail_thread.start()

    def _tail_loop(self):
        try:
            from kafka import KafkaConsumer
            consumer = KafkaConsumer(
                bootstrap_servers=CFG.kafka_bootstrap,
                security_protocol="SASL_SSL",
                sasl_mechanism=CFG.kafka_sasl_mechanism,
                sasl_plain_username=CFG.kafka_api_key,
                sasl_plain_password=CFG.kafka_api_secret,
                auto_offset_reset="latest",
                enable_auto_commit=False,
                group_id=None,
                consumer_timeout_ms=1000,
                value_deserializer=lambda b: b.decode("utf-8", "replace"),
            )
            consumer.subscribe([CFG.kafka_topic])
            self.kafka_error = None
            while self._tail_running:
                recs = consumer.poll(timeout_ms=1000, max_records=20)
                for _tp, msgs in recs.items():
                    for m in msgs:
                        try:
                            v = json.loads(m.value)
                            oid, st = v.get("order_id", "")[:8], v.get("order_status")
                        except Exception:
                            oid, st = "", None
                        with self._lock:
                            self.kafka_buf.appendleft({
                                "partition": m.partition, "offset": m.offset,
                                "order_id": oid, "order_status": st,
                                "raw": m.value,   # 전체 JSON 보관 (UI 에서 클릭 시 전체 표시)
                            })
        except Exception as e:
            self.kafka_error = f"{type(e).__name__}: {str(e)[:120]}"
            self._tail_running = False

    # ---------------- clickhouse reads ----------------
    def _rows(self, client, sql):
        r = client.query(sql)
        return {"columns": list(r.column_names),
                "rows": [[_j(v) for v in row] for row in r.result_rows]}

    def counts(self, client):
        r = client.query(
            f"SELECT (SELECT count() FROM {CFG.database}.{CFG.tbl_raw}),"
            f" (SELECT count() FROM {CFG.database}.{CFG.tbl_staging}),"
            f" (SELECT count() FROM {CFG.database}.{CFG.tbl_fact})").result_rows[0]
        return {"raw": r[0], "staging": r[1], "fact": r[2]}

    def stages(self, client):
        with self._lock:
            client_rows = list(self.client_buf)
            kafka_rows = list(self.kafka_buf)
            kerr = self.kafka_error
        staging = self._rows(client, f"""
            SELECT order_id, order_status, customer_id, tracking_id,
                   order_timestamp_local, JSONLength(order_lines) AS n_lines
            FROM {CFG.database}.{CFG.tbl_staging}
            ORDER BY _timestamp DESC LIMIT {MAXBUF}""")
        fact = self._rows(client, f"""
            SELECT order_id, product_sku, product_category,
                   unit_price, quantity, line_total
            FROM {CFG.database}.{CFG.tbl_fact}
            ORDER BY order_timestamp_local DESC LIMIT {MAXBUF}""")
        return {"client": client_rows, "kafka": kafka_rows, "kafka_error": kerr,
                "staging": staging, "fact": fact}

    # ---------------- clickpipe state (cached) ----------------
    def pipe_state(self):
        now = time.time()
        if now - self._pipe_cache["ts"] < 10 and self._pipe_cache["state"]:
            return self._pipe_cache
        try:
            import clickpipe_api as api
            p = api.find_by_name(CFG.clickpipe_name)
            self._pipe_cache = {"state": (p or {}).get("state", "없음"),
                                "name": CFG.clickpipe_name, "ts": now}
        except Exception as e:
            self._pipe_cache = {"state": f"조회실패({type(e).__name__})",
                                "name": CFG.clickpipe_name, "ts": now}
        return self._pipe_cache

    # ---------------- cleanup ----------------
    def cleanup(self, client):
        result = {}
        for name in (CFG.tbl_raw, CFG.tbl_staging, CFG.tbl_fact):
            before = client.query(f"SELECT count() FROM {CFG.database}.{name}").result_rows[0][0]
            client.command(f"TRUNCATE TABLE IF EXISTS {CFG.database}.{name}")
            result[name] = before
        with self._lock:
            self.client_buf.clear()
            self.kafka_buf.clear()
            self.sent = 0
        return result

    def status(self):
        with self._lock:
            return {"running": self._prod_running, "interval": self.interval, "sent": self.sent}


def _j(v):
    """JSON 직렬화 가능하게 변환 (Decimal/datetime → str)."""
    from datetime import date, datetime
    from decimal import Decimal
    if isinstance(v, (Decimal, datetime, date)):
        return str(v)
    return v


STATE = DemoState()
