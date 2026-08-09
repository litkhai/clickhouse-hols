#!/usr/bin/env bash
# Run every lab in a release directory against a container of that exact
# ClickHouse version and report the first error per file.
#
#   .github/scripts/verify_release_lab.sh 26.5
#   .github/scripts/verify_release_lab.sh 26.5 --keep   # leave the container up
#
# The container is named clickhouse-<version-with-hyphens>, which is what the
# lab runners expect, so ./01-*.sh works while it is running.
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <version> [--keep]" >&2; exit 2; }
V="$1"
KEEP="${2:-}"
NAME="clickhouse-${V//./-}"
ROOT="$(git rev-parse --show-toplevel)"
DIR="$ROOT/local/releases/$V"

[ -d "$DIR" ] || { echo "no such release directory: $DIR" >&2; exit 2; }

docker rm -f "$NAME" >/dev/null 2>&1
docker run -d --name "$NAME" --ulimit nofile=262144:262144 \
    "clickhouse/clickhouse-server:$V" >/dev/null || {
    echo "could not start clickhouse/clickhouse-server:$V" >&2; exit 1; }

for _ in $(seq 1 40); do
    docker exec "$NAME" clickhouse-client -q "SELECT 1" >/dev/null 2>&1 && break
    sleep 3
done

build=$(docker exec "$NAME" clickhouse-client -q "SELECT version()" 2>/dev/null)
[ -n "$build" ] || { echo "server never became ready" >&2; docker rm -f "$NAME" >/dev/null; exit 1; }

echo "===== $V  (server $build)"
failed=0
for f in "$DIR"/[0-9][1-9]-*.sql; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    out=$(docker exec -i "$NAME" clickhouse-client --multiline --multiquery < "$f" 2>&1)
    err=$(echo "$out" | grep -m1 -oE 'Code: [0-9]+\. DB::Exception: [^\n]*' | cut -c1-140)
    if [ -z "$err" ]; then
        printf '  OK    %s\n' "$base"
    else
        printf '  FAIL  %-36s %s\n' "$base" "$err"
        failed=1
    fi
done

if [ "$KEEP" = "--keep" ]; then
    echo "  (container $NAME left running)"
else
    docker rm -f "$NAME" >/dev/null 2>&1
fi
exit "$failed"
