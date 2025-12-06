-- ClickHouse 25.6 Feature: Bech32 Encoding Functions
-- Purpose: Test the new bech32Encode and bech32Decode functions
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-06

-- Bech32 is a checksummed base32 encoding format used in cryptocurrency addresses
-- It provides better error detection than traditional Base58 encoding

-- Drop tables if exist
DROP TABLE IF EXISTS crypto_addresses;
DROP TABLE IF EXISTS identifier_mapping;

-- Query 1: Basic Bech32 encoding
SELECT '=== Basic Bech32 Encoding ===' AS title;
SELECT
    'hello' AS original_data,
    bech32Encode('test', 'hello') AS encoded,
    bech32Decode(bech32Encode('test', 'hello')) AS decoded;

-- Query 2: Encode various data types
SELECT '=== Encoding Various Data Types ===' AS title;
SELECT
    'User123' AS user_id,
    bech32Encode('usr', 'User123') AS encoded_user,
    'Order456' AS order_id,
    bech32Encode('ord', 'Order456') AS encoded_order,
    'Product789' AS product_id,
    bech32Encode('prd', 'Product789') AS encoded_product;

-- Query 3: Encode and decode workflow
SELECT '=== Encode and Decode Workflow ===' AS title;
WITH test_data AS (
    SELECT
        'sensitive_data_12345' AS original,
        'data' AS hrp
)
SELECT
    original,
    hrp,
    bech32Encode(hrp, original) AS encoded,
    bech32Decode(bech32Encode(hrp, original)) AS decoded,
    original = bech32Decode(bech32Encode(hrp, original)) AS is_valid
FROM test_data;

