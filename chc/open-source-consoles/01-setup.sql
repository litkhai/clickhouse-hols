-- Test schema and two tool accounts for the console scenarios. Run as the service's default user:
--   clickhouse client ... --param_admin_pw='…' --param_ro_pw='…' --multiquery < 01-setup.sql
-- Cloud's password policy applies to both passwords (upper case, a special character, length).
CREATE DATABASE IF NOT EXISTS console_lab;

-- No ENGINE clause: on Cloud this is SharedMergeTree.
CREATE TABLE IF NOT EXISTS console_lab.events
(
    ts      DateTime,
    user_id UInt32,
    event   LowCardinality(String),
    amount  Decimal(18, 2),
    props   Map(String, String)
)
ORDER BY (event, ts)
PARTITION BY toYYYYMM(ts);

-- AggregatingMergeTree becomes SharedAggregatingMergeTree.
CREATE TABLE IF NOT EXISTS console_lab.daily
(
    d     Date,
    event LowCardinality(String),
    n     AggregateFunction(count),
    s     AggregateFunction(sum, Decimal(18, 2))
)
ENGINE = AggregatingMergeTree
ORDER BY (d, event);

CREATE MATERIALIZED VIEW IF NOT EXISTS console_lab.daily_mv TO console_lab.daily AS
SELECT toDate(ts) AS d, event, countState() AS n, sumState(amount) AS s
FROM console_lab.events GROUP BY d, event;

CREATE VIEW IF NOT EXISTS console_lab.v_buy AS SELECT * FROM console_lab.events WHERE event = 'buy';

INSERT INTO console_lab.events
SELECT toDateTime('2026-11-08 00:00:00') - toIntervalSecond(number * 37),
       number % 10000, ['view', 'click', 'buy'][number % 3 + 1], (number % 1000) / 10, map('k', toString(number % 7))
FROM numbers(2100000);

-- default has no global GRANT OPTION on Cloud, so "GRANT ALL" fails; CURRENT GRANTS hands over what default has.
CREATE USER IF NOT EXISTS console_admin IDENTIFIED WITH sha256_password BY {admin_pw:String};
GRANT CURRENT GRANTS ON *.* TO console_admin;
CREATE USER IF NOT EXISTS console_ro IDENTIFIED WITH sha256_password BY {ro_pw:String};
GRANT SELECT ON console_lab.* TO console_ro;
GRANT CURRENT GRANTS(SELECT ON system.*) TO console_ro;
-- Tools that read every replica with clusterAllReplicas() also need this:
GRANT CURRENT GRANTS(READ ON REMOTE) TO console_ro;

SELECT name, engine FROM system.tables WHERE database = 'console_lab' ORDER BY name;
SELECT count() AS events FROM console_lab.events;
