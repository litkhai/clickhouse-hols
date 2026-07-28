-- ClickHouse 26.6: SQL Compatibility and Ergonomics Test
-- New Features: SOME/ALL array quantifiers, column selection by LIKE/ILIKE pattern,
--               ESCAPE clause for LIKE, PostgreSQL-style date_part/EXTRACT,
--               compatibility aliases (min_by, max_by, REGEXP_SUBSTR),
--               and system.documentation behind the CLI `help` command.
-- Reference: https://clickhouse.com/blog/clickhouse-release-26-06

-- ============================================
-- 1. Test Data
-- ============================================

SELECT '========== 1. Test Data ==========';

DROP TABLE IF EXISTS orders;

CREATE TABLE orders
(
    order_id      UInt64,
    customer_name String,
    order_ref     String,
    ts_created    DateTime,
    ts_shipped    DateTime,
    amount        Decimal(10, 2),
    region        LowCardinality(String)
)
ENGINE = MergeTree
ORDER BY order_id;

INSERT INTO orders
SELECT
    number + 1,
    ['alice', 'bob', 'carol', 'dave'][number % 4 + 1],
    concat('ORDER_', leftPad(toString(number + 1), 5, '0'), '-x'),
    toDateTime('2026-06-25 09:00:00') + number * 3600,
    toDateTime('2026-06-25 09:00:00') + number * 3600 + 86400,
    (number % 50 + 1) * 19.99,
    ['us-east', 'eu-west', 'ap-south'][number % 3 + 1]
FROM numbers(120);

SELECT count() AS rows FROM orders;

-- ============================================
-- 2. SOME / ALL Quantifiers Over Arrays
-- ============================================

SELECT '========== 2. SOME / ALL With Arrays ==========';

-- ANSI SQL quantified comparisons. Previously this needed arrayAll / arrayExists.
SELECT
    500 > ALL([100, 200, 300])  AS above_every_value,
    500 > SOME([100, 200, 900]) AS above_at_least_one,
    500 = SOME([100, 500, 900]) AS matches_one,
    500 < ALL([600, 700])       AS below_every_value;

-- The old equivalent, for comparison.
SELECT
    arrayAll(x -> 500 > x, [100, 200, 300])    AS old_all,
    arrayExists(x -> 500 > x, [100, 200, 900]) AS old_some;

-- ============================================
-- 3. SOME / ALL Over Subqueries
-- ============================================

SELECT '========== 3. SOME / ALL With Subqueries ==========';

-- Orders larger than every order from ap-south.
SELECT count() AS beats_every_ap_south_order
FROM orders
WHERE amount > ALL (SELECT amount FROM orders WHERE region = 'ap-south');

-- Orders whose amount matches at least one eu-west order.
SELECT count() AS matches_some_eu_west_order
FROM orders
WHERE amount = SOME (SELECT amount FROM orders WHERE region = 'eu-west');

-- ============================================
-- 4. Column Selection by Pattern
-- ============================================

SELECT '========== 4. SELECT * LIKE / * ILIKE ==========';

-- Pick columns by name pattern instead of typing them out.
SELECT * LIKE 'ts_%' FROM orders ORDER BY ts_created LIMIT 3;

-- ILIKE is the case-insensitive form.
SELECT * ILIKE 'ORDER%' FROM orders ORDER BY order_id LIMIT 3;

-- Patterns compose with EXCEPT to subtract one column back out.
SELECT * LIKE 'ts_%' EXCEPT (ts_shipped) FROM orders ORDER BY ts_created LIMIT 3;

-- Handy for wide tables: aggregate every matching column at once.
SELECT * LIKE 'ts_%' APPLY max FROM orders;

-- ============================================
-- 5. ESCAPE Clause for LIKE
-- ============================================

SELECT '========== 5. LIKE ... ESCAPE ==========';

