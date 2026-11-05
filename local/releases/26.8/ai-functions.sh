#!/bin/bash

# ClickHouse 26.8: AI functions (aiFilter, aiRedact) against the Anthropic API.
# Needs ANTHROPIC_API_KEY in ./.env (gitignored, mode 600). The key is never
# printed: the CREATE NAMED COLLECTION statement is built here and piped to
# clickhouse-client on stdin, and the client runs without --echo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="clickhouse-26-8"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "Missing $SCRIPT_DIR/.env - create it with one line: ANTHROPIC_API_KEY=<your key>"
    exit 1
fi
set -a
# shellcheck disable=SC1091
. "$SCRIPT_DIR/.env"
set +a
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ANTHROPIC_API_KEY is empty in $SCRIPT_DIR/.env"
    exit 1
fi

CH=(docker exec -i "$CONTAINER" clickhouse-client --multiline --multiquery)

# Always drop the collection (it holds the key), even if a query fails.
trap 'echo "DROP NAMED COLLECTION IF EXISTS ai_text_credentials;" | "${CH[@]}"' EXIT

echo "================================"
echo "ClickHouse 26.8: AI functions (Anthropic, claude-haiku-5-5)"
echo "================================"
echo ""

# Section 1 setup: the key goes in through stdin only.
printf "DROP NAMED COLLECTION IF EXISTS ai_text_credentials;
CREATE NAMED COLLECTION ai_text_credentials AS
    provider = 'anthropic',
    endpoint = 'https://api.anthropic.com/v1/messages',
    model = 'claude-haiku-5-5',
    api_version = '2023-06-01',
    api_key = '%s';\n" "$ANTHROPIC_API_KEY" | "${CH[@]}" || exit 1

# --ignore-error: section 4 shows a query that is supposed to fail.
"${CH[@]}" --ignore-error < "$SCRIPT_DIR/ai-functions.sql"

echo ""
echo "================================"
echo "Test complete!"
echo "================================"
