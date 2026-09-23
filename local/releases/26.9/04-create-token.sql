-- ClickHouse 26.9 — CREATE TOKEN and scope-limited authentication methods
--
--   CREATE TOKEN VALID FOR INTERVAL 30 DAY GRANTS (SELECT ON db.table)
--   ALTER USER u ADD IDENTIFIED WITH ... VALID UNTIL ... GRANTS (...)
--
-- 26.9 lets an authentication method carry its own grant list. A session that
-- logs in with that method gets the intersection of the user's privileges and
-- the listed ones, so one user can hand out credentials that are strictly
-- weaker than itself without a second user, a second role, or a proxy.
--
-- CREATE TOKEN is the self-service form: it generates the secret for you,
-- attaches it to the current user, and returns it with its deadline. The
-- ALTER USER form is the administrator's form, and does the same thing to
-- somebody else with a secret you choose.
--
-- This file uses the ALTER USER form throughout, for a reason worth knowing
-- before you try CREATE TOKEN yourself — see section 2.

SELECT '════════ 1. The statement, from the new system.statements table ════════' AS section;

SELECT name, syntax FROM system.statements WHERE name = 'CREATE TOKEN';

SELECT name, value AS default_ttl_seconds, 'without VALID UNTIL / VALID FOR' AS applies_when
FROM system.settings WHERE name = 'create_token_default_ttl_seconds';

-- 1800 — thirty minutes. Short on purpose: a token you forget about expires.

SELECT '════════ 2. Two things that stop CREATE TOKEN working ════════' AS section;

-- (a) The user has to live in a writable access storage. The default user of
--     the official Docker image is defined in users.xml, which is read-only,
--     so minting a token as default fails:
--
--       CREATE TOKEN VALID FOR INTERVAL 1 DAY GRANTS (SELECT ON demo.events);
--       Code: 495. Cannot update user `default` in users_xml because this
--                  storage is readonly.
--
--     SQL-defined users — CREATE USER, stored in local_directory or in
--     Keeper — are fine. That is why this lab creates one.
--
-- (b) A token is an additional authentication method, and no_password cannot
--     co-exist with any other method:
--
--       Code: 36. Authentication method 'no_password' cannot co-exist with
--                 other authentication methods.
--
--     So the user needs a real credential before it can have a token.

SELECT 'see the comments above' AS note;

SELECT '════════ 3. A user with more privileges than it should hand out ════════' AS section;

DROP DATABASE IF EXISTS demo SYNC;
CREATE DATABASE demo;

CREATE TABLE demo.events  (id UInt32, msg String) ENGINE = MergeTree ORDER BY id;
CREATE TABLE demo.secrets (id UInt32, v   String) ENGINE = MergeTree ORDER BY id;
INSERT INTO demo.events  VALUES (1, 'a'), (2, 'b');
INSERT INTO demo.secrets VALUES (1, 'top');

DROP USER IF EXISTS app;
CREATE USER app IDENTIFIED WITH sha256_password BY 'lab-password-not-a-secret';
GRANT SELECT ON demo.* TO app;
GRANT CREATE TOKEN ON *.* TO app;

-- CREATE TOKEN is its own privilege, and it needs the ON *.* form:
-- `GRANT CREATE TOKEN TO app` is a syntax error.

SHOW GRANTS FOR app;

SELECT '════════ 4. Issue a credential scoped below the user ════════' AS section;

-- app can read all of demo. This credential can read one table of it.
ALTER USER app ADD IDENTIFIED WITH sha256_password BY 'scoped-credential-not-a-secret'
    VALID UNTIL '2026-12-31 00:00:00'
    GRANTS (SELECT ON demo.events);

SHOW CREATE USER app;

-- The scope is stored on the method, visible in the user definition. What
-- system.users shows instead is three identical sha256_password entries with
-- no scope at all, so SHOW CREATE USER is the place to audit this:

SELECT name, auth_type FROM system.users WHERE name = 'app';

SELECT '════════ 5. Prove it over a real authenticated connection ════════' AS section;

-- remote() opens a genuine session as app, so these two rows are the two
-- credentials logging in, not a simulation.

SELECT * FROM (
    SELECT 'full password    ' AS credential,
           (SELECT count() FROM remote('localhost:9000', demo.events, 'app', 'lab-password-not-a-secret'))      AS can_read_events
    UNION ALL
    SELECT 'scoped credential',
           (SELECT count() FROM remote('localhost:9000', demo.events, 'app', 'scoped-credential-not-a-secret'))
) ORDER BY credential;

-- Both read demo.events: 2 rows each. The difference only shows on the table
-- the scope leaves out, and that attempt raises ACCESS_DENIED rather than
-- returning a row, so it lives in 04-create-token.sh instead of here — a
-- raised exception would stop this file at that line.

SELECT '════════ 6. A scoped session cannot mint more credentials ════════' AS section;

-- The obvious escalation is closed. Logging in with a scope-limited method and
-- calling CREATE TOKEN again gives:
--
--   Code: 497. Not enough privileges. The current session is authenticated
--              with a method which limits the access rights with the GRANTS
--              clause, and such sessions cannot add authentication methods to
--              an existing user.
--
-- 04-create-token.sh runs it.

SELECT 'see 04-create-token.sh' AS note;

SELECT '════════ 7. Expiry is checked at login, not at issue ════════' AS section;

-- A credential dated in the past is accepted by ALTER USER without complaint
-- and then refuses every login. Useful to know when a deploy script computes
-- the deadline and gets the timezone wrong: you get no error at issue time.

ALTER USER app ADD IDENTIFIED WITH sha256_password BY 'already-expired-not-a-secret'
    VALID UNTIL '2020-01-01 00:00:00'
    GRANTS (SELECT ON demo.events);

SELECT 'issued without error, valid until 2020-01-01' AS note;

SELECT '════════ 8. Revoking them ════════' AS section;

-- There is no DROP TOKEN. Each credential is an authentication method on the
-- user, and IDENTIFIED WITH (as opposed to ADD IDENTIFIED WITH) replaces the
-- whole list — so this revokes every token at once and leaves the password.

ALTER USER app IDENTIFIED WITH sha256_password BY 'lab-password-not-a-secret';

SHOW CREATE USER app;

-- Back to a single method. Any credential handed out above now fails with
-- AUTHENTICATION_FAILED. Revoking one token and keeping the others means
-- re-issuing the others, which is the main operational cost of this feature:
-- plan one token per consumer so you never have to.

-- Cleanup left commented so you can keep poking at the user.
-- DROP USER IF EXISTS app;
-- DROP DATABASE IF EXISTS demo SYNC;
