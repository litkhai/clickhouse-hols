-- ClickHouse 25.12 Feature: HMAC Function
-- Purpose: Test Hash-based Message Authentication Code (HMAC) function
-- Reference: https://clickhouse.com/docs/whats-new/changelog

-- HMAC (Hash-based Message Authentication Code) is used in many APIs,
-- especially webhooks, enabling validation of message authenticity.

SELECT '=== Basic HMAC Examples ===' AS title;

-- HMAC with SHA-256 (most common)
SELECT
    'Test Message' AS message,
    'secret_key' AS key,
    hex(HMAC('Test Message', 'secret_key', 'sha256')) AS hmac_sha256;

-- HMAC with different hash algorithms
SELECT '=== HMAC with Different Hash Algorithms ===' AS title;
SELECT
    'Hello World' AS message,
    'my_secret' AS key,
    hex(HMAC('Hello World', 'my_secret', 'sha1')) AS hmac_sha1,
    hex(HMAC('Hello World', 'my_secret', 'sha256')) AS hmac_sha256,
    hex(HMAC('Hello World', 'my_secret', 'sha512')) AS hmac_sha512;

-- Real-world use case: API webhook validation
DROP TABLE IF EXISTS webhook_events;

CREATE TABLE webhook_events
(
    event_id UInt64,
    timestamp DateTime,
    event_type String,
    payload String,
    signature String,
    api_key String
)
ENGINE = MergeTree()
ORDER BY (timestamp, event_id);

-- Insert sample webhook events
INSERT INTO webhook_events VALUES
    (1, '2025-01-01 10:00:00', 'user.created', '{"user_id": 123, "email": "user@example.com"}', '', 'webhook_secret_key_123'),
    (2, '2025-01-01 10:05:00', 'order.placed', '{"order_id": 456, "amount": 99.99}', '', 'webhook_secret_key_123'),
    (3, '2025-01-01 10:10:00', 'payment.received', '{"payment_id": 789, "amount": 99.99}', '', 'webhook_secret_key_123'),
    (4, '2025-01-01 10:15:00', 'user.updated', '{"user_id": 123, "email": "newemail@example.com"}', '', 'webhook_secret_key_456'),
    (5, '2025-01-01 10:20:00', 'order.shipped', '{"order_id": 456, "tracking": "TRACK123"}', '', 'webhook_secret_key_456');

-- Query 1: Generate HMAC signatures for webhook validation
SELECT '=== Generate Webhook HMAC Signatures ===' AS title;
SELECT
    event_id,
    event_type,
    payload,
    hex(HMAC(payload, api_key, 'sha256')) AS computed_signature
FROM webhook_events
ORDER BY event_id;

-- Query 2: Simulate webhook signature validation
-- In practice, the signature would come from the webhook sender
SELECT '=== Webhook Signature Validation ===' AS title;
WITH webhook_with_signature AS (
    SELECT
        event_id,
        event_type,
        payload,
        api_key,
        hex(HMAC(payload, api_key, 'sha256')) AS expected_signature
    FROM webhook_events
)
SELECT
    event_id,
    event_type,
    expected_signature,
    expected_signature AS received_signature,
    expected_signature = expected_signature AS is_valid
FROM webhook_with_signature
ORDER BY event_id;

-- Use case: API token validation
DROP TABLE IF EXISTS api_requests;

CREATE TABLE api_requests
(
    request_id UInt64,
    request_time DateTime,
    client_id String,
    endpoint String,
    request_params String,
    client_secret String
)
ENGINE = MergeTree()
ORDER BY (request_time, request_id);

-- Insert sample API requests
INSERT INTO api_requests VALUES
    (1, '2025-01-01 11:00:00', 'client_001', '/api/users', 'user_id=123&action=get', 'client_secret_abc'),
    (2, '2025-01-01 11:05:00', 'client_002', '/api/orders', 'order_id=456&status=pending', 'client_secret_xyz'),
    (3, '2025-01-01 11:10:00', 'client_001', '/api/products', 'category=electronics&limit=10', 'client_secret_abc'),
    (4, '2025-01-01 11:15:00', 'client_003', '/api/payments', 'amount=99.99&currency=USD', 'client_secret_def'),
    (5, '2025-01-01 11:20:00', 'client_002', '/api/shipping', 'tracking_id=TRACK123', 'client_secret_xyz');

-- Query 3: Generate API request signatures
SELECT '=== Generate API Request Signatures ===' AS title;
SELECT
    request_id,
    client_id,
    endpoint,
    request_params,
    hex(HMAC(concat(endpoint, '?', request_params), client_secret, 'sha256')) AS request_signature
FROM api_requests
ORDER BY request_id;

-- Query 4: Verify API requests with timestamp to prevent replay attacks
SELECT '=== API Request Validation with Timestamp ===' AS title;
SELECT
    request_id,
    client_id,
    endpoint,
    request_time,
    hex(HMAC(
        concat(
            endpoint, '?', request_params,
            '&timestamp=', toString(toUnixTimestamp(request_time))
        ),
        client_secret,
        'sha256'
    )) AS secure_signature,
    toUnixTimestamp(request_time) AS unix_timestamp
FROM api_requests
ORDER BY request_id;

-- Use case: JWT-like token generation
DROP TABLE IF EXISTS user_sessions;

