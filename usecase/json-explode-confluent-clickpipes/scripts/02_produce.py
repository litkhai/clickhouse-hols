"""③ 로컬 주문 생성기 (Path A) — Confluent Cloud 토픽으로 계속 발행.

터미널에 켜두면 Ctrl+C 전까지 계속 메시지를 만들어 넣습니다(라이브 데모용).

  python scripts/02_produce.py

.env 의 PRODUCE_RATE(기본 1/s) / PRODUCE_MAX(0=무한) /
PLACEHOLDER_RATE / EMPTY_LINES_RATE 로 조절합니다.

전체 데모를 한 번에 시작하려면 scripts/start_demo.py 를 쓰세요
(연결·스키마·ClickPipe 점검까지 포함).
"""
from producer import build_producer, run_forever


def main():
    producer = build_producer()
    try:
        run_forever(producer)
    finally:
        producer.close()


if __name__ == "__main__":
    main()
