# ClickHouse server + Python 3 and the distro's `cryptography`, for the executable UDFs.
# Same server version as the langfuse-hols v4 track (versions.env: CLICKHOUSE_VERSION).
ARG CLICKHOUSE_VERSION=26.8.22.13
FROM docker.io/clickhouse/clickhouse-server:${CLICKHOUSE_VERSION}
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-cryptography \
 && rm -rf /var/lib/apt/lists/*
