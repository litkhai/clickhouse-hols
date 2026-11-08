#!/usr/bin/env bash
# Iceberg v1 / v2 / v3 side by side: write with Spark, open the files, read with ClickHouse.
#
#   ./run.sh            stack up -> spark/steps.py -> inspect/inspect.py -> clickhouse/read.py
#   ./run.sh read       only the ClickHouse step (tables already written)
#   ./run.sh down       remove the stack and its volumes
#
# Env: CH_VERSION (ClickHouse image tag, default 26.10.3.7). Results land in results/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
export CH_VERSION="${CH_VERSION:-26.10.3.7}"
ICEBERG_VERSION=1.11.0
PACKAGES="org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:${ICEBERG_VERSION},org.apache.iceberg:iceberg-aws-bundle:${ICEBERG_VERSION}"

case "${1:-all}" in
  down) docker compose --profile tools down -v; exit 0 ;;
  read|all) ;;
  *) echo "usage: $0 [all|read|down]" >&2; exit 2 ;;
esac

mkdir -p results
docker compose up -d --quiet-pull --wait minio iceberg-rest clickhouse
docker compose up --quiet-pull minio-setup >/dev/null 2>&1   # bucket (idempotent)
until docker compose exec -T clickhouse clickhouse-client -q 'SELECT 1' >/dev/null 2>&1; do sleep 1; done

if [ "${1:-all}" = all ]; then
  echo "== spark: write v1, v2, v3 tables (results/spark-steps.txt)"
  docker compose run --rm -q spark /opt/spark/bin/spark-submit \
    --conf spark.driver.memory=2g --conf spark.jars.ivy=/root/.ivy2 \
    --packages "$PACKAGES" spark/steps.py > results/spark-run.log 2>&1 \
    || { tail -30 results/spark-run.log; exit 1; }
  grep -E "^Spark|REFUSED|DONE" results/spark-steps.txt

  echo "== inspect: open the files (results/inspect-*.txt)"
  docker compose run --rm -q inspect sh -c \
    'pip install -q --root-user-action=ignore -r inspect/requirements.txt && python -I inspect/inspect.py'
fi

echo "== clickhouse ${CH_VERSION}: read the tables"
python3 clickhouse/read.py
