#!/usr/bin/env bash
# 02-create-topics.sh — create the two topics with identical partition counts.
#
#   events_misaligned  — producer uses the DEFAULT (hash-of-key) partitioner,
#                        so every partition ends up with the full customer range.
#   events_aligned     — producer assigns partition = customer_id range bucket,
#                        so each partition owns a disjoint, contiguous range.
#
# Same partition COUNT on both; only the *assignment strategy* (in 04-produce.py)
# differs. That is the whole experiment.
set -euo pipefail
cd "$(dirname "$0")"
. ./_env.sh; load_env

P="${NUM_PARTITIONS:-8}"
KT=(docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092)

for t in events_misaligned events_aligned; do
  echo "▶ (re)creating topic '$t' with $P partitions…"
  "${KT[@]}" --delete --topic "$t" 2>/dev/null || true
  "${KT[@]}" --create --topic "$t" --partitions "$P" --replication-factor 1
done

echo
echo "▶ Topics:"
"${KT[@]}" --describe --topic events_misaligned | sed 's/^/   /'
"${KT[@]}" --describe --topic events_aligned   | sed 's/^/   /'
echo "✅ Done."
