#!/usr/bin/env bash
# run.sh: the lab on a fresh container, output to results/<version>.txt.
#
#   ./run.sh              every NN-*.sql in order; 06-topn.sql is run REPEAT times (default 5)
#   KEEP=1 ./run.sh       leave the container running afterwards (name musz-<tag>)
#   REPEAT=3 ./run.sh     fewer timing runs
#
# The image tag comes from lab.yaml (`clickhouse:`). Needs Docker only.
set -euo pipefail

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LAB/../.." && pwd)"
TAG="$(sed -n 's/^clickhouse: *"*\([^"]*\)"*.*$/\1/p' "$LAB/lab.yaml")"
REPEAT="${REPEAT:-5}"
NAME="musz-${TAG//./-}"
OUT="$LAB/results/$TAG.txt"
SECCOMP="$ROOT/local/oss-docker/seccomp-profile.json"

[ -n "$TAG" ] || { echo "no clickhouse: tag in lab.yaml" >&2; exit 1; }

cleanup() { [ "${KEEP:-0}" = 1 ] || docker rm -f -v "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker rm -f -v "$NAME" >/dev/null 2>&1 || true
args=(docker run -d --name "$NAME" --ulimit nofile=262144:262144
      -e CLICKHOUSE_PASSWORD= -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1)
[ -f "$SECCOMP" ] && args+=(--security-opt "seccomp=$SECCOMP")
"${args[@]}" "clickhouse/clickhouse-server:$TAG" >/dev/null
for _ in $(seq 1 60); do
    docker exec "$NAME" clickhouse-client -q "SELECT 1" >/dev/null 2>&1 && break
    sleep 1
done

client() { docker exec -i "$NAME" clickhouse-client --multiquery --format PrettyCompactMonoBlock "$@"; }

host_cpu() {
    if [ "$(uname -s)" = Darwin ]; then sysctl -n machdep.cpu.brand_string 2>/dev/null || true
    else sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1; fi
}

others() {
    docker stats --no-stream --format '{{.Name}} {{.CPUPerc}}' | grep -v "^$NAME " || true
}

mkdir -p "$LAB/results"
{
    echo "# workload/mv-uniq-state-size: run.sh output"
    echo "date (UTC):  $(date -u '+%Y-%m-%d %H:%M')"
    echo "image:       clickhouse/clickhouse-server:$TAG"
    echo "version():   $(docker exec "$NAME" clickhouse-client -q 'SELECT version()')"
    echo "host:        $(uname -sm), $(host_cpu)"
    echo "docker VM:   $(docker info --format '{{.NCPU}} CPUs, {{.MemTotal}} bytes memory, {{.OperatingSystem}}')"
    echo "timing runs: $REPEAT"
    echo "other containers at start (CPU%):"
    others | sed 's/^/  /'
    echo
    for f in "$LAB"/[0-9][0-9]-*.sql; do
        base="$(basename "$f")"
        [ "$base" = 99-cleanup.sql ] && continue   # the container goes away; KEEP=1 keeps the data
        echo "=================== $base"
        start=$(date +%s)
        if [ "$base" = 06-topn.sql ]; then
            echo "other containers before the timing runs (CPU%):"
            others | sed 's/^/  /'
            # no --format here: the client's --format would override the file's FORMAT Null
            for _ in $(seq 1 "$REPEAT"); do docker exec -i "$NAME" clickhouse-client --multiquery < "$f"; done
        else
            client --echo < "$f"
        fi
        echo "------------------- $base: $(( $(date +%s) - start )) s"
        echo
    done
} 2>&1 | tee "$OUT"
