#!/usr/bin/env bash
# 02-load.sh — bench.ev_plain: Langfuse 4.56.0's events_full schema, filled with synthetic observations.
#   TRACES (default 100000) traces × 4 observations over 7 days. Also bench.core_plain, the
#   200-character preview table Langfuse keeps as events_core (its list pages read it).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_lab_env
TRACES="${TRACES:-100000}"

ddl() { # ddl <table> [codec-for-input-output] — Langfuse's DDL with a new name (and codec)
  local codec="${2:-ZSTD(3)}"
  sed -e "s/default\.events_full/bench.$1/" \
      -e "s/\`input\` String CODEC(ZSTD(3))/\`input\` String CODEC($codec)/" \
      -e "s/\`output\` String CODEC(ZSTD(3))/\`output\` String CODEC($codec)/" \
      "$LAB_DIR/sql/events_full.langfuse-4.56.0.sql"
}

# Vocabulary: Korean banking/chat words and English tech words; generate.sql samples it skewed
# (a few words very common), which compresses roughly like real prompt text.
VOCAB="['고객','계좌','잔액','이체','한도','대출','금리','상환','카드','결제','승인','취소','환불','수수료','예금','적금','만기','해지','본인','인증','비밀번호','변경','조회','내역','거래','입금','출금','지점','영업일','상담','문의','답변','확인','처리','요청','안내','정책','규정','조항','근거','기준','신청','서류','제출','심사','결과','통지','연체','이자','원금','월','일','년','원','만원','부터','까지','에서','으로','에게','그리고','하지만','따라서','경우','때문에','관련','해당','다음','이전','현재','최근','모든','일부','가능','불가','필요','완료','대기','오류','다시','시도','the','customer','account','balance','transfer','limit','loan','rate','card','payment','refund','fee','policy','section','according','to','please','confirm','request','status','error','retry','user','assistant','system','tool','context','document','retrieved','score','answer','question','summary','step','result','json','id','date','amount','KRW','branch','app','session','trace','model','token','latency','is','are','was','not','and','or','for','with','this','that','in','on','of','a','an','be','can','will','should','must','may','if','then','when','which','from','by','as','at','it']"

say "bench database and tables"
ch -q "CREATE DATABASE IF NOT EXISTS bench"
ch -q "DROP TABLE IF EXISTS bench.ev_plain SYNC"
ddl ev_plain | ch --multiquery
ch -q "DROP TABLE IF EXISTS bench.core_plain SYNC"
ddl core_plain | ch --multiquery

say "generate $TRACES traces × 4 observations"
t0=$(date +%s)
ch --param_traces "$TRACES" --param_vocab "$VOCAB" --multiquery < "$LAB_DIR/sql/generate.sql"
ch -q "OPTIMIZE TABLE bench.ev_plain FINAL"
ch -q "INSERT INTO bench.core_plain SELECT * REPLACE (leftUTF8(input, 200) AS input, leftUTF8(output, 200) AS output) FROM bench.ev_plain"
ch -q "OPTIMIZE TABLE bench.core_plain FINAL"
echo "  generated in $(( $(date +%s) - t0 )) s"

ch -q "
SELECT count() AS rows, uniqExact(trace_id) AS traces,
       formatReadableSize(sum(length(input))) AS input_bytes, formatReadableSize(sum(length(output))) AS output_bytes,
       round(avg(length(input))) AS avg_input_bytes, round(avg(lengthUTF8(input))) AS avg_input_chars,
       quantiles(0.5, 0.9, 0.99)(length(input)) AS input_bytes_p50_p90_p99,
       countIf(position(input, 'rx77refund') > 0) AS marker_rows,
       min(start_time), max(start_time)
FROM bench.ev_plain FORMAT Vertical"
