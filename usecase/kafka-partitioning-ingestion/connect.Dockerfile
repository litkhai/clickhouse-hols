# Kafka Connect worker + the official ClickHouse Kafka Connect Sink connector.
# Built once by `docker compose up` (compose `build:` below). The connector jar is
# baked in at build time so the lab doesn't depend on a download at container start.
FROM confluentinc/cp-kafka-connect:7.8.0

# https://github.com/ClickHouse/clickhouse-kafka-connect  (Confluent Hub coordinates)
# 'latest' tracks a client compatible with current ClickHouse servers. Older
# pins (e.g. v1.3.4) bundle a Java client that mis-handles LZ4 framing against
# CH 26.x ("Magic is not correct" on version detection).
RUN confluent-hub install --no-prompt clickhouse/clickhouse-kafka-connect:latest
