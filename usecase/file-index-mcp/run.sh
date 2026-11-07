#!/usr/bin/env bash
# End-to-end run of usecase/file-index-mcp on a local ClickHouse container. Writes results/NN-*.txt.
# Needs: Docker, Python 3 (for gen_tree.py), uv (indexer and MCP probe run in uv-managed Python 3.12).
# Usage: ./run.sh            # everything except the AI prompts (ai_prompts.sh) and teardown (./run.sh down)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE="clickhouse/clickhouse-server:${CH_VERSION:-26.10.3.7}"
NAME=fileidx-ch
PORT=${CH_HTTP_PORT:-18123}
CC_VERSION=1.12.0           # clickhouse-connect
MCP_VERSION=0.7.0           # mcp-clickhouse
MCP_SDK_VERSION=2.3.0       # mcp (Python SDK, used by mcp_probe.py as the client)
W=work; R=results

if [[ "${1:-}" == "down" ]]; then docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$W"; echo "down"; exit 0; fi

mkdir -p "$W" "$R"
ADMIN_PW=$(openssl rand -hex 12); IDX_PW=$(openssl rand -hex 12); AI_PW=$(openssl rand -hex 12)
umask 077; cat > "$W/.lab.env" <<EOF
CH_HOST=localhost
CH_PORT=$PORT
ADMIN_PW=$ADMIN_PW
IDX_PW=$IDX_PW
AI_PW=$AI_PW
MCP_VERSION=$MCP_VERSION
MCP_SDK_VERSION=$MCP_SDK_VERSION
EOF
umask 022

ch()   { docker exec "$NAME" clickhouse-client --password "$ADMIN_PW" "$@" </dev/null; }
chf()  { docker exec -i "$NAME" clickhouse-client --password "$ADMIN_PW" --multiquery < "$1"; }
ai()   { docker exec "$NAME" clickhouse-client --user ai_reader --password "$AI_PW" "$@" </dev/null; }
# expect_fail <label> <cmd...>: the command must fail; prints the first error line. Exits the run if it succeeds.
expect_fail() { local l=$1; shift; local out; if out=$("$@" 2>&1); then echo "UNEXPECTED SUCCESS: $l"; echo "$out"; exit 1; fi
                local e; e=$(grep -o 'Code: [0-9]*.*' <<<"$out" | head -1 | sed -E 's/ \(version [^)]*\)//' || true); echo "$l -> ${e:-$(tail -1 <<<"$out")}"; }
expect_ok()   { local l=$1; shift; local out; out=$("$@" 2>&1) || { echo "UNEXPECTED FAILURE: $l"; echo "$out"; exit 1; }; echo "$l -> ok: $(tr '\n' ' ' <<<"$out")"; }
P="--format PrettyCompactMonoBlock"
indexer() { env SCAN_ROOTS="docs=$PWD/$W/tree/docs,archive=$PWD/$W/tree/archive" EXCLUDE_DIRS=".git,node_modules" \
              CH_HOST=localhost CH_PORT="$PORT" CH_USER=indexer CH_PASSWORD="$IDX_PW" HASH_MAX_MB=8 TEXT_MAX_KB=4 "$@" \
              uv run -q --python 3.12 --with "clickhouse-connect==$CC_VERSION" python indexer.py; }
on_disk() { find "$W/tree" -type f | wc -l | tr -d ' '; }
in_view() { ch -q "SELECT count() FROM fileidx.files"; }

echo "== 00 up: $IMAGE"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --memory 3g -p "$PORT:8123" -e CLICKHOUSE_PASSWORD="$ADMIN_PW" \
  -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 --ulimit nofile=262144:262144 "$IMAGE" >/dev/null
for _ in $(seq 60); do ch -q "SELECT 1" >/dev/null 2>&1 && break; sleep 1; done
{ ch -q "SELECT version()"; date -u +%FT%TZ; } > "$R/00-version.txt"

echo "== 01 schema, the guide's view, users"
{
  chf sql/01-schema.sql; chf sql/02-view-invoker.sql
  sed "s/__INDEXER_PASSWORD__/$IDX_PW/; s/__AI_PASSWORD__/$AI_PW/" sql/03-users.sql | docker exec -i "$NAME" clickhouse-client --password "$ADMIN_PW" --multiquery
  ch -q "SELECT name, value FROM system.settings WHERE name IN ('default_normal_view_sql_security','default_view_definer')" $P
  ch -q "INSERT INTO fileidx.file_index (root,path,name,ext,size,mtime,is_dir,depth,scan_id) VALUES ('probe','p','p','',1,now(),0,0,0)"
  expect_fail "ai_reader SELECT on the guide's view (SQL SECURITY INVOKER by default)" ai -q "SELECT count() FROM fileidx.files"
  chf sql/04-view-definer.sql
  expect_ok   "ai_reader SELECT on the DEFINER view" ai -q "SELECT count() FROM fileidx.files"
  expect_fail "ai_reader SELECT on the base table" ai -q "SELECT count() FROM fileidx.file_index"
  ch -q "TRUNCATE TABLE fileidx.file_index"
} 2>&1 | tee "$R/01-view-security.txt"

