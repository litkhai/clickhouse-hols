#!/usr/bin/env python3
# ============================================================================
# kafka-partitioning-ingestion Step 5: the producer (the whole experiment)
# 카프카 파티셔닝 인제스천 5단계: 프로듀서 (실험의 핵심)
# ============================================================================
# Produces the SAME number of events, with the SAME (uniform) customer
# distribution, to two topics — differing only in HOW records map to partitions:
#
#   events_misaligned : key = customer_id, DEFAULT partitioner (murmur2 hash).
#                       Random customer order. → every partition gets the full
#                       [0, NUM_CUSTOMERS) key range mixed together.
#
#   events_aligned    : partition = customer_id // bucket (range partitioning),
#                       produced in ascending customer order. → each partition
#                       owns a disjoint, contiguous key interval.
#
# That single upstream choice is what later makes ClickHouse parts wide (no
# pruning) vs narrow (effective pruning). Everything else is held constant.
#
#   두 토픽에 동일한 수의 이벤트를, 동일한 customer 분포로 produce하되, 레코드를
#   파티션에 매핑하는 방식만 다르게 한다 (hash vs range). 이 상류의 선택 하나가
#   나중에 ClickHouse part를 넓게(pruning 불가) / 좁게(pruning 작동) 만든다.
#
# Usage:
#   python 04-produce.py                 # both topics, ROWS from .env
#   python 04-produce.py --topic aligned --rows 2000000
# ============================================================================
import argparse
import json
import os
import random
import sys
import time

try:
    from confluent_kafka import Producer
except ImportError:
    sys.exit("confluent-kafka not installed. Run: pip install -r requirements.txt")


def load_dotenv(path=".env"):
    """Minimal .env reader so the producer honors the same config as the shell scripts."""
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), path)
    if not os.path.exists(here):
        return
    with open(here) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            val = val.split(" #", 1)[0].strip().strip('"').strip("'")
            os.environ.setdefault(key.strip(), val)


load_dotenv()

NOW = int(time.time())
WINDOW = 30 * 24 * 3600  # spread ts over the last 30 days


def make_producer(bootstrap):
    errors = {"n": 0}

    def on_error(err):
        errors["n"] += 1
        if errors["n"] <= 5:
            print(f"  ! kafka error: {err}", file=sys.stderr)

    p = Producer({
        "bootstrap.servers": bootstrap,
        "linger.ms": 50,
        "batch.num.messages": 100000,
        "queue.buffering.max.messages": 2000000,
        "queue.buffering.max.kbytes": 1048576,
        "compression.type": "lz4",
        "acks": "1",
        "error_cb": lambda e: on_error(e),
    })
    return p, errors


def record(customer_id):
    """One event as JSONEachRow-compatible bytes. ts is a unix int (ClickHouse DateTime)."""
    return json.dumps({
        "customer_id": customer_id,
        "ts": NOW - random.randint(0, WINDOW),
        "val": random.randint(0, 2**31 - 1),
    }).encode()


def produce_misaligned(p, rows, num_customers, progress):
    """Hash partitioning: pass a key, let Kafka's default partitioner place it. Random order."""
    topic = "events_misaligned"
    for i in range(rows):
        cid = random.randrange(num_customers)
        while True:
            try:
                p.produce(topic, key=str(cid).encode(), value=record(cid))
                break
            except BufferError:
                p.poll(0.1)
        if i % 100000 == 0:
            p.poll(0)
            progress(topic, i, rows)
    progress(topic, rows, rows)


def produce_aligned(p, rows, num_customers, num_partitions, progress):
    """Range partitioning: partition = customer_id // bucket.

    IMPORTANT: customers are drawn in the SAME random/interleaved time order as the
    misaligned topic — the ONLY difference between the two topics is the partitioner
    (range here vs hash there). This realistic "all customers active at once" timeline
    is what exposes the engine-default gotcha: a single consumer reads partitions
    interleaved, so it multiplexes the full key range into each part (locality lost),
    while one-consumer-per-partition (tuned engine / Connect) still isolates each
    partition's contiguous range. (range 파티셔닝. 단, customer는 misaligned와 동일한
    무작위/교차 시간 순서로 뽑는다 — 두 토픽의 유일한 차이는 파티셔너(range vs hash)다.)
    """
    topic = "events_aligned"
    bucket = -(-num_customers // num_partitions)  # ceil division
    for i in range(rows):
        cid = random.randrange(num_customers)
        part = min(cid // bucket, num_partitions - 1)
        while True:
            try:
                p.produce(topic, key=str(cid).encode(), value=record(cid), partition=part)
                break
            except BufferError:
                p.poll(0.1)
        if i % 100000 == 0:
            p.poll(0)
            progress(topic, i, rows)
    progress(topic, rows, rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--topic", choices=["both", "aligned", "misaligned"], default="both")
    ap.add_argument("--rows", type=int, default=int(os.environ.get("ROWS", 10_000_000)))
    ap.add_argument("--customers", type=int, default=int(os.environ.get("NUM_CUSTOMERS", 10_000)))
    ap.add_argument("--partitions", type=int, default=int(os.environ.get("NUM_PARTITIONS", 8)))
    ap.add_argument("--bootstrap", default=os.environ.get("KAFKA_BOOTSTRAP", "localhost:9094"))
    args = ap.parse_args()

    print(f"▶ producing rows={args.rows:,} customers={args.customers:,} "
          f"partitions={args.partitions} → {args.bootstrap}")
    p, errors = make_producer(args.bootstrap)

    def progress(topic, done, total):
        pct = 100 * done / total if total else 100
        print(f"  {topic:18s} {done:>12,} / {total:,}  ({pct:5.1f}%)", end="\r")
        if done >= total:
            print()

    t0 = time.time()
    if args.topic in ("both", "misaligned"):
        produce_misaligned(p, args.rows, args.customers, progress)
    if args.topic in ("both", "aligned"):
        produce_aligned(p, args.rows, args.customers, args.partitions, progress)

    print("▶ flushing…")
    p.flush(60)
    dt = time.time() - t0
    if errors["n"]:
        print(f"⚠ {errors['n']} kafka error(s) reported.", file=sys.stderr)
    print(f"✅ done in {dt:.1f}s. The engine MVs and Connect sinks are consuming in "
          f"the background; wait a few seconds then run 06-compare.sql.")


if __name__ == "__main__":
    main()