-- '_' and '%' are wildcards. ESCAPE nominates a character that turns off that meaning,
-- so a literal underscore can be matched without backslash-escaping the pattern.
SELECT
    'ORDER_00001-x' LIKE 'ORDER!_%' ESCAPE '!' AS literal_underscore_matches,
    'ORDERX00001-x' LIKE 'ORDER!_%' ESCAPE '!' AS other_char_rejected;

-- Real filter: order_ref values whose prefix contains a literal underscore.
SELECT count() AS refs_with_literal_underscore
FROM orders
WHERE order_ref LIKE 'ORDER!_%' ESCAPE '!';

-- ============================================
-- 6. PostgreSQL-Style date_part and EXTRACT
-- ============================================

SELECT '========== 6. date_part / EXTRACT ==========';

SELECT
    date_part('year',   ts_created) AS y,
    date_part('month',  ts_created) AS m,
    date_part('day',    ts_created) AS d,
    date_part('hour',   ts_created) AS h,
    date_part('minute', ts_created) AS mi
FROM orders
ORDER BY order_id
LIMIT 3;

-- EXTRACT(unit FROM value) is the ANSI spelling of the same thing.
SELECT
    EXTRACT(YEAR FROM ts_created)    AS y,
    EXTRACT(MONTH FROM ts_created)   AS m,
    EXTRACT(QUARTER FROM ts_created) AS q
FROM orders
ORDER BY order_id
LIMIT 3;

-- Group by an extracted part, the way a Postgres report would.
SELECT
    date_part('day', ts_created) AS day_of_month,
    count()                      AS orders,
    round(sum(amount), 2)        AS revenue
FROM orders
GROUP BY day_of_month
ORDER BY day_of_month;

-- ============================================
-- 7. Compatibility Aliases
-- ============================================

SELECT '========== 7. min_by / max_by / REGEXP_SUBSTR ==========';

-- min_by / max_by: the value of one column at the row where another is extreme.
SELECT
    min_by(customer_name, amount) AS cheapest_order_customer,
    max_by(customer_name, amount) AS largest_order_customer,
    min(amount)                   AS min_amount,
    max(amount)                   AS max_amount
FROM orders;

-- argMin / argMax are the native spellings of the same aggregates.
SELECT
    argMin(customer_name, amount) AS same_as_min_by,
    argMax(customer_name, amount) AS same_as_max_by
FROM orders;

-- REGEXP_SUBSTR pulls the first match out of a string.
SELECT
    order_ref,
    REGEXP_SUBSTR(order_ref, '[0-9]+') AS digits
FROM orders
ORDER BY order_id
LIMIT 3;

-- ============================================
-- 8. Per-Region Report Combining the New Syntax
-- ============================================

SELECT '========== 8. Combined Report ==========';

SELECT
    region,
    count()                                                  AS orders,
    round(sum(amount), 2)                                    AS revenue,
    max_by(customer_name, amount)                            AS top_customer,
    countIf(order_ref LIKE 'ORDER!_%' ESCAPE '!')            AS refs_ok,
    uniqExact(date_part('day', ts_created))                  AS active_days
FROM orders
GROUP BY region
ORDER BY revenue DESC;

-- ============================================
-- 9. system.documentation — the CLI `help` Backend
-- ============================================

SELECT '========== 9. system.documentation ==========';

-- 26.6 embeds the reference documentation in the server. The CLI `help <topic>` command
-- reads it, and so can SQL.
SELECT type, count() AS documented_entities
FROM system.documentation
GROUP BY type
ORDER BY documented_entities DESC
LIMIT 8;

-- Look up one function without leaving the session.
SELECT substring(description, 1, 240) AS max_by_docs
FROM system.documentation
WHERE name = 'max_by';

-- Find every entity whose docs mention a term.
SELECT name, type
FROM system.documentation
WHERE description ILIKE '%quantified comparison%' OR name ILIKE '%regexp_substr%'
ORDER BY name
LIMIT 10;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS orders;

SELECT '========== Test Complete ==========';
SELECT 'Quantifiers, column patterns, ESCAPE and date_part close long-standing porting gaps.' AS summary;