echo "== 02 generate tree, first full scan"
rm -rf "$W/tree"
{
  python3 gen_tree.py --out "$W/tree"
  indexer MODE=full
  echo "files on disk: $(on_disk)   rows in view: $(in_view)"
  ch -q "SELECT count() AS rows, countIf(is_dir = 0) AS files, formatReadableSize(sum(size)) AS total, max(indexed_at) AS last_index FROM fileidx.files" $P
} 2>&1 | tee "$R/02-first-scan.txt"

echo "== 03 same full scan again (idempotency)"
{
  indexer MODE=full
  ch -q "SELECT (SELECT count() FROM fileidx.file_index) AS base_rows, (SELECT count() FROM fileidx.files) AS view_rows,
                (SELECT count() FROM system.parts WHERE database='fileidx' AND table='file_index' AND active) AS active_parts" $P
  echo "-- guide quality check 1 on the base table (guide: 'should be 0'):"
  ch -q "SELECT count() FROM (SELECT root, path, count() AS c FROM fileidx.file_index WHERE is_deleted = 0 GROUP BY root, path HAVING c > 1)"
  echo "-- the same check through the view:"
  ch -q "SELECT count() - uniqExact(root, path) FROM fileidx.files"
  echo "-- guide quality check 2 (rows per scan):"
  ch -q "SELECT scan_id, count() AS rows, min(indexed_at) AS started FROM fileidx.file_index GROUP BY scan_id ORDER BY scan_id DESC LIMIT 10" $P
} 2>&1 | tee "$R/03-rescan.txt"

echo "== 04 changes: delete 5, rename 1, modify 1; incremental scan; then full scan with delete detection"
{
  last=$(ch -q "SELECT toUnixTimestamp(max(indexed_at)) FROM fileidx.file_index")
  sleep 2
  T=$W/tree/docs
  find "$T/finance" -name '*.pdf' | sort | head -5 | while read -r v; do rm "$v"; echo "deleted  ${v#"$W/tree/"}"; done
  ren=$(find "$T/hr" -name '*.xlsx' | sort | head -1); mv "$ren" "${ren%.xlsx}_renamed.xlsx"; echo "renamed  ${ren#"$W/tree/"} (mv keeps mtime)"
  mod=$(find "$T/sales" -name '*.md' | sort | head -1); echo "appended line" >> "$mod"; echo "modified ${mod#"$W/tree/"}"
  echo "files on disk: $(on_disk)"
  echo "-- incremental scan, SINCE = last indexed_at ($last):"
  inc=$(indexer MODE=incremental SINCE="$last"); echo "$inc"
  inc_id=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['scan_id'])" "$inc")
  echo "rows in view: $(in_view)   renamed path in view: $(ch -q "SELECT count() FROM fileidx.files WHERE path LIKE '%_renamed.xlsx'")"
  echo "-- the guide's delete-detection SQL after this incremental scan would mark this many live files deleted:"
  ch -q "SELECT count() FROM fileidx.file_index FINAL WHERE is_deleted = 0 AND scan_id < $inc_id"
  expect_fail "indexer refuses DETECT_DELETES after an incremental scan" indexer MODE=incremental SINCE="$last" DETECT_DELETES=1
  echo "-- full scan + delete detection:"
  indexer MODE=full DETECT_DELETES=1
  echo "files on disk: $(on_disk)   rows in view: $(in_view)"
  ch -q "SELECT path FROM fileidx.file_index FINAL WHERE is_deleted = 1 ORDER BY path" $P
  echo "renamed path in view: $(ch -q "SELECT count() FROM fileidx.files WHERE path LIKE '%_renamed.xlsx'")"
} 2>&1 | tee "$R/04-deletes.txt"

