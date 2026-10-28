-- ClickHouse 26.10 — function composition f | g, placeholders _ and _1.._N,
--                    and three pieces of other dialects in plain ClickHouse SQL
--
--   arrayMap(plus(_, 1) | multiply(_, 2), arr)   -- x -> (x + 1) * 2
--   arrayMap(_1 * 2 + 1, arr)                    -- x -> x * 2 + 1
--
-- A placeholder turns an expression into a lambda; | chains two functions left
-- to right. Both are resolved at analysis time into an ordinary lambda, so they
-- cost nothing at run time and work anywhere a lambda does.
--
-- The rules are short and one of them bites:
--
--   * every bare _ is a NEW argument, left to right. _ * _ takes two arguments,
--     not one. Use _1 * _1 to square.
--   * | means composition only where a function is expected. 5 | 3 is not
--     bitwise OR; it is an error that tells you to use bitOr.
--   * a function with a variable number of arguments, such as toString, cannot
--     be composed by name. Write toString(_) instead.
--
-- The errors are in 02-function-composition.sh.

SELECT '════════ 1. Placeholders ════════' AS section;

SELECT
    arrayMap(_ + 1, [1, 2, 3])          AS plus_one,
    arrayFilter(_ > 1, [1, 2, 3])       AS gt_one,
    arraySort(-_, [3, 1, 2])            AS descending,
    arrayMap(_1 * 2 + 1, [1, 2, 3])     AS numbered,
    arrayMap(_1 + _2, [1, 2], [10, 20]) AS two_arrays;

-- The trap. Each _ takes the next argument, so _ * _ is (a, b) -> a * b, and
-- arrayMap over one array rejects it (see the .sh). Number them to reuse one.
SELECT '-- 1b. squares need _1 * _1' AS note;
SELECT arrayMap(_1 * _1, [1, 2, 3]) AS squares;

SELECT '-- 1c. arrayFold, where the two-argument form is what you want' AS note;
SELECT
    arrayFold((acc, x) -> acc + x, [1, 2, 3], 0::UInt64) AS lambda_form,
    arrayFold(_1 + _2, [1, 2, 3], 0::UInt64)             AS placeholder_form;

SELECT '════════ 2. Composition ════════' AS section;

SELECT
    arrayMap(plus(_, 1) | multiply(_, 2), [1, 2, 3])               AS plus_then_times,
    arrayMap(multiply(_, 2) | plus(_, 1), [1, 2, 3])               AS times_then_plus,
    arrayMap(lower | reverse, ['AbC', 'XyZ'])                      AS by_name,
    arrayMap(plus(_, 1) | multiply(_, 2) | toString(_), [1, 2])    AS three_steps;

-- Order is left to right: f | g is g(f(x)), the way a shell pipe reads.

SELECT '════════ 3. What the analyzer turns it into ════════' AS section;

-- EXPLAIN SYNTAX keeps the composition as __compose(...). The query tree is
-- where it becomes a plain lambda: multiply(plus(__composed_arg_1, 1), 2).
EXPLAIN SYNTAX SELECT arrayMap(plus(_, 1) | multiply(_, 2), [1, 2, 3]);

SELECT '-- 3b. the projection name is the lambda the analyzer built' AS note;
SELECT explain FROM (EXPLAIN QUERY TREE SELECT arrayMap(plus(_, 1) | multiply(_, 2), [1, 2, 3]))
WHERE explain LIKE '%lambda(%';

SELECT '════════ 4. A column named _ still wins ════════' AS section;

-- Placeholders do not shadow real identifiers. A column called _ resolves to the
-- column, which keeps old queries working and makes the placeholder unusable in
-- that scope (the .sh shows arrayMap failing on it).
SELECT _ FROM (SELECT 1 AS _);
SELECT arrayMap(_ -> _ + 1, [1, 2]) AS lambda_parameter_named_underscore;

SELECT '════════ 5. Trino spellings and SIMILAR TO, in the default dialect ════════' AS section;

-- 26.9 had these only behind dialect = 'trino'. 26.10 accepts them in ordinary
-- ClickHouse SQL. On 26.9 every line of this section is an error.
SELECT
    TRY_CAST('abc' AS Int32)         AS try_cast_bad,
    TRY_CAST('12' AS Int32)          AS try_cast_good,
    ARRAY[1, 2, 3]                   AS array_ctor,
    starts_with('hello', 'he')       AS starts_with,
    slice([1, 2, 3, 4], 2, 2)        AS slice,
    regexp_like('2026-10-22', '^\\d{4}-') AS regexp_like;

-- SIMILAR TO is the SQL-standard pattern: LIKE's % and _ plus regex-style
-- alternation and grouping, matched against the WHOLE string.
SELECT
    'abc' SIMILAR TO 'a%'       AS prefix,
    'abc' SIMILAR TO 'a_c'      AS one_char,
    'abc' SIMILAR TO '(a|b)c'   AS whole_string_only,
    'bc'  SIMILAR TO '(a|b)c'   AS alternation,
    'abc' NOT SIMILAR TO 'b%'   AS negated;
