"""③ 로컬 주문 생성기 (Path A) — Confluent Cloud 토픽으로 발행.

order_lines 는 JSON "문자열"로 직렬화해 발행합니다(raw 테이블의 String 컬럼에 적재).

  python scripts/02_produce.py

.env 의 PRODUCE_RATE / PRODUCE_MAX / PLACEHOLDER_RATE / EMPTY_LINES_RATE 로 조절.
Ctrl+C 로 중단.
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


def main():
    producer = build_producer()
    interval = 1.0 / CFG.produce_rate if CFG.produce_rate > 0 else 0
    limit = CFG.produce_max
    print(f"[produce] → {CFG.kafka_topic} @ {CFG.kafka_bootstrap} "
          f"(~{CFG.produce_rate}/s, max={'∞' if limit == 0 else limit}) — Ctrl+C 로 중단")
    sent = 0
    try:
        while limit == 0 or sent < limit:
            producer.send(CFG.kafka_topic, to_message(make_order()))
            sent += 1
            if sent % 50 == 0:
                producer.flush()
                print(f"  sent {sent} orders")
            if interval:
                time.sleep(interval)
    except KeyboardInterrupt:
        print("\n[produce] 중단 요청")
    finally:
        producer.flush()
        producer.close()
        print(f"[produce] 종료. 총 {sent}건 발행")


if __name__ == "__main__":
    main()
