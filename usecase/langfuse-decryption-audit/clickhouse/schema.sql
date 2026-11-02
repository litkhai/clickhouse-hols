-- The decryption audit store. Run as the admin user by 01-up.sh; the two users are created there
-- with generated passwords.
--   audit_writer  the decryption service: INSERT on the table, nothing else
--   auditor       the reviewer: SELECT on the table and read access to OpenBao's audit file

CREATE DATABASE IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.decrypt_events
(
    event_time    DateTime64(3) DEFAULT now64(3),
    request_id    UUID,
    user          String,                   -- verified by OpenBao (empty when the login was refused)
    claimed_user  String,                   -- what the token claimed, unverified; for refusals
    client_ip     String,
    trace_id      String,
    field         LowCardinality(String),
    key_name      LowCardinality(String),
    reason        String,
    outcome       LowCardinality(String),   -- attempt | success | denied | reason_missing | unauthenticated | not_found | bad_request
    detail        String
)
ENGINE = MergeTree
ORDER BY (event_time, request_id)
TTL toDateTime(event_time) + INTERVAL 5 YEAR;   -- example retention; set it to the regulation that applies