-- Create a table for cryptocurrency addresses
CREATE TABLE crypto_addresses
(
    address_id UInt64,
    user_name String,
    raw_address String,
    network String,
    encoded_address String,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY address_id;

-- Insert cryptocurrency address data
-- Using bech32Encode to create human-readable addresses
INSERT INTO crypto_addresses
SELECT
    number AS address_id,
    concat('user_', toString(number)) AS user_name,
    hex(rand64()) AS raw_address,
    CASE
        WHEN number % 3 = 0 THEN 'bitcoin'
        WHEN number % 3 = 1 THEN 'cosmos'
        ELSE 'ethereum'
    END AS network,
    CASE
        WHEN number % 3 = 0 THEN bech32Encode('bc', hex(rand64()))
        WHEN number % 3 = 1 THEN bech32Encode('cosmos', hex(rand64()))
        ELSE bech32Encode('eth', hex(rand64()))
    END AS encoded_address,
    now() AS created_at
FROM numbers(10);

-- Query 4: View cryptocurrency addresses
SELECT '=== Cryptocurrency Addresses ===' AS title;
SELECT
    address_id,
    user_name,
    network,
    substring(raw_address, 1, 16) AS raw_address_preview,
    encoded_address
FROM crypto_addresses
ORDER BY address_id
LIMIT 5;

-- Query 5: Decode addresses back to raw format
SELECT '=== Decode Addresses ===' AS title;
SELECT
    address_id,
    user_name,
    network,
    encoded_address,
    substring(bech32Decode(encoded_address), 1, 16) AS decoded_preview
FROM crypto_addresses
ORDER BY address_id
LIMIT 5;

-- Query 6: Group by network and count
SELECT '=== Addresses by Network ===' AS title;
SELECT
    network,
    count() AS address_count,
    any(encoded_address) AS sample_address
FROM crypto_addresses
GROUP BY network
ORDER BY network;

-- Create identifier mapping table for obfuscation use case
CREATE TABLE identifier_mapping
(
    internal_id String,
    public_id String,
    entity_type String,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY internal_id;

-- Insert data with public identifiers using Bech32
INSERT INTO identifier_mapping VALUES
    ('USER-001', bech32Encode('usr', 'USER-001'), 'user', now()),
    ('USER-002', bech32Encode('usr', 'USER-002'), 'user', now()),
    ('ORDER-1001', bech32Encode('ord', 'ORDER-1001'), 'order', now()),
    ('ORDER-1002', bech32Encode('ord', 'ORDER-1002'), 'order', now()),
    ('PRODUCT-5001', bech32Encode('prd', 'PRODUCT-5001'), 'product', now()),
    ('PRODUCT-5002', bech32Encode('prd', 'PRODUCT-5002'), 'product', now()),
    ('INVOICE-2001', bech32Encode('inv', 'INVOICE-2001'), 'invoice', now()),
    ('INVOICE-2002', bech32Encode('inv', 'INVOICE-2002'), 'invoice', now());

-- Query 7: View identifier mapping
SELECT '=== Internal to Public ID Mapping ===' AS title;
SELECT
    entity_type,
    internal_id,
    public_id
FROM identifier_mapping
ORDER BY entity_type, internal_id;

-- Query 8: Decode public IDs back to internal
SELECT '=== Decode Public IDs ===' AS title;
SELECT
    entity_type,
    public_id,
    bech32Decode(public_id) AS decoded_internal_id,
    internal_id,
    bech32Decode(public_id) = internal_id AS matches
FROM identifier_mapping
ORDER BY entity_type, internal_id;

-- Query 9: Use case - API key generation
SELECT '=== API Key Generation Example ===' AS title;
WITH api_keys AS (
    SELECT
        number AS key_id,
        concat('app_', toString(number)) AS app_name,
        hex(rand64()) AS secret
    FROM numbers(5)
)
SELECT
    key_id,
    app_name,
    bech32Encode('apikey', secret) AS api_key,
    substring(secret, 1, 16) AS secret_preview
FROM api_keys;

-- Query 10: Validate Bech32 checksums (round-trip test)
SELECT '=== Checksum Validation ===' AS title;
WITH test_cases AS (
    SELECT
        number AS test_id,
        concat('test_data_', toString(number)) AS test_data
    FROM numbers(5)
)
SELECT
    test_id,
    test_data,
    bech32Encode('test', test_data) AS encoded,
    bech32Decode(bech32Encode('test', test_data)) AS decoded,
    test_data = bech32Decode(bech32Encode('test', test_data)) AS is_valid
FROM test_cases;

-- Query 11: Different HRP (Human Readable Prefix) examples
SELECT '=== Different HRP Examples ===' AS title;
SELECT
    'Bitcoin Mainnet' AS network,
    'bc' AS hrp,
    bech32Encode('bc', 'sample_address_data') AS address
UNION ALL
SELECT
    'Bitcoin Testnet' AS network,
    'tb' AS hrp,
    bech32Encode('tb', 'sample_address_data') AS address
UNION ALL
SELECT
    'Cosmos Network' AS network,
    'cosmos' AS hrp,
    bech32Encode('cosmos', 'sample_address_data') AS address
UNION ALL
SELECT
    'Lightning Network' AS network,
    'lnbc' AS hrp,
    bech32Encode('lnbc', 'sample_address_data') AS address;

-- Real-world scenario: URL shortener with obfuscation
DROP TABLE IF EXISTS url_mappings;

CREATE TABLE url_mappings
(
    id UInt64,
    original_url String,
    short_code String,
    clicks UInt64 DEFAULT 0,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY id;

-- Insert URL mappings with Bech32-encoded short codes
INSERT INTO url_mappings
SELECT
    number AS id,
    concat('https://example.com/page/', toString(number)) AS original_url,
    bech32Encode('url', toString(number)) AS short_code,
    0 AS clicks,
    now() AS created_at
FROM numbers(5);

-- Query 12: View URL mappings
SELECT '=== URL Shortener Example ===' AS title;
SELECT
    id,
    original_url,
    short_code,
    concat('https://short.link/', short_code) AS shortened_url
FROM url_mappings
ORDER BY id;

-- Query 13: Decode short code to retrieve original ID
SELECT '=== Decode Short Code ===' AS title;
SELECT
    short_code,
    bech32Decode(short_code) AS decoded_id,
    original_url
FROM url_mappings
ORDER BY id
LIMIT 3;

-- Benefits of Bech32 encoding
SELECT '=== Bech32 Encoding Benefits ===' AS info;
SELECT
    'Better error detection with checksum validation' AS benefit_1,
    'Human-readable prefix for easy identification' AS benefit_2,
    'Case-insensitive encoding reduces input errors' AS benefit_3,
    'No ambiguous characters (0, O, I, l are excluded)' AS benefit_4,
    'Widely used in cryptocurrency for address encoding' AS benefit_5;

-- Use cases
SELECT '=== Common Use Cases ===' AS info;
SELECT
    'Cryptocurrency address encoding' AS use_case_1,
    'Public API key generation' AS use_case_2,
    'URL shortening with obfuscation' AS use_case_3,
    'Invoice and payment identifiers' AS use_case_4,
    'External ID mapping for security' AS use_case_5,
    'QR code data encoding' AS use_case_6;

-- Cleanup (commented out for inspection)
-- DROP TABLE crypto_addresses;
-- DROP TABLE identifier_mapping;
-- DROP TABLE url_mappings;

SELECT '✅ Bech32 Encoding Functions Test Complete!' AS status;
