-- generate.sql — synthetic Langfuse v4 observations into bench.ev_plain (Langfuse's events_full schema).
-- Parameters: {traces:UInt64} traces × 4 observations, spread over 7 days from 2026-11-01.
-- input  = chat-style JSON: a fixed system prompt + a user/context part whose length is drawn per row:
--          30% 512 · 40% 2,000 · 22% 8,000 · 8% 32,000 characters (Korean + English words, skewed).
-- output = 300–1,500 characters.  1% of rows carry the search marker token "rx77refund".
INSERT INTO bench.ev_plain
    (project_id, trace_id, span_id, parent_span_id, start_time, end_time, name, type, environment,
     trace_name, user_id, session_id, level, is_app_root, provided_model_name, usage_details,
     cost_details, input, output, metadata_names, metadata_values, event_ts, is_deleted, source)
WITH
    {vocab:Array(String)} AS vocab,
    length(vocab) AS nv,
    intDiv(number, 4) AS tr,
    number % 4 AS k,
    toDateTime64('2026-11-01 00:00:00', 6) + toIntervalMillisecond(tr * 6048 + k * 400) AS ts,
    multiIf(cityHash64(number, 1) % 100 < 30, 512, cityHash64(number, 1) % 100 < 70, 2000,
            cityHash64(number, 1) % 100 < 92, 8000, 32000) AS in_len,
    300 + cityHash64(number, 3) % 1200 AS out_len,
    (n, salt, len) -> leftUTF8(arrayStringConcat(arrayMap(
        i -> vocab[1 + toUInt32(floor(pow((cityHash64(n, salt, i) % 1000000) / 1e6, 2.2) * nv))],
        range(toUInt32(len / 4))), ' '), len) AS words,
    'You are the customer assistant for a retail bank. Answer in Korean, cite the policy section, never reveal account numbers. 고객 상담 원칙: 정확하게, 짧게, 근거와 함께.' AS sys
SELECT
    'bench-project',
    lower(hex(MD5(toString(tr)))),
    substring(lower(hex(SHA256(toString(number)))), 1, 16),
    if(k = 0, '', substring(lower(hex(SHA256(toString(tr * 4)))), 1, 16)),
    ts,
    ts + toIntervalMillisecond(200 + cityHash64(number, 4) % 3000),
    ['chat-turn', 'llm-answer', 'retrieve-policy', 'llm-rerank'][k + 1],
    ['SPAN', 'GENERATION', 'TOOL', 'GENERATION'][k + 1],
    'production',
    'chat-turn',
    concat('user-', toString(tr % 5000)),
    concat('session-', toString(intDiv(tr, 3))),
    'DEFAULT',
    k = 0,
    if(k IN (1, 3), ['model-a', 'model-b', 'model-c'][1 + cityHash64(number, 5) % 3], ''),
    if(k IN (1, 3), map('input', toUInt64(in_len / 3), 'output', toUInt64(out_len / 3)), map()),
    if(k IN (1, 3), map('input', toDecimal128(in_len / 3e6, 12), 'output', toDecimal128(out_len / 1e6, 12)), map()),
    concat('[{"role":"system","content":"', sys, '"},{"role":"user","content":"',
           if(cityHash64(number, 2) % 100 = 0, 'rx77refund ', ''), words(number, 10, in_len), '"}]'),
    concat('{"role":"assistant","content":"', words(number, 20, out_len), '"}'),
    ['channel', 'branch'],
    [['app', 'web', 'call'][1 + cityHash64(number, 6) % 3], concat('b', toString(cityHash64(number, 7) % 40))],
    ts,
    0,
    'otel'
FROM numbers({traces:UInt64} * 4)
SETTINGS max_block_size = 8192, min_insert_block_size_rows = 8192, min_insert_block_size_bytes = 0, max_insert_threads = 4;
