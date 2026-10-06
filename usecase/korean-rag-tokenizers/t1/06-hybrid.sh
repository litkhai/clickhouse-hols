#!/usr/bin/env bash
# Step 6 (T1): vector search and hybrid ranking with bge-m3 embeddings from a
# local Ollama. It needs the container that `tools/hol run ... --keep` leaves
# behind, with steps 0 to 5 already run in it:
#
#   python3 tools/hol run usecase/korean-rag-tokenizers --keep
#   usecase/korean-rag-tokenizers/t1/06-hybrid.sh
#
# It lives in t1/ so that hol's top-level NN-*.sql glob never picks it up and
# steps 1 to 5 stay T0.
#
# What it does, in order:
#   1. checks the container, the lab tables, Ollama and the model
#   2. prints the Ollama and model versions, so a saved run log records them
#   3. gives the container's `default` user the right to create a named
#      collection (a users.d file + SYSTEM RELOAD CONFIG)
#   4. pipes 06-hybrid.sql through clickhouse-client
#
# Environment (all optional):
#   CONTAINER   the lab container        (hol-usecase-korean-rag-tokenizers)
#   OLLAMA_URL  Ollama, as seen from this machine   (http://localhost:11434)
#   MODEL       the embedding model to look for     (bge-m3)
#
# OLLAMA_URL and MODEL only steer the checks here. 06-hybrid.sql itself reaches
# Ollama from inside the container as host.docker.internal:11434 and embeds with
# 'bge-m3' into a 1024-dimension index; edit it if yours differ.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="${CONTAINER:-hol-usecase-korean-rag-tokenizers}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
MODEL="${MODEL:-bge-m3}"

die() { echo "error: $*" >&2; exit 1; }

# 1a. the container
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" != "true" ]; then
    die "container '$CONTAINER' is not running. Start it and run steps 0-5 first:
  python3 tools/hol run usecase/korean-rag-tokenizers --keep"
fi

# 1b. the tables this step reads (step 4 writes keyword_ranked)
if [ "$(docker exec "$CONTAINER" clickhouse-client -q 'EXISTS TABLE korean_rag.keyword_ranked')" != "1" ]; then
    die "korean_rag.keyword_ranked is missing in '$CONTAINER'; run steps 0-5 first:
  python3 tools/hol run usecase/korean-rag-tokenizers --keep"
fi

# 1c. Ollama and the model. The digest identifies the exact weights that made the vectors.
tags="$(curl -fsS --max-time 10 "$OLLAMA_URL/api/tags")" \
    || die "cannot reach Ollama at $OLLAMA_URL (start it with 'ollama serve', or set OLLAMA_URL)"

if ! digest="$(printf '%s' "$tags" | python3 -c '
import json, sys
want = sys.argv[1]
for m in json.load(sys.stdin).get("models", []):
    if m["name"] == want or m["name"].startswith(want + ":"):
        print(m["name"] + " " + m["digest"])
        break
else:
    sys.exit(1)
' "$MODEL")"; then
    echo "error: model '$MODEL' is not in $OLLAMA_URL/api/tags. Pull it first (this script does not):" >&2
    echo "  ollama pull $MODEL" >&2
    exit 1
fi

# 2. versions for the run log
echo "== Ollama"
if command -v ollama >/dev/null 2>&1; then
    ollama --version 2>&1 | head -n 1
else
    echo "ollama CLI not on PATH; server says: $(curl -fsS --max-time 10 "$OLLAMA_URL/api/version")"
fi
echo "model  $digest"
echo "== ClickHouse"
docker exec "$CONTAINER" clickhouse-client -q 'SELECT version()'

# 1d. the container must be able to reach the host. Docker Desktop provides the
# name; on Linux start the container with --add-host=host.docker.internal:host-gateway.
docker exec "$CONTAINER" getent hosts host.docker.internal >/dev/null \
    || die "'$CONTAINER' cannot resolve host.docker.internal, so aiEmbed cannot reach Ollama.
On Linux, start the container with --add-host=host.docker.internal:host-gateway."

# 3. named_collection_control for the default user, then reload
echo "== named collection rights"
docker exec -i "$CONTAINER" sh -c 'cat > /etc/clickhouse-server/users.d/zz-named-collections.xml' <<'EOF'
<clickhouse><users><default><named_collection_control>1</named_collection_control></default></users></clickhouse>
EOF
docker exec "$CONTAINER" clickhouse-client -q 'SYSTEM RELOAD CONFIG'

# 4. the step itself
echo "== 06-hybrid.sql"
docker exec -i "$CONTAINER" clickhouse-client --multiline --multiquery < "$HERE/06-hybrid.sql"
