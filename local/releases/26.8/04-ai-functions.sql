-- ClickHouse 26.8 — AI functions: aiFilter and aiRedact
--
--   SELECT * FROM tickets WHERE aiFilter(body, 'the customer asks for a refund')
--
-- A function call that sends the row to an LLM. Beta in 26.8 (every ai_function_*
-- setting is tier Beta), the output is non-deterministic, and the text you pass
-- goes to the provider. Treat the result as untrusted: the input can steer the
-- model (prompt injection), so validate it before using it to build SQL, shell
-- commands or access decisions.
--
-- Provider: Anthropic, model claude-haiku-5-5, through a named collection that
-- 04-ai-functions.sh creates from ./.env before this file runs and drops
-- afterwards. The key is never in this file.
--
-- aiSimilarity is not run: Anthropic is chat-only in ClickHouse's provider list
-- (docs: reference/functions/regular-functions/ai-functions, "Supported
-- providers"), and aiSimilarity needs an embeddings endpoint.

-- Note on temperature: aiFilter and aiRedact send temperature = 0.0 by default, and
-- claude-haiku-5-5 rejects that request: HTTP 400 [invalid_request_error]
-- `temperature` is deprecated for this model. The function-specific parameter map
-- accepts it as a string, so every call below passes map('temperature', '1'), which
-- the API accepts. An empty string is not allowed ("must be a number"). The cost:
-- the answers are no longer greedy, so two runs can differ.

SELECT '════════ 1. Credentials ════════' AS section;

-- The shape of the named collection the shell script created (key omitted):
--
--   CREATE NAMED COLLECTION ai_text_credentials AS
--       provider    = 'anthropic',
--       endpoint    = 'https://api.anthropic.com/v1/messages',
--       model       = 'claude-haiku-5-5',
--       api_version = '2023-06-01',
--       api_key     = '<from .env>';
--
-- A function finds it from the 'credentials' key of its parameter map, or else
-- from this setting (text functions: aiGenerate, aiClassify, aiFilter, aiExtract,
-- aiTranslate, aiRedact):
SET ai_function_text_default_credentials = 'ai_text_credentials';

-- Marks where this run starts, so section 6 counts only this run.
SELECT 'run start' AS marker SETTINGS log_comment = 'ai97_start';

SELECT name, tier FROM system.settings
WHERE name LIKE 'ai_function%' ORDER BY name;

-- The collection exists, and the key is masked when you look at it.
SELECT name, collection['provider'] AS provider, collection['model'] AS model,
       collection['api_key'] AS api_key
FROM system.named_collections WHERE name = 'ai_text_credentials';

SELECT '════════ 2. Sample data: 20 made-up support tickets ════════' AS section;

-- Everything below is fake: names, 010-0000-xxxx numbers, @example.com emails.
CREATE OR REPLACE TABLE tickets (id UInt8, body String) ENGINE = Memory;
INSERT INTO tickets VALUES
 (1,  'I want a refund. The order arrived broken. My name is Minjun Kim, phone 010-0000-0001.'),
 (2,  '배송이 너무 늦어요. 언제 도착하나요? 연락처 010-0000-0002, 이름은 박서연입니다.'),
 (3,  'How do I change the password for my account? Reply to jane.doe@example.com please.'),
 (4,  '환불해 주세요. 상품이 설명과 달라요. 주문자 이지훈, 이메일 jihoon.lee@example.com'),
 (5,  'The app crashes every time I open the dashboard. Contact: Sarah Park, 010-0000-0005.'),
 (6,  '결제가 두 번 됐습니다. 한 건을 취소하고 돈을 돌려주세요. 010-0000-0006 최유진'),
 (7,  'Great service, thank you! No issue, just wanted to say so. - Tom Lee, tom.lee@example.com'),
 (8,  '비밀번호 재설정 메일이 오지 않아요. choi.mina@example.com 으로 보내주세요.'),
 (9,  'Please cancel my subscription and refund this month''s charge. Jisoo Han, 010-0000-0009.'),
 (10, '앱에서 로그인이 안 됩니다. 오류 코드는 E-401입니다. 정하늘 010-0000-0010'),
 (11, 'Can you add dark mode to the dashboard? Thanks, Alex Cho (alex.cho@example.com).'),
 (12, '주문한 상품이 아직도 안 왔습니다. 환불 또는 재배송 부탁드립니다. 강민서 010-0000-0012'),
 (13, 'My invoice shows the wrong company name. Please fix it. Daniel Yoon, 010-0000-0013.'),
 (14, '서비스가 정말 좋아요. 문의는 없습니다. 감사합니다! - 오지원'),
 (15, 'I was charged after I cancelled. Send my money back. Hana Seo, hana.seo@example.com'),
 (16, '배송지 주소를 바꾸고 싶습니다. 새 주소 문의는 010-0000-0016 윤도현 에게 전화 주세요.'),
 (17, 'The export to CSV button does nothing. Browser: Firefox. Reported by Chris Jung.'),
 (18, '제품 불량으로 환불 요청합니다. 사진 첨부했습니다. 신하준, shin.hajun@example.com'),
 (19, 'What are your support hours? Asking for Emily Shin, 010-0000-0019.'),
 (20, '영수증을 다시 보내주세요. 이메일 kim.soyeon@example.com, 감사합니다.');

SELECT count() AS tickets FROM tickets;

SELECT '════════ 3. aiFilter in WHERE: tickets asking for a refund ════════' AS section;

-- aiFilter(text, condition) returns UInt8, one API call per row. Anything the model
-- answers other than 'true' counts as 0.
SELECT id, body
FROM tickets
WHERE aiFilter(body, 'the customer asks for a refund or for their money back', map('temperature', '1'))
ORDER BY id
SETTINGS log_comment = 'ai97_filter';

SELECT '════════ 4. aiRedact: before and after ════════' AS section;

-- aiRedact(text, categories[, params]) returns the whole text with PII replaced.
-- Best effort: the docs warn it is not a safe anonymisation step and works best on
-- well-formed English, so read the Korean rows with that in mind.
SELECT id, body AS before, aiRedact(body, ['name', 'email', 'phone number'], map('temperature', '1', 'max_tokens', '512')) AS after
FROM tickets
WHERE id IN (1, 2, 4, 9)
ORDER BY id
SETTINGS log_comment = 'ai97_redact'
FORMAT Vertical;

SELECT '════════ 5. Limits: ai_function_max_api_calls_per_query ════════' AS section;

-- Positive: 8 rows, limit 10. All 8 calls are allowed.
SELECT count() AS refund_rows_of_first_8
FROM tickets
WHERE id <= 8 AND aiFilter(body, 'the customer asks for a refund or for their money back', map('temperature', '1'))
SETTINGS ai_function_max_api_calls_per_query = 10, log_comment = 'ai97_limit_ok';

-- Negative: 8 rows, limit 3, ai_function_throw_on_quota_exceeded = 1 (the default).
-- The query stops with the quota error. The cap is exact: a slot is reserved
-- before each request is sent.
SELECT count() AS refund_rows_of_first_8
FROM tickets
WHERE id <= 8 AND aiFilter(body, 'the customer asks for a refund or for their money back', map('temperature', '1'))
SETTINGS ai_function_max_api_calls_per_query = 3, log_comment = 'ai97_limit_hit';

-- Same limit with the throw switched off: rows over the quota are skipped
-- (aiFilter returns 0 for them) and the query succeeds, so a count can be silently low.
SELECT count() AS refund_rows_of_first_8
FROM tickets
WHERE id <= 8 AND aiFilter(body, 'the customer asks for a refund or for their money back', map('temperature', '1'))
SETTINGS ai_function_max_api_calls_per_query = 3, ai_function_throw_on_quota_exceeded = 0,
         log_comment = 'ai97_limit_skip';

SELECT '════════ 6. What it cost: ProfileEvents per query ════════' AS section;

SYSTEM FLUSH LOGS;

SELECT
    log_comment,
    type,
    ProfileEvents['AIAPICalls']     AS api_calls,
    ProfileEvents['AIRowsProcessed'] AS rows_processed,
    ProfileEvents['AIRowsSkipped']  AS rows_skipped,
    ProfileEvents['AIInputTokens']  AS input_tokens,
    ProfileEvents['AIOutputTokens'] AS output_tokens
FROM system.query_log
WHERE log_comment LIKE 'ai97_%' AND log_comment != 'ai97_start'
  AND type IN ('QueryFinish', 'ExceptionWhileProcessing')
  AND event_time_microseconds >= (SELECT max(event_time_microseconds) FROM system.query_log WHERE log_comment = 'ai97_start')
ORDER BY event_time;

SELECT
    sum(ProfileEvents['AIAPICalls'])    AS total_api_calls,
    sum(ProfileEvents['AIInputTokens'])  AS total_input_tokens,
    sum(ProfileEvents['AIOutputTokens']) AS total_output_tokens,
    round(total_input_tokens * 0.10 / 1e6 + total_output_tokens * 0.50 / 1e6, 5) AS usd_at_list_price
FROM system.query_log
WHERE log_comment LIKE 'ai97_%' AND log_comment != 'ai97_start'
  AND type IN ('QueryFinish', 'ExceptionWhileProcessing')
  AND event_time_microseconds >= (SELECT max(event_time_microseconds) FROM system.query_log WHERE log_comment = 'ai97_start');
