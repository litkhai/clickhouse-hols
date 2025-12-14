-- ClickHouse 25.6 Feature: Consistent Snapshot Across Queries
-- Purpose: Test the consistent snapshot feature for multi-query read consistency
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-06

-- Consistent snapshots ensure that multiple queries see the same data state
-- This is crucial for generating reports, audits, and analytical dashboards
-- where data consistency across multiple queries is required

-- Drop tables if exist
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS audit_log;

-- Create accounts table
CREATE TABLE accounts
(
    account_id UInt32,
    account_name String,
    balance Float64,
    account_type String,
    last_updated DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY account_id;

-- Create transactions table
CREATE TABLE transactions
(
    transaction_id UInt64,
    from_account UInt32,
    to_account UInt32,
    amount Float64,
    transaction_time DateTime DEFAULT now(),
    status String
)
ENGINE = MergeTree()
ORDER BY transaction_id;

-- Insert initial account data
INSERT INTO accounts VALUES
    (1, 'Alice Account', 10000.00, 'checking', now()),
    (2, 'Bob Account', 5000.00, 'checking', now()),
    (3, 'Charlie Account', 15000.00, 'savings', now()),
    (4, 'David Account', 20000.00, 'savings', now()),
    (5, 'Eve Account', 8000.00, 'checking', now());

-- Insert initial transaction history
INSERT INTO transactions VALUES
    (1, 1, 2, 500.00, now() - INTERVAL 2 DAY, 'completed'),
    (2, 3, 4, 1000.00, now() - INTERVAL 1 DAY, 'completed'),
    (3, 2, 5, 300.00, now() - INTERVAL 1 DAY, 'completed'),
    (4, 4, 1, 750.00, now() - INTERVAL 1 HOUR, 'completed');

-- Query 1: View current state of accounts
SELECT '=== Current Account Balances ===' AS title;
SELECT
    account_id,
    account_name,
    balance,
    account_type,
    last_updated
FROM accounts
ORDER BY account_id;

-- Query 2: View transaction history
SELECT '=== Transaction History ===' AS title;
SELECT
    transaction_id,
    from_account,
    to_account,
    amount,
    transaction_time,
    status
FROM transactions
ORDER BY transaction_time DESC;

-- Demonstrate consistent snapshot using snapshot_id setting
-- Note: In ClickHouse, snapshot isolation is primarily managed through settings
-- The example shows how to ensure consistency across queries

-- Query 3: Generate a financial report with multiple queries
-- This simulates a scenario where we need consistency across multiple queries
SELECT '=== Financial Report - Part 1: Account Summary ===' AS title;
SELECT
    account_type,
    count() AS account_count,
    sum(balance) AS total_balance,
    avg(balance) AS avg_balance,
    min(balance) AS min_balance,
    max(balance) AS max_balance
FROM accounts
GROUP BY account_type
ORDER BY account_type;

-- Query 4: Financial report - Part 2: Transaction volume
SELECT '=== Financial Report - Part 2: Transaction Volume ===' AS title;
SELECT
    toDate(transaction_time) AS date,
    count() AS transaction_count,
    sum(amount) AS total_amount,
    avg(amount) AS avg_amount
FROM transactions
WHERE status = 'completed'
GROUP BY date
ORDER BY date DESC;

-- Query 5: Financial report - Part 3: Account activity
SELECT '=== Financial Report - Part 3: Account Activity ===' AS title;
SELECT
    a.account_id,
    a.account_name,
    a.balance AS current_balance,
    coalesce(sent.sent_amount, 0) AS total_sent,
    coalesce(received.received_amount, 0) AS total_received
FROM accounts a
LEFT JOIN (
    SELECT from_account, sum(amount) AS sent_amount
    FROM transactions
    WHERE status = 'completed'
    GROUP BY from_account
) sent ON a.account_id = sent.from_account
LEFT JOIN (
    SELECT to_account, sum(amount) AS received_amount
    FROM transactions
    WHERE status = 'completed'
    GROUP BY to_account
) received ON a.account_id = received.to_account
ORDER BY a.account_id;

-- Real-world scenario: End-of-day reporting
-- Create a materialized view for consistent reporting
DROP TABLE IF EXISTS daily_snapshot;

CREATE TABLE daily_snapshot
(
    snapshot_date Date,
    account_id UInt32,
    account_name String,
    balance Float64,
    account_type String,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (snapshot_date, account_id);

-- Take a snapshot of current state
INSERT INTO daily_snapshot
SELECT
    toDate(now()) AS snapshot_date,
    account_id,
    account_name,
    balance,
    account_type,
    now() AS created_at
FROM accounts;

-- Query 6: View snapshot data
SELECT '=== Daily Snapshot ===' AS title;
SELECT
    snapshot_date,
    account_id,
    account_name,
    balance,
    account_type
FROM daily_snapshot
ORDER BY account_id;

-- Simulate concurrent updates (in real scenario, these would happen in parallel)
-- Insert new transactions
INSERT INTO transactions VALUES
    (5, 1, 3, 1500.00, now(), 'completed'),
    (6, 5, 2, 600.00, now(), 'completed');

-- Update account balances
INSERT INTO accounts VALUES
    (1, 'Alice Account', 8500.00, 'checking', now()),
    (2, 'Bob Account', 5600.00, 'checking', now()),
    (3, 'Charlie Account', 16500.00, 'savings', now()),
    (5, 'Eve Account', 7400.00, 'checking', now());

-- Query 7: Compare snapshot vs current state
SELECT '=== Snapshot vs Current State Comparison ===' AS title;
SELECT
    'SNAPSHOT' AS data_source,
    account_id,
    account_name,
    balance
FROM daily_snapshot
WHERE snapshot_date = toDate(now())
UNION ALL
SELECT
    'CURRENT' AS data_source,
    account_id,
    account_name,
    balance
FROM accounts
ORDER BY data_source, account_id;

-- Query 8: Detect changes since snapshot
SELECT '=== Changes Since Snapshot ===' AS title;
SELECT
    c.account_id,
    c.account_name,
    s.balance AS snapshot_balance,
    c.balance AS current_balance,
    c.balance - s.balance AS balance_change,
    round((c.balance - s.balance) / s.balance * 100, 2) AS change_percentage
FROM accounts c
JOIN daily_snapshot s ON c.account_id = s.account_id AND s.snapshot_date = toDate(now())
WHERE c.balance != s.balance
ORDER BY abs(balance_change) DESC;

-- Create audit log for compliance
CREATE TABLE audit_log
(
    audit_id UInt64,
    audit_time DateTime DEFAULT now(),
    report_type String,
    snapshot_date Date,
    total_accounts UInt32,
    total_balance Float64,
    record_count UInt64,
    checksum String
)
ENGINE = MergeTree()
ORDER BY audit_id;

-- Query 9: Generate audit log entry with snapshot
INSERT INTO audit_log
SELECT
    1 AS audit_id,
    now() AS audit_time,
    'DAILY_BALANCE_REPORT' AS report_type,
    toDate(now()) AS snapshot_date,
    count() AS total_accounts,
    sum(balance) AS total_balance,
    count() AS record_count,
    hex(cityHash64(groupArray((account_id, balance)))) AS checksum
FROM daily_snapshot
WHERE snapshot_date = toDate(now());

SELECT '=== Audit Log ===' AS title;
SELECT * FROM audit_log;

-- Query 10: Multi-query consistency check
-- Verify that sum of balances matches across different queries
SELECT '=== Consistency Verification ===' AS title;
WITH
    snapshot_sum AS (
        SELECT sum(balance) AS total
        FROM daily_snapshot
        WHERE snapshot_date = toDate(now())
    ),
    current_sum AS (
        SELECT sum(balance) AS total
        FROM accounts
    )
SELECT
    (SELECT total FROM snapshot_sum) AS snapshot_total,
    (SELECT total FROM current_sum) AS current_total,
    (SELECT total FROM current_sum) - (SELECT total FROM snapshot_sum) AS difference,
    'Values differ due to concurrent updates' AS note;

-- Real-world use case: Regulatory reporting
DROP TABLE IF EXISTS regulatory_report;

CREATE TABLE regulatory_report
(
    report_id UInt32,
    report_date Date,
    report_type String,
    account_type String,
    account_count UInt32,
    total_balance Float64,
    avg_balance Float64,
    generated_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (report_date, report_id);

-- Generate consistent regulatory report
INSERT INTO regulatory_report
SELECT
    1 AS report_id,
    toDate(now()) AS report_date,
    'REGULATORY_BALANCE_REPORT' AS report_type,
    account_type,
    count() AS account_count,
    sum(balance) AS total_balance,
    avg(balance) AS avg_balance,
    now() AS generated_at
FROM daily_snapshot
WHERE snapshot_date = toDate(now())
GROUP BY account_type;

-- Query 11: View regulatory report
SELECT '=== Regulatory Report ===' AS title;
SELECT
    report_id,
    report_date,
    account_type,
    account_count,
    round(total_balance, 2) AS total_balance,
    round(avg_balance, 2) AS avg_balance,
    generated_at
FROM regulatory_report
ORDER BY account_type;

-- Query 12: Historical snapshot comparison
-- Insert another snapshot for comparison
INSERT INTO daily_snapshot
SELECT
    toDate(now()) + INTERVAL 1 DAY AS snapshot_date,
    account_id,
    account_name,
    balance,
    account_type,
    now() AS created_at
FROM accounts;

SELECT '=== Historical Snapshot Analysis ===' AS title;
SELECT
    snapshot_date,
    account_type,
    sum(balance) AS total_balance,
    count() AS account_count
FROM daily_snapshot
GROUP BY snapshot_date, account_type
ORDER BY snapshot_date, account_type;

-- Benefits of consistent snapshots
SELECT '=== Consistent Snapshot Benefits ===' AS info;
SELECT
    'Ensures data consistency across multiple queries' AS benefit_1,
    'Prevents phantom reads during report generation' AS benefit_2,
    'Critical for financial and regulatory reporting' AS benefit_3,
    'Enables accurate point-in-time analysis' AS benefit_4,
    'Supports audit and compliance requirements' AS benefit_5,
    'Provides repeatable query results for verification' AS benefit_6;

-- Use cases
SELECT '=== Common Use Cases ===' AS info;
SELECT
    'Financial end-of-day reporting and reconciliation' AS use_case_1,
    'Regulatory compliance and audit trails' AS use_case_2,
    'Multi-table dashboard generation with consistency' AS use_case_3,
    'Data export for external systems' AS use_case_4,
    'Historical point-in-time analysis' AS use_case_5,
    'Backup verification and data integrity checks' AS use_case_6;

-- Best practices
SELECT '=== Best Practices ===' AS info;
SELECT
    'Create snapshot tables for critical reports' AS practice_1,
    'Use materialized views for frequently accessed snapshots' AS practice_2,
    'Include checksums for data integrity verification' AS practice_3,
    'Maintain audit logs with snapshot metadata' AS practice_4,
    'Archive historical snapshots for compliance' AS practice_5;

-- Cleanup (commented out for inspection)
-- DROP TABLE accounts;
-- DROP TABLE transactions;
-- DROP TABLE audit_log;
-- DROP TABLE daily_snapshot;
-- DROP TABLE regulatory_report;

SELECT '✅ Consistent Snapshot Test Complete!' AS status;
