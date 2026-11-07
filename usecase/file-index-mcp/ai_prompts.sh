#!/usr/bin/env bash
# Ask an AI assistant (Claude Code in print mode) the lab's prompts through mcp-clickhouse as ai_reader.
# Needs run.sh to have run (container up, work/.lab.env) and a logged-in `claude` CLI.
# This uses your Claude account; each prompt is capped at $MAX_USD (default 0.50).
# (--tools "" would also hide the MCP tools, so built-in tools are denied by name instead.)
# Usage: ./ai_prompts.sh [prompt-id ...]     (ids from prompts.tsv; default: all)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
set -a; . work/.lab.env; set +a
MODEL=${MODEL:-sonnet}; MAX_USD=${MAX_USD:-0.50}
OUT=results/ai; CWD=work/ai-cwd; mkdir -p "$OUT" "$CWD"

# A venv, not uvx: print mode answers before a slow-starting MCP server connects (uvx cold start left it "pending").
[[ -x work/mcp-venv/bin/mcp-clickhouse ]] || { uv venv -q --python 3.12 work/mcp-venv && uv pip install -q --python work/mcp-venv/bin/python "mcp-clickhouse==$MCP_VERSION"; }
cat > work/mcp.json <<EOF
{"mcpServers": {"fileidx": {"command": "$PWD/work/mcp-venv/bin/mcp-clickhouse", "args": [],
  "env": {"CLICKHOUSE_HOST": "$CH_HOST", "CLICKHOUSE_PORT": "$CH_PORT", "CLICKHOUSE_USER": "ai_reader",
          "CLICKHOUSE_PASSWORD": "$AI_PW", "CLICKHOUSE_SECURE": "false"}}}}
EOF
BARE="당신은 파일 색인 데이터베이스에 MCP(fileidx)로 연결된 데이터 도우미입니다. 한국어로 답하세요."

while IFS=$'\t' read -r id ctx prompt; do
  [[ "$id" == id || -z "$id" ]] && continue
  if [[ $# -gt 0 && ! " $* " == *" $id "* ]]; then continue; fi
  if [[ "$ctx" == rules ]]; then sys="$BARE"$'\n\n'"$(cat project-prompt.md)"; else sys="$BARE"; fi
  echo "== $id ($ctx): $prompt"
  ( cd "$CWD" && claude -p "$prompt" --model "$MODEL" --system-prompt "$sys" \
      --mcp-config ../mcp.json --strict-mcp-config --setting-sources project \
      --disallowedTools Bash Edit Write Read Glob Grep WebFetch WebSearch Agent NotebookEdit \
      --allowedTools mcp__fileidx__run_query mcp__fileidx__list_tables mcp__fileidx__list_databases \
      --max-budget-usd "$MAX_USD" --output-format stream-json --verbose ) > "$OUT/$id.jsonl" || echo "   (claude exited $?)"
  python3 render_transcript.py "$OUT/$id.jsonl" "$id" "$ctx" "$prompt" > "$OUT/$id.md"
  tail -3 "$OUT/$id.md"
done < prompts.tsv

# Independent checks of the numbers in the answers (admin, on the view)
docker exec -i fileidx-ch clickhouse-client --password "$ADMIN_PW" --multiquery --format TSV < sql/07-ground-truth.sql > results/09-ground-truth.txt
