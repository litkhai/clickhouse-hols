#!/usr/bin/env bash
# 08-in-place-probe.sh — can ClickHouse encrypt a column "in place", so that Langfuse keeps writing and
# reading `input` by that name while only ciphertext is stored? Two candidate column kinds:
#   ALIAS      store input_enc, expose input as ALIAS dec(input_enc)   → an INSERT into input must work
#   EPHEMERAL  accept input on INSERT, store input_enc DEFAULT enc(…) → a SELECT of input must work
# Both fail, which is why the methods in this lab either change what Langfuse receives (callback,
# SDK hook) or encrypt below the column (codec, disk).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
PASSES=0; FAILS=0
q() { ch -q "$1" 2>&1 | grep -oE 'Code: [0-9]+' | head -n 1; }

ch -q "DROP DATABASE IF EXISTS enc_probe"
ch -q "CREATE DATABASE enc_probe"
ch -q "CREATE TABLE enc_probe.t_alias (id UInt32, input_enc String, input String ALIAS concat('dec(', input_enc, ')')) ENGINE = MergeTree ORDER BY id"
check "INSERT into an ALIAS column is refused (NO_SUCH_COLUMN_IN_TABLE)" "Code: 16" "$(q "INSERT INTO enc_probe.t_alias (id, input) VALUES (1, 'secret')")"
ch -q "CREATE TABLE enc_probe.t_eph (id UInt32, input String EPHEMERAL, input_enc String DEFAULT concat('enc(', input, ')')) ENGINE = MergeTree ORDER BY id"
ch -q "INSERT INTO enc_probe.t_eph (id, input) VALUES (1, 'secret')"
check "EPHEMERAL accepts the value and stores only the transformed copy" "enc(secret)" "$(ch -q 'SELECT input_enc FROM enc_probe.t_eph')"
check "SELECT of the EPHEMERAL column is refused (NO_SUCH_COLUMN_IN_TABLE)" "Code: 16" "$(q 'SELECT input FROM enc_probe.t_eph')"
ch -q "DROP DATABASE enc_probe"
echo; echo "08-in-place-probe: $PASSES PASS, $FAILS FAIL"
[ "$FAILS" -eq 0 ]
