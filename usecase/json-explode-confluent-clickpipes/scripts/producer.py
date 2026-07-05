"""Kafka producer 코어 — 02_produce.py 와 start_demo.py 가 공유.

order_lines 는 JSON "문자열"로 직렬화해 발행합니다(raw 테이블의 String 컬럼에 적재).
"""
import json
import time

from kafka import KafkaProducer

from config import CFG
from order_generator import make_order


def build_producer() -> KafkaProducer:
    return KafkaProducer(
        bootstrap_servers=CFG.kafka_bootstrap,
        security_protocol="SASL_SSL",
        sasl_mechanism=CFG.kafka_sasl_mechanism,
        sasl_plain_username=CFG.kafka_api_key,
        sasl_plain_password=CFG.kafka_api_secret,
        value_serializer=lambda v: json.dumps(v).encode(),
        linger_ms=50,
    )


def to_message(order: dict) -> dict:
    """order_lines(list) → JSON 문자열. raw 테이블 String 컬럼과 정합."""
    return {**order, "order_lines": json.dumps(order["order_lines"], ensure_ascii=False)}


def produce_batch(producer: KafkaProducer, n: int) -> int:
    """씨드용: n 건을 즉시 발행하고 flush. 발행 건수 반환."""
    for _ in range(n):
        producer.send(CFG.kafka_topic, to_message(make_order()))
    producer.flush()
    return n


def run_forever(producer: KafkaProducer, rate=None, limit=None, banner=True):
    """rate 건/초로 계속 발행. limit=0/None 이면 Ctrl+C 까지 무한."""
    rate = CFG.produce_rate if rate is None else rate
    limit = CFG.produce_max if limit is None else limit
    interval = 1.0 / rate if rate > 0 else 0
    report_every = max(1, int(round(rate)) * 5)  # 약 5초마다 리포트

    if banner:
        print("=" * 62)
        print("  라이브 주문 이벤트 생성기 (계속 실행 — Ctrl+C 로 중단)")
        print(f"  topic  : {CFG.kafka_topic} @ {CFG.kafka_bootstrap}")
        print(f"  rate   : ~{rate}/s   max: {'∞ (무한)' if limit == 0 else limit}")
        print(f"  mix    : placeholder {CFG.placeholder_rate:.0%} · empty-lines {CFG.empty_lines_rate:.0%}")
        print("=" * 62)

    sent = 0
    t0 = last_t = time.time()
    last_sent = 0
    try:
        while limit == 0 or sent < limit:
            producer.send(CFG.kafka_topic, to_message(make_order()))
            sent += 1
            if sent % report_every == 0:
                producer.flush()
                now = time.time()
                inst = (sent - last_sent) / (now - last_t) if now > last_t else 0
                print(f"  sent {sent:>6,}  |  {now - t0:6.1f}s 경과  |  실측 {inst:5.1f}/s")
                last_t, last_sent = now, sent
            if interval:
                time.sleep(interval)
    except KeyboardInterrupt:
        print("\n[produce] 중단 요청")
    finally:
        producer.flush()
        elapsed = time.time() - t0
        avg = sent / elapsed if elapsed > 0 else 0
        print(f"[produce] 종료. 총 {sent:,}건 · {elapsed:.1f}s · 평균 {avg:.1f}/s")
    return sent