echo "== 05 read-only user: positive and negative controls (clickhouse-client)"
{
  expect_ok   "ai_reader SELECT count() FROM fileidx.files" ai -q "SELECT count() FROM fileidx.files"
  expect_fail "ai_reader INSERT INTO fileidx.file_index" ai -q "INSERT INTO fileidx.file_index (root,path,name,ext,size,mtime,is_dir,depth,scan_id) VALUES ('x','x','x','',0,now(),0,0,0)"
  expect_fail "ai_reader DROP TABLE fileidx.file_index" ai -q "DROP TABLE fileidx.file_index"
  expect_fail "ai_reader DROP VIEW fileidx.files" ai -q "DROP VIEW fileidx.files"
  expect_fail "ai_reader CREATE TABLE default.t" ai -q "CREATE TABLE default.t (x UInt8) ENGINE = Memory"
  expect_fail "ai_reader SET max_result_rows = 0 (readonly = 1)" ai -q "SET max_result_rows = 0"
  expect_fail "ai_reader SELECT every path (max_result_rows = 20000)" ai -q "SELECT root, path FROM fileidx.files"
  expect_ok   "ai_reader the same with LIMIT 50" bash -c "docker exec $NAME clickhouse-client --user ai_reader --password $AI_PW -q 'SELECT count() FROM (SELECT root, path FROM fileidx.files LIMIT 50)' </dev/null"
  expect_ok   "indexer INSERT (control: the INSERT itself is valid)" docker exec "$NAME" clickhouse-client --user indexer --password "$IDX_PW" -q \
              "INSERT INTO fileidx.file_index (root,path,name,ext,size,mtime,is_dir,depth,scan_id,is_deleted) VALUES ('control','c','c','',0,now(),0,0,0,1)"
} 2>&1 | tee "$R/05-readonly.txt"

echo "== 06 the guide's skip indexes: which predicates use them"
{
  chf sql/05-skip-indexes.sql
  for pred in "positionCaseInsensitive(name, 'contract') > 0" "multiSearchAnyCaseInsensitive(name, ['계약','contract'])" \
              "name LIKE '%contract%'" "hasToken(text_excerpt, 'renews')" "positionCaseInsensitive(text_excerpt, '연장') > 0" \
              "text_excerpt LIKE '%연장%'" "hasAnyTokens(text_excerpt, ['renews'])"; do
    used=$(ch -q "EXPLAIN indexes = 1 SELECT count() FROM fileidx.file_index WHERE $pred" | grep -oE "Name: idx_[a-z_]+" | sort -u | tr '\n' ' ' || true)
    echo "$pred  ->  ${used:-no skip index}"
  done
} 2>&1 | tee "$R/06-skip-indexes.txt"

echo "== 07 primary-key lookup: rows read through the view, the base table, and the no-view design"
{
  sed "s/__AI_PASSWORD__/$AI_PW/" sql/06-no-view.sql | docker exec -i "$NAME" clickhouse-client --password "$ADMIN_PW" --multiquery
  K="root = 'docs' AND path = 'legal/contracts/contract_001.docx'"
  ai -q "SELECT count() FROM fileidx.files WHERE $K /* pk-view */" >/dev/null
  ch -q "SELECT count() FROM fileidx.file_index FINAL WHERE is_deleted = 0 AND $K /* pk-base */" >/dev/null
  docker exec "$NAME" clickhouse-client --user ai_reader_b --password "$AI_PW" -q "SELECT count() FROM fileidx.file_index_b WHERE $K /* pk-noview */" </dev/null >/dev/null
  echo "rows visible: view $(ai -q 'SELECT count() FROM fileidx.files')  no-view $(docker exec "$NAME" clickhouse-client --user ai_reader_b --password "$AI_PW" -q 'SELECT count() FROM fileidx.file_index_b' </dev/null)"
  expect_fail "ai_reader_b turns FINAL off" docker exec "$NAME" clickhouse-client --user ai_reader_b --password "$AI_PW" -q "SELECT count() FROM fileidx.file_index_b SETTINGS final = 0"
  expect_fail "ai_reader_b reads scan_id (not granted)" docker exec "$NAME" clickhouse-client --user ai_reader_b --password "$AI_PW" -q "SELECT scan_id FROM fileidx.file_index_b LIMIT 1"
  ch -q "SYSTEM FLUSH LOGS"
  ch -q "SELECT extract(query, 'pk-[a-z]+') AS how, user, read_rows, Settings['final'] AS final FROM system.query_log
         WHERE type = 'QueryFinish' AND match(query, 'pk-(view|base|noview) ') AND query NOT LIKE '%system.query_log%' ORDER BY event_time_microseconds" $P
  ch -q "EXPLAIN indexes = 1 SELECT count() FROM fileidx.files WHERE $K" | grep -E "ReadFrom|Filter column"
} 2>&1 | tee "$R/07-view-pushdown.txt"

echo "== 08 MCP probe (mcp-clickhouse $MCP_VERSION over stdio, user ai_reader)"
uv run -q --python 3.12 --with "mcp==$MCP_SDK_VERSION" python mcp_probe.py 2>&1 | tee "$R/08-mcp-probe.txt"

echo "done. AI prompts: ./ai_prompts.sh   teardown: ./run.sh down"
