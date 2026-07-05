"""▶ 데모 시작 원클릭 런처.

  1) ClickHouse SQL 연결 + 스키마(테이블·MV) 존재 확인
  2) Confluent Kafka 연결 + 토픽 확인
  3) ClickPipes 존재·가동 여부 확인 (멈춰 있으면 자동 start)
  4) 위가 모두 OK면 주문 메시지를 계속 발행 (기본 1초에 1건)

사용법:
  python scripts/start_demo.py            # 점검 후 계속 발행 (Ctrl+C 로 중단)
  python scripts/start_demo.py --check    # 점검만 하고 종료 (발행 안 함)
  python scripts/start_demo.py --rate 5   # 발행 속도 임시 오버라이드 (건/초)

전제: scripts/00_setup_clickhouse.py, scripts/01_create_clickpipe.py 는 사전에 1회 실행.
반복 데모 사이 초기화는 scripts/clean.py 를 쓰세요.
"""
import sys

import clickpipe_api as api
from config import CFG

OK = "\033[92m✓\033[0m"
BAD = "\033[91m✗\033[0m"
WARN = "\033[93m!\033[0m"


def fail(msg, hint=None):
    print(f"  {BAD} {msg}")
    if hint:
        print(f"      → {hint}")
    sys.exit(1)


def check_clickhouse():
    print("① ClickHouse SQL 연결 · 스키마 확인")
    try:
        client = CFG.ch_client()
        ver = client.query("SELECT version()").result_rows[0][0]
    except Exception as e:
        fail(f"연결 실패: {type(e).__name__} {str(e)[:120]}",
             ".env 의 CH_HOST/CH_PORT/CH_USER/CH_PASSWORD 확인")
    print(f"  {OK} 연결 OK (v{ver}) — {CFG.ch_host}")

    need = [CFG.tbl_raw, CFG.tbl_staging, CFG.tbl_fact, CFG.mv_transform, CFG.mv_explode]
    have = {r[0] for r in client.query(
        f"SELECT name FROM system.tables WHERE database='{CFG.database}'").result_rows}
    missing = [n for n in need if n not in have]
    if missing:
        fail(f"누락된 오브젝트: {', '.join(missing)}",
             "python scripts/00_setup_clickhouse.py 먼저 실행")
    print(f"  {OK} 스키마 OK — {CFG.database}.{{{', '.join(need)}}}")
    # 현재 적재량
    counts = {t: client.query(f"SELECT count() FROM {CFG.database}.{t}").result_rows[0][0]
              for t in (CFG.tbl_raw, CFG.tbl_staging, CFG.tbl_fact)}
    print(f"  {OK} 현재 행 수 — raw={counts[CFG.tbl_raw]:,} "
          f"staging={counts[CFG.tbl_staging]:,} fact={counts[CFG.tbl_fact]:,}")
    return client


def check_kafka():
    print("② Confluent Kafka 연결 · 토픽 확인")
    from producer import build_producer
    try:
        p = build_producer()
        connected = p.bootstrap_connected()
        parts = p.partitions_for(CFG.kafka_topic)
        p.close()
    except Exception as e:
        fail(f"연결 실패: {type(e).__name__} {str(e)[:120]}",
             ".env 의 KAFKA_BOOTSTRAP(:9092)/KAFKA_API_KEY/SECRET (cluster 스코프 키) 확인")
    if not parts:
        fail(f"토픽 '{CFG.kafka_topic}' 을 찾을 수 없음",
             "토픽 이름 확인 또는 Confluent 콘솔에서 토픽 생성")
    print(f"  {OK} 연결 OK — topic '{CFG.kafka_topic}' partitions={sorted(parts)}")


def check_clickpipe():
    print("③ ClickPipes 가동 여부 확인")
    try:
        pipe = api.find_by_name(CFG.clickpipe_name)
    except Exception as e:
        fail(f"OpenAPI 호출 실패: {type(e).__name__} {str(e)[:120]}",
             ".env 의 CH_API_KEY_ID/SECRET, CH_ORG_ID, CH_SERVICE_ID 확인")
    if not pipe:
        fail(f"ClickPipe '{CFG.clickpipe_name}' 없음",
             "python scripts/01_create_clickpipe.py 먼저 실행")

    pid, state = pipe["id"], pipe.get("state")
    print(f"  {OK} 존재 — id={pid} state={state}")
    if state == "Running":
        return
    if state in ("Stopped", "Paused"):
        print(f"  {WARN} 멈춰 있어 start 시도…")
        api.start_clickpipe(pid)
        state, _ = api.wait_for_state(pid, target=("Running",), timeout_s=120)
        if state != "Running":
            fail(f"start 후에도 상태가 '{state}'", "Cloud 콘솔에서 ClickPipe 상태 확인")
        print(f"  {OK} 이제 Running")
    else:
        print(f"  {WARN} 상태 '{state}' — 잠시 후 Running 이 되는지 대기…")
        state, _ = api.wait_for_state(pid, target=("Running",), timeout_s=120)
        if state != "Running":
            fail(f"상태가 '{state}' 로 유지됨", "Cloud 콘솔에서 ClickPipe 상태·에러 확인")
        print(f"  {OK} 이제 Running")


def parse_rate():
    if "--rate" in sys.argv:
        i = sys.argv.index("--rate")
        try:
            return float(sys.argv[i + 1])
        except (IndexError, ValueError):
            fail("--rate 뒤에 숫자(건/초)를 지정하세요. 예: --rate 5")
    return None


def main():
    print("\n\033[1m▶ 실시간 JSON explode 데모 시작 점검\033[0m\n")
    check_clickhouse()
    check_kafka()
    check_clickpipe()
    print(f"\n\033[1m{OK} 모든 점검 통과.\033[0m\n")

    if "--check" in sys.argv:
        print("(--check 모드: 발행하지 않고 종료)")
        return

    rate = parse_rate()
    print("주문 메시지 발행을 시작합니다. 다른 터미널에서 검증:")
    print("  python scripts/03_verify.py --watch\n")
    from producer import build_producer, run_forever
    producer = build_producer()
    try:
        run_forever(producer, rate=rate)
    finally:
        producer.close()


if __name__ == "__main__":
    main()