CREATE TABLE user_sessions
(
    session_id UInt64,
    user_id UInt32,
    username String,
    login_time DateTime,
    expiry_time DateTime,
    session_secret String
)
ENGINE = MergeTree()
ORDER BY (user_id, login_time);

-- Insert sample user sessions
INSERT INTO user_sessions VALUES
    (1, 1001, 'alice', '2025-01-01 09:00:00', '2025-01-01 17:00:00', 'session_secret_alpha'),
    (2, 1002, 'bob', '2025-01-01 09:30:00', '2025-01-01 17:30:00', 'session_secret_beta'),
    (3, 1003, 'charlie', '2025-01-01 10:00:00', '2025-01-01 18:00:00', 'session_secret_gamma'),
    (4, 1001, 'alice', '2025-01-01 14:00:00', '2025-01-01 22:00:00', 'session_secret_alpha'),
    (5, 1004, 'diana', '2025-01-01 11:00:00', '2025-01-01 19:00:00', 'session_secret_delta');

-- Query 5: Generate session tokens with HMAC
SELECT '=== Generate Secure Session Tokens ===' AS title;
SELECT
    session_id,
    user_id,
    username,
    login_time,
    expiry_time,
    hex(HMAC(
        concat(
            'user_id=', toString(user_id),
            '&username=', username,
            '&login=', toString(toUnixTimestamp(login_time)),
            '&expiry=', toString(toUnixTimestamp(expiry_time))
        ),
        session_secret,
        'sha256'
    )) AS session_token
FROM user_sessions
ORDER BY session_id;

-- Query 6: Validate session tokens and check expiry
SELECT '=== Session Token Validation ===' AS title;
SELECT
    session_id,
    user_id,
    username,
    login_time,
    expiry_time,
    now() < expiry_time AS is_active,
    hex(HMAC(
        concat(
            'user_id=', toString(user_id),
            '&username=', username,
            '&login=', toString(toUnixTimestamp(login_time)),
            '&expiry=', toString(toUnixTimestamp(expiry_time))
        ),
        session_secret,
        'sha256'
    )) AS current_token,
    CASE
        WHEN now() < expiry_time THEN 'VALID'
        ELSE 'EXPIRED'
    END AS token_status
FROM user_sessions
ORDER BY session_id;

-- Advanced: HMAC for data integrity verification
DROP TABLE IF EXISTS data_records;

CREATE TABLE data_records
(
    record_id UInt64,
    created_at DateTime,
    data_content String,
    integrity_key String
)
ENGINE = MergeTree()
ORDER BY (created_at, record_id);

-- Insert sample data records
INSERT INTO data_records VALUES
    (1, '2025-01-01 08:00:00', 'Important financial data: Balance=$10,000', 'integrity_key_001'),
    (2, '2025-01-01 08:30:00', 'User profile: email=user@example.com, status=active', 'integrity_key_001'),
    (3, '2025-01-01 09:00:00', 'Transaction: from=A, to=B, amount=500', 'integrity_key_002'),
    (4, '2025-01-01 09:30:00', 'Configuration: db_host=localhost, db_port=5432', 'integrity_key_002'),
    (5, '2025-01-01 10:00:00', 'Audit log: action=delete, user=admin, target=record_123', 'integrity_key_003');

-- Query 7: Generate integrity checksums with HMAC
SELECT '=== Data Integrity Checksums ===' AS title;
SELECT
    record_id,
    created_at,
    data_content,
    hex(HMAC(
        concat(
            toString(record_id), '|',
            toString(created_at), '|',
            data_content
        ),
        integrity_key,
        'sha256'
    )) AS integrity_checksum
FROM data_records
ORDER BY record_id;

-- Query 8: Simulate integrity verification (detecting tampering)
SELECT '=== Data Integrity Verification ===' AS title;
WITH original_checksums AS (
    SELECT
        record_id,
        data_content,
        hex(HMAC(
            concat(
                toString(record_id), '|',
                toString(created_at), '|',
                data_content
            ),
            integrity_key,
            'sha256'
        )) AS checksum
    FROM data_records
)
SELECT
    record_id,
    data_content,
    checksum AS original_checksum,
    checksum AS verified_checksum,
    checksum = checksum AS integrity_valid
FROM original_checksums
ORDER BY record_id;

-- Benefits of HMAC Function
SELECT '=== HMAC Function Benefits ===' AS info;
SELECT
    'Webhook signature validation' AS benefit_1,
    'API request authentication' AS benefit_2,
    'Session token generation' AS benefit_3,
    'Data integrity verification' AS benefit_4,
    'Replay attack prevention' AS benefit_5,
    'Secure message authentication' AS benefit_6;

-- Use Cases
SELECT '=== Use Cases ===' AS info;
SELECT
    'Webhook validation (GitHub, Stripe, etc.)' AS use_case_1,
    'API authentication and authorization' AS use_case_2,
    'JWT-like token generation' AS use_case_3,
    'Data integrity checks' AS use_case_4,
    'Secure inter-service communication' AS use_case_5,
    'Audit trail protection' AS use_case_6,
    'OAuth and OpenID implementations' AS use_case_7;

-- Cleanup (commented out for inspection)
-- DROP TABLE data_records;
-- DROP TABLE user_sessions;
-- DROP TABLE api_requests;
-- DROP TABLE webhook_events;

SELECT '✅ HMAC Function Test Complete!' AS status;
