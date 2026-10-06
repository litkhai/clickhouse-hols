# Consolidating Survey Tables for a JSON Column

[English](#english) | [한국어](#한국어)

---

## English

> **Migrated, not verified.** Moved on 2026-10-06 from the author's notes site (clickhouse.kr), as written there. The steps and numbers have not been re-run in this repository. The English text is an LLM-assisted translation of the Korean original.

The following describes the process of defining the problem and deriving a solution. An organization is working on a requirement to store and analyze survey data.

In the initial design for collecting survey data, a separate table was created for each survey and the questions were defined as columns. As the number of surveys grew, the number of tables grew linearly, creating a risk of reaching ClickHouse's hard limit. Currently there are 5 tables for 5 surveys, and a metadata table is managed separately; since the number and type of questions differ per survey, there is little that can be shared between tables. To solve this, we want to migrate to a structure that converts all survey data into one unified table (One Big Table), storing survey metadata as common columns and the variable survey responses in a JSON column.

---

### 1. Understanding the problem

#### 1.1 Background

The initial system design for collecting survey data was a structure in which **a new table is created for every survey** and **each question becomes a column of the table**. For example, if a survey called "customer satisfaction survey" has 5 questions, a table named `survey_customer_satisfaction` is created, and q1, q2, q3, q4 and q5 are each defined as separate columns.

This design had the advantages of being intuitive and keeping queries simple at first. However, as the service grew, the number of surveys kept increasing, and as a result **the number of tables increased linearly**. If 5 surveys are in operation now, there are 5 survey response tables, plus a separate table that manages survey metadata.

A bigger problem is that **the number and type of questions differ from survey to survey**. Some surveys are simple scale ratings with 4 questions, while others have 12 questions including free text, multiple choice and NPS scores. This leaves very little that can be shared between tables, and cross-survey analysis requires complex UNION ALL queries.

#### 1.2 Direction of the solution

In this situation, we concluded that **survey data should be consolidated into a One Big Table form**. The unified table should contain the following elements.

First, **survey metadata**. These are fields common to all surveys, such as survey_id identifying the survey, the survey name, respondent information and submission time.

Second, **survey-specific context**. This is classification information that applies only to certain surveys, such as "department" in an employee survey or "event name" in event feedback.

Third, **survey response data**. These are the actual response values, whose number and type of questions vary; this part can be **consolidated into a JSON column** to gain schema flexibility.

This report is the result of carrying out the whole process in a real ClickHouse Cloud environment, creating 5 legacy survey tables and migrating them to a JSON-based unified table, in order to **verify the technical feasibility** of this direction.

#### 1.3 Structural limits of the current architecture

The current survey system creates an independent table for each survey. Because the questions of a survey are defined as table columns, a survey with 5 questions becomes a table with 8 columns (including common fields), and a survey with 12 questions becomes a table with 16 columns.

**Legacy tables created in the test environment for verification:**

```text
┌─table────────────────────────┬─column_count─┬─columns──────────────────────────────────────┐
│ survey_employee_satisfaction │           16 │ [response_id, respondent_id, submitted_at,  │
│                              │              │  department, q1_job_satisfaction, ...       │
│                              │              │  q12_additional_comments]                   │
│ survey_product_experience    │           11 │ [response_id, respondent_id, submitted_at,  │
│                              │              │  q1_usage_frequency, ... q8_overall_exp]    │
│ survey_event_feedback        │           10 │ [response_id, ... q6_suggestions]           │
│ survey_customer_satisfaction │            8 │ [response_id, ... q5_feedback]              │
│ survey_website_ux            │            7 │ [response_id, ... q4_overall_ux_score]      │
└──────────────────────────────┴──────────────┴──────────────────────────────────────────────┘

```

**Example DDL for creating legacy tables:**

```sql
-- a new table is needed for every survey
CREATE TABLE survey.survey_customer_satisfaction (
    response_id UUID DEFAULT generateUUIDv4(),
    respondent_id UInt32,
    submitted_at DateTime DEFAULT now(),
    q1_overall_satisfaction UInt8,   -- question 1
    q2_service_quality UInt8,        -- question 2
    q3_price_satisfaction UInt8,     -- question 3
    q4_recommend_likelihood UInt8,   -- question 4
    q5_feedback String               -- question 5
) ENGINE = MergeTree()
ORDER BY (submitted_at, respondent_id)

-- another survey -> another table
CREATE TABLE survey.survey_employee_satisfaction (
    response_id UUID DEFAULT generateUUIDv4(),
    respondent_id UInt32,
    submitted_at DateTime DEFAULT now(),
    department String,
    q1_job_satisfaction UInt8,
    q2_work_life_balance UInt8,
    -- ... columns for 12 questions
    q12_additional_comments String
) ENGINE = MergeTree()
ORDER BY (submitted_at, respondent_id)

```

#### 1.4 Specific problems

**First, the risk of a hard limit from the growing number of tables.** ClickHouse Cloud limits the number of tables depending on the service tier. There are 5 tables for 5 surveys now, but if surveys grow to 1,000, 1,000 tables are needed. This goes beyond simply hitting a limit and affects operations overall: a heavier metadata management burden on ZooKeeper/Keeper, higher backup and recovery complexity, and difficult schema management.

```sql
-- tables currently in the survey schema
SELECT name, engine, total_rows, formatReadableSize(total_bytes) as size
FROM system.tables WHERE database = 'survey' ORDER BY name

```

```text
┌─name─────────────────────────┬─engine───────────┬─total_rows─┬─size──────┐
│ survey_customer_satisfaction │ SharedMergeTree  │         15 │ 1.55 KiB  │
│ survey_employee_satisfaction │ SharedMergeTree  │         20 │ 2.79 KiB  │
│ survey_event_feedback        │ SharedMergeTree  │         18 │ 1.94 KiB  │
│ survey_metadata              │ SharedMergeTree  │          5 │ 1.24 KiB  │
│ survey_product_experience    │ SharedMergeTree  │         12 │ 1.89 KiB  │
│ survey_website_ux            │ SharedMergeTree  │         10 │ 1.17 KiB  │
└──────────────────────────────┴──────────────────┴────────────┴───────────┘

```

**Second, the complexity of cross-survey analysis.** Analyzing responses across surveys requires UNION ALL, and the query must be modified every time a survey is added.

```sql
-- legacy: comparing satisfaction across 4 surveys needs UNION ALL (4 branches)
SELECT * FROM (
    SELECT 'SURV001' as survey_id, '고객 만족도' as survey_name,
           count() as cnt, avg(q1_overall_satisfaction) as avg_score
    FROM survey.survey_customer_satisfaction
    UNION ALL
    SELECT 'SURV003', '직원 만족도', count(), avg(q1_job_satisfaction)
    FROM survey.survey_employee_satisfaction
    UNION ALL
    SELECT 'SURV004', '이벤트 피드백', count(), avg(q1_event_satisfaction)
    FROM survey.survey_event_feedback
    UNION ALL
    SELECT 'SURV005', '웹사이트 UX', count(), avg(q1_navigation_ease)
    FROM survey.survey_website_ux
) ORDER BY survey_id

```

```text
┌─survey_id─┬─survey_name───┬─cnt─┬─avg_score─┐
│ SURV001   │ 고객 만족도    │  15 │       3.0 │
│ SURV003   │ 직원 만족도    │  20 │       3.2 │
│ SURV004   │ 이벤트 피드백  │  18 │      2.94 │
│ SURV005   │ 웹사이트 UX   │  10 │       2.0 │
└───────────┴───────────────┴─────┴───────────┘

```

**Third, increased operational complexity.** Every time a survey is added, repetitive work is needed: running DDL, setting up the ingestion pipeline, granting permissions and setting backup policy. As surveys grow to hundreds, this operational burden increases exponentially.

---

### 2. Solution: using ClickHouse JSON and Views

#### 2.1 Overview of the ClickHouse JSON type

The new JSON type introduced in ClickHouse 24.1+ supports **column-oriented storage**, unlike the earlier String-based JSON. Each path inside the JSON is stored as a separate subcolumn, which greatly improves compression efficiency and query performance.

**Key features:**

- Dynamic schema: can store JSON of various structures without predefinition
- Subcolumn access: direct access with the `column.path` syntax
- Type inference: types are detected automatically at storage time
- Optional type hints: explicit types can be given to frequently used fields

#### 2.2 JSON query patterns

#### Pattern 1: basic field access

```sql
-- access JSON fields directly with dot notation
SELECT
    respondent_id,
    responses.q1_overall_satisfaction as q1,
    responses.q5_feedback as feedback
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'
LIMIT 5

```

```text
┌─respondent_id─┬─q1─┬─feedback───────────┐
│          1000 │ 1  │ 매우 만족합니다     │
│          1001 │ 4  │ 추천하고 싶습니다   │
│          1002 │ 1  │ 매우 만족합니다     │
│          1003 │ 2  │ 개선이 필요합니다   │
│          1004 │ 4  │ 추천하고 싶습니다   │
└───────────────┴────┴────────────────────┘

```

#### Pattern 2: type casting for numeric operations

Values extracted from JSON are of the Dynamic type, so explicit casting is needed when using aggregate functions.

```sql
-- method 1: toUInt8OrZero + toString (safe conversion, returns 0 on failure)
SELECT
    avg(toUInt8OrZero(toString(responses.q1_overall_satisfaction))) as avg_q1,
    avg(toUInt8OrZero(toString(responses.q2_service_quality))) as avg_q2
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'

```

```text
┌─avg_q1─┬─avg_q2─┐
│    3.0 │    3.0 │
└────────┴────────┘

```

```sql
-- method 2: casting inside an expression
SELECT
    respondent_id,
    toUInt8(toString(responses.q1_overall_satisfaction)) as q1_score,
    toUInt8(toString(responses.q2_service_quality)) as q2_score,
    (toUInt8(toString(responses.q1_overall_satisfaction)) +
     toUInt8(toString(responses.q2_service_quality))) / 2 as avg_score
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'
LIMIT 3

```

```text
┌─respondent_id─┬─q1_score─┬─q2_score─┬─avg_score─┐
│          1004 │        4 │        4 │       4.0 │
│          1005 │        4 │        4 │       4.0 │
│          1014 │        3 │        3 │       3.0 │
└───────────────┴──────────┴──────────┴───────────┘

```

#### Pattern 3: exploring the JSON structure

You can dynamically look up which questions (keys) each survey has.

```sql
-- list the JSON keys (questions) of each survey
SELECT
    survey_id,
    survey_name,
    groupUniqArray(arrayJoin(JSONAllPaths(responses))) as question_keys
FROM survey.survey_responses_unified
GROUP BY survey_id, survey_name
ORDER BY survey_id

```

```text
┌─survey_id─┬─survey_name─────────┬─question_keys─────────────────────────────────────────┐
│ SURV001   │ 고객 만족도 조사     │ [q1_overall_satisfaction, q2_service_quality,        │
│           │                     │  q3_price_satisfaction, q4_recommend_likelihood,     │
│           │                     │  q5_feedback]                                        │
│ SURV002   │ 제품 사용 경험       │ [q1_usage_frequency, q2_ease_of_use, ... (8개)]      │
│ SURV003   │ 직원 만족도 조사     │ [q1_job_satisfaction, q2_work_life_balance, (12개)]  │
│ SURV004   │ 이벤트 피드백        │ [q1_event_satisfaction, ... (6개)]                   │
│ SURV005   │ 웹사이트 UX         │ [q1_navigation_ease, ... (4개)]                      │
└───────────┴─────────────────────┴───────────────────────────────────────────────────────┘

```

#### Pattern 4: checking whether a field exists

```sql
-- check whether a field exists with IS NOT NULL
SELECT
    survey_id,
    respondent_id,
    responses.q5_feedback IS NOT NULL as has_feedback,
    responses.q12_additional_comments IS NOT NULL as has_comments
FROM survey.survey_responses_unified
WHERE survey_id IN ('SURV001', 'SURV003')
LIMIT 4

```

```text
┌─survey_id─┬─respondent_id─┬─has_feedback─┬─has_comments─┐
│ SURV001   │          1004 │            1 │            0 │
│ SURV001   │          1005 │            1 │            0 │
│ SURV003   │          3014 │            0 │            1 │
│ SURV003   │          3017 │            0 │            1 │
└───────────┴───────────────┴──────────────┴──────────────┘

```

#### Pattern 5: conditional filtering

```sql
-- filter on a JSON field value
SELECT survey_id, respondent_id,
       toUInt8OrZero(toString(responses.q1_overall_satisfaction)) as score
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'
  AND toUInt8OrZero(toString(responses.q1_overall_satisfaction)) >= 4
ORDER BY score DESC

```

```text
┌─survey_id─┬─respondent_id─┬─score─┐
│ SURV001   │          1011 │     5 │
│ SURV001   │          1006 │     5 │
│ SURV001   │          1004 │     4 │
│ SURV001   │          1005 │     4 │
│ SURV001   │          1001 │     4 │
└───────────┴───────────────┴───────┘

```

#### Pattern 6: grouping with context fields

Context information per survey (department, event name and so on) is stored in a separate JSON column and used in GROUP BY.

```sql
-- employee satisfaction by department
SELECT
    toString(context.department) as department,
    count() as response_count,
    round(avg(toUInt8OrZero(toString(responses.q1_job_satisfaction))), 2) as avg_satisfaction,
    round(avg(toUInt8OrZero(toString(responses.q11_recommend_employer))), 2) as avg_recommend
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV003'
GROUP BY department
ORDER BY avg_recommend DESC

```

```text
┌─department──┬─response_count─┬─avg_satisfaction─┬─avg_recommend─┐
│ Finance     │              5 │              5.0 │           9.0 │
│ HR          │              3 │              4.0 │          7.33 │
│ Sales       │              5 │              2.0 │           5.0 │
│ Marketing   │              5 │              3.0 │           5.0 │
│ Engineering │              2 │              1.0 │           3.5 │
└─────────────┴────────────────┴──────────────────┴───────────────┘

```

#### Pattern 7: cross-survey analysis

Compare and analyze several surveys in a single query without UNION ALL.

```sql
-- handle the different field names per survey with multiIf
SELECT
    survey_id,
    survey_name,
    count() as responses,
    round(avg(multiIf(
        survey_id = 'SURV001', toUInt8OrZero(toString(responses.q1_overall_satisfaction)),
        survey_id = 'SURV003', toUInt8OrZero(toString(responses.q1_job_satisfaction)),
        survey_id = 'SURV004', toUInt8OrZero(toString(responses.q1_event_satisfaction)),
        survey_id = 'SURV005', toUInt8OrZero(toString(responses.q1_navigation_ease)),
        0
    )), 2) as avg_primary_satisfaction
FROM survey.survey_responses_unified
WHERE survey_id IN ('SURV001', 'SURV003', 'SURV004', 'SURV005')
GROUP BY survey_id, survey_name
ORDER BY avg_primary_satisfaction DESC

```

```text
┌─survey_id─┬─survey_name──────────┬─responses─┬─avg_primary_satisfaction─┐
│ SURV003   │ 직원 만족도 조사      │        20 │                      3.2 │
│ SURV001   │ 고객 만족도 조사      │        15 │                      3.0 │
│ SURV004   │ 이벤트 피드백         │        18 │                     2.94 │
│ SURV005   │ 웹사이트 UX          │        10 │                      2.0 │
└───────────┴──────────────────────┴───────────┴──────────────────────────┘

```

#### Pattern 8: text search

```sql
-- search feedback with a LIKE pattern
SELECT respondent_id, toString(responses.q5_feedback) as feedback
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'
  AND toString(responses.q5_feedback) LIKE '%만족%'

```

```text
┌─respondent_id─┬─feedback──────────┐
│          1002 │ 매우 만족합니다    │
│          1012 │ 매우 만족합니다    │
│          1000 │ 매우 만족합니다    │
└───────────────┴───────────────────┘

```

#### 2.3 Performance optimization: Materialized View (limited use)

**Creating an MV per survey is not recommended.** Instead, create only a few **MVs for unified analytical metrics** that span all surveys.

```sql
-- MV for daily response counts across all surveys (a single MV covers every survey)
CREATE MATERIALIZED VIEW survey.mv_daily_survey_stats
ENGINE = SummingMergeTree()
ORDER BY (response_date, survey_id)
AS
SELECT
    toDate(submitted_at) as response_date,
    survey_id,
    survey_name,
    count() as daily_responses,
    uniq(respondent_id) as unique_respondents
FROM survey.survey_responses_unified
GROUP BY response_date, survey_id, survey_name

```

**Query using the unified MV:**

```sql
-- quickly query the daily response trend of all surveys
SELECT
    response_date,
    sum(daily_responses) as total_responses,
    sum(unique_respondents) as total_respondents
FROM survey.mv_daily_survey_stats
WHERE response_date >= today() - 30
GROUP BY response_date
ORDER BY response_date

```

This approach minimizes the number of objects while still allowing the key metrics needed for dashboards and monitoring to be queried quickly.

#### 2.4 Temporary use of Views, limited to the migration period

Views also count toward the number of objects, so **running per-survey compatibility Views permanently is not recommended.** However, if existing analytical queries cannot be modified right away during the migration period, you can **create temporary Views mainly for newly arriving data** to buy time for query conversion.

```sql
-- temporary compatibility View (to be dropped after the migration)
CREATE VIEW survey.v_temp_customer_satisfaction AS
SELECT
    response_id,
    respondent_id,
    submitted_at,
    toUInt8OrZero(toString(responses.q1_overall_satisfaction)) as q1_overall_satisfaction,
    toUInt8OrZero(toString(responses.q2_service_quality)) as q2_service_quality,
    toString(responses.q5_feedback) as q5_feedback
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'

```

**Principles for operating temporary Views:**

- Keep them only for the migration period (for example, 4 weeks)
- Delete Views one by one, starting with the surveys whose queries have been converted
- The final goal is for **all analytical queries to read the unified table directly**

#### 2.5 Improving performance with JSON type hints

For surveys whose schema is fixed, you can specify types on JSON subcolumns to eliminate runtime casting.

```sql
CREATE TABLE survey.survey_responses_with_typed_json (
    response_id UUID DEFAULT generateUUIDv4(),
    survey_id String,
    survey_name String,
    respondent_id UInt32,
    submitted_at DateTime,
    context JSON DEFAULT '{}',
    -- apply type hints to JSON subcolumns
    responses JSON(
        q1_overall_satisfaction UInt8,
        q2_service_quality UInt8,
        q3_price_satisfaction UInt8,
        q4_recommend_likelihood UInt8,
        q5_feedback String
    ),
    migrated_at DateTime DEFAULT now(),
    source_table String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(submitted_at)
ORDER BY (survey_id, submitted_at, respondent_id)

```

**Query after applying type hints (no casting needed):**

```sql
SELECT
    avg(responses.q1_overall_satisfaction) as avg_q1,
    avg(responses.q2_service_quality) as avg_q2
FROM survey.survey_responses_with_typed_json

```

```text
┌─avg_q1─┬─avg_q2─┐
│    3.0 │    3.0 │
└────────┴────────┘

```

---

### 3. Unified table design principles and usage

#### 3.1 Unified table schema

```sql
CREATE TABLE survey.survey_responses_unified (
    -- common metadata (for indexing and filtering)
    response_id UUID DEFAULT generateUUIDv4(),
    survey_id String,              -- survey identifier
    survey_name String,            -- survey name
    respondent_id UInt32,          -- respondent ID
    submitted_at DateTime,         -- submission time
    -- survey context (classification info)
    context JSON DEFAULT '{}',     -- department name, event name and so on
    -- survey responses (flexible storage)
    responses JSON,                -- all question responses
    -- migration metadata
    migrated_at DateTime DEFAULT now(),
    source_table String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(submitted_at)
ORDER BY (survey_id, submitted_at, respondent_id)

```

#### 3.2 Design principles

**Principle 1: explicit separation of common fields**

response_id, survey_id, respondent_id and submitted_at apply to every survey. Keeping them as separate columns lets ORDER BY and WHERE clauses use the index.

**Principle 2: separation of context and responses**

Information used for classification, such as department or event name, is stored in the `context` JSON, and the actual question responses in the `responses` JSON. This lets you optimize GROUP BY performance.

**Principle 3: partitioning strategy**

Monthly partitions with `toYYYYMM(submitted_at)` improve the performance of time-range queries.

#### 3.3 Ingesting a new survey (no DDL change needed)

Even when a new survey is added, data can be ingested without changing the table structure.

```sql
-- ingest new survey data
INSERT INTO survey.survey_responses_unified
    (survey_id, survey_name, respondent_id, submitted_at, context, responses, source_table)
VALUES
    ('SURV006', '신규 프로모션 피드백', 6001, now(),
     '{"campaign_name": "Summer Sale 2024"}',
     '{"q1_awareness": "social_media", "q2_interest_level": "5",
       "q3_purchase_intent": "yes", "q4_feedback": "좋은 이벤트입니다"}',
     'api_ingestion')

```

**Check the ingested data:**

```sql
SELECT survey_id, survey_name, respondent_id, context, responses
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV006'

```

```text
┌─survey_id─┬─survey_name──────────┬─respondent_id─┬─context─────────────────────────┬─responses───────────────────────────────────┐
│ SURV006   │ 신규 프로모션 피드백  │          6001 │ {"campaign_name":"Summer Sale"} │ {"q1_awareness":"social_media", ...}       │
│ SURV006   │ 신규 프로모션 피드백  │          6002 │ {"campaign_name":"Summer Sale"} │ {"q1_awareness":"email", ...}              │
└───────────┴──────────────────────┴───────────────┴─────────────────────────────────┴─────────────────────────────────────────────┘

```

#### 3.4 Comparing optimization strategies

| Strategy | Implementation complexity | Query performance | Storage cost | When to apply |
| --- | --- | --- | --- | --- |
| Basic JSON query | Low | Medium | None | All surveys |
| Materialized View | Medium | High | Additional storage | Frequently analyzed surveys |
| JSON type hints | Low | Medium-high | None | Surveys with a fixed schema |
| Compatibility View | Low | Medium | None | Migration period |
| Projection | Medium | High | Additional storage | Many aggregation queries |

---

### 4. Migration in practice

#### 4.1 Migration SQL

Move the data of each legacy table into the unified table. Columns are converted to JSON using the `toJSONString` and `map` functions.

**Customer satisfaction survey migration:**

```sql
INSERT INTO survey.survey_responses_unified
    (response_id, survey_id, survey_name, respondent_id, submitted_at,
     context, responses, source_table)
SELECT
    response_id,
    'SURV001' as survey_id,
    '고객 만족도 조사' as survey_name,
    respondent_id,
    submitted_at,
    '{}' as context,
    toJSONString(map(
        'q1_overall_satisfaction', toString(q1_overall_satisfaction),
        'q2_service_quality', toString(q2_service_quality),
        'q3_price_satisfaction', toString(q3_price_satisfaction),
        'q4_recommend_likelihood', toString(q4_recommend_likelihood),
        'q5_feedback', q5_feedback
    )) as responses,
    'survey_customer_satisfaction' as source_table
FROM survey.survey_customer_satisfaction

```

**Employee satisfaction survey migration (department included in context):**

```sql
INSERT INTO survey.survey_responses_unified
    (response_id, survey_id, survey_name, respondent_id, submitted_at,
     context, responses, source_table)
SELECT
    response_id,
    'SURV003' as survey_id,
    '직원 만족도 조사' as survey_name,
    respondent_id,
    submitted_at,
    toJSONString(map('department', department)) as context,
    toJSONString(map(
        'q1_job_satisfaction', toString(q1_job_satisfaction),
        'q2_work_life_balance', toString(q2_work_life_balance),
        -- ... remaining questions
        'q12_additional_comments', q12_additional_comments
    )) as responses,
    'survey_employee_satisfaction' as source_table
FROM survey.survey_employee_satisfaction

```

#### 4.2 Data consistency verification

**Row count comparison:**

```sql
SELECT
    survey_id, survey_name, source_table, count() as unified_count
FROM survey.survey_responses_unified
GROUP BY survey_id, survey_name, source_table
ORDER BY survey_id

```

```text
┌─survey_id─┬─survey_name──────────┬─source_table───────────────────┬─unified_count─┐
│ SURV001   │ 고객 만족도 조사      │ survey_customer_satisfaction   │            15 │
│ SURV002   │ 제품 사용 경험        │ survey_product_experience      │            12 │
│ SURV003   │ 직원 만족도 조사      │ survey_employee_satisfaction   │            20 │
│ SURV004   │ 이벤트 피드백         │ survey_event_feedback          │            18 │
│ SURV005   │ 웹사이트 UX          │ survey_website_ux              │            10 │
└───────────┴──────────────────────┴────────────────────────────────┴───────────────┘

```

**Value comparison (legacy vs unified):**

```sql
-- legacy table
SELECT respondent_id, q1_overall_satisfaction, q2_service_quality, q5_feedback
FROM survey.survey_customer_satisfaction ORDER BY respondent_id LIMIT 3

```

```text
┌─respondent_id─┬─q1_overall_satisfaction─┬─q2_service_quality─┬─q5_feedback────────┐
│          1000 │                       1 │                  1 │ 매우 만족합니다     │
│          1001 │                       4 │                  4 │ 추천하고 싶습니다   │
│          1002 │                       1 │                  1 │ 매우 만족합니다     │
└───────────────┴─────────────────────────┴────────────────────┴────────────────────┘

```

```sql
-- unified table
SELECT respondent_id,
       responses.q1_overall_satisfaction as q1,
       responses.q2_service_quality as q2,
       responses.q5_feedback as feedback
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001' ORDER BY respondent_id LIMIT 3

```

```text
┌─respondent_id─┬─q1─┬─q2─┬─feedback───────────┐
│          1000 │ 1  │ 1  │ 매우 만족합니다     │
│          1001 │ 4  │ 4  │ 추천하고 싶습니다   │
│          1002 │ 1  │ 1  │ 매우 만족합니다     │
└───────────────┴────┴────┴────────────────────┘

```

#### 4.3 Storage comparison

```sql
SELECT
    'Legacy Tables (Sum)' as category,
    sum(total_rows) as total_rows,
    formatReadableSize(sum(total_bytes)) as compressed_size
FROM system.tables
WHERE database = 'survey'
  AND name IN ('survey_customer_satisfaction', 'survey_product_experience',
               'survey_employee_satisfaction', 'survey_event_feedback', 'survey_website_ux')

UNION ALL

SELECT 'Unified Table', total_rows, formatReadableSize(total_bytes)
FROM system.tables
WHERE database = 'survey' AND name = 'survey_responses_unified'

```

```text
┌─category─────────────┬─total_rows─┬─compressed_size─┐
│ Legacy Tables (Sum)  │         75 │ 9.34 KiB        │
│ Unified Table        │         78 │ 11.24 KiB       │
└──────────────────────┴────────────┴─────────────────┘

```

The unified table grows by about 20% because JSON key names are stored repeatedly, but the benefit of reducing the number of tables from 5 to 1 (an 80% decrease) is far greater.

#### 4.4 Table/column count comparison

```sql
SELECT
    'Legacy Tables Total' as category, sum(column_count) as total_columns
FROM (
    SELECT count() as column_count
    FROM system.columns
    WHERE database = 'survey'
      AND table IN ('survey_customer_satisfaction', 'survey_product_experience',
                    'survey_employee_satisfaction', 'survey_event_feedback', 'survey_website_ux')
    GROUP BY table
)
UNION ALL
SELECT 'Unified Table', count()
FROM system.columns
WHERE database = 'survey' AND table = 'survey_responses_unified'

```

```text
┌─category─────────────┬─total_columns─┐
│ Legacy Tables Total  │            52 │
│ Unified Table        │             9 │
└──────────────────────┴───────────────┘

```

#### 4.5 Step-by-step migration plan

| Phase | Duration | Work |
| --- | --- | --- |
| Phase 1 | 2 weeks | Create the unified table; ingest new surveys into it from the start |
| Phase 2 | 4 weeks | Batch-migrate legacy data; create compatibility Views |
| Phase 3 | 2 weeks | Switch analytical queries, add MVs, monitor performance |
| Phase 4 | 2 weeks | Archive and clean up legacy tables |

---

### 5. Summary

#### 5.1 Key verification results

In this POC, 5 legacy survey tables (75 rows in total, 52 columns) were successfully migrated into a single JSON-based unified table (9 columns).

| Item | Legacy | Unified | Change |
| --- | --- | --- | --- |
| Number of tables | 5 | 1 | 80% decrease |
| Total columns | 52 | 9 | 83% decrease |
| Row count | 75 | 75 | 100% retained |
| Compressed size | 9.34 KiB | 11.24 KiB | 20% increase |
| Adding a new survey | DDL required | No DDL required | Simpler operations |
| Cross-survey analysis | UNION ALL required | Single query | Simpler queries |

#### 5.2 Trade-offs

**Improvements:**

- Fundamentally resolves the table hard limit problem
- No DDL change needed when adding a new survey
- Cross-survey analysis possible in a single query
- Central management of survey metadata

**Costs:**

- Queries need type casting (can be resolved with MVs/Views)
- Slightly more storage because JSON keys are stored
- Existing queries need to be modified (gradual transition with compatibility Views)

#### 5.3 Recommendations

**First, proceed with the migration.** Compared with the hard-limit risk, the added query complexity can be adequately offset with MVs and Views.

**Second, apply Materialized Views to frequently analyzed surveys.** This removes the JSON parsing overhead and lets you keep the legacy query shape.

**Third, transition gradually.** Use compatibility Views to keep existing analytical queries unchanged, then switch step by step to new queries after verification.

**Fourth, manage a question metadata table in addition.** Manage each survey's question definitions (question_id, question_text, question_type) in a separate table to compensate for the visibility of the JSON structure.

#### 5.4 Summary of created objects

| Object | Type | Purpose |
| --- | --- | --- |
| survey.survey_responses_unified | Table | Unified response storage |
| survey.survey_responses_with_typed_json | Table | Type hint example |
| survey.mv_customer_satisfaction | Materialized View | Performance optimization example |
| survey.v_survey_customer_satisfaction | View | Compatibility layer example |

---

---

## 한국어

> **이관본, 미검증.** 2026-10-06 작성자의 노트 사이트(clickhouse.kr)에서 원문 그대로 옮겼습니다. 이 저장소에서 단계와 수치를 다시 실행하지 않았습니다. 영어본은 한국어 원문을 LLM 도움으로 번역한 것입니다.

다음은 문제상황을 정의하고 해결방안을 도출한 과정입니다. 한 조직은 설문 데이터를 저장하고 분석하는 요건을 진행하고 있습니다.

설문지 데이터를 수집하기 위한 최초 설계에서는 각 설문지마다 별도의 테이블을 생성하고 문항을 컬럼으로 정의하는 구조를 채택했으나, 설문 수가 증가함에 따라 테이블 수도 선형적으로 늘어나 ClickHouse의 Hard Limit에 도달할 위험이 발생했습니다. 현재 5개 설문에 5개 테이블이 존재하며 메타 정보 테이블까지 별도로 관리되고 있는데, 설문별로 문항 수와 형태가 상이하여 테이블 간 공통화할 수 있는 요소가 제한적입니다. 이를 해결하기 위해 모든 설문 데이터를 하나의 통합 테이블(One Big Table)로 전환하고, 설문 메타 정보는 공통 컬럼으로, 가변적인 설문 응답은 JSON 컬럼으로 저장하는 구조로 마이그레이션하고자 합니다.

---

### 1. 문제 상황의 이해

#### 1.1 배경

설문지 데이터를 수집하기 위한 최초의 시스템 설계는 **매 설문지마다 새로운 테이블을 생성**하고, **각 문항이 테이블의 컬럼이 되는 구조**였습니다. 예를 들어, "고객 만족도 조사"라는 설문이 5개 문항을 가지고 있다면 `survey_customer_satisfaction`이라는 테이블이 생성되고, q1, q2, q3, q4, q5 각각이 별도의 컬럼으로 정의되는 방식입니다.

이 설계는 초기에는 직관적이고 쿼리가 단순하다는 장점이 있었습니다. 그러나 서비스가 성장하면서 설문의 수가 지속적으로 증가하게 되었고, 이에 따라 **테이블 수가 선형적으로 증가**하는 문제가 발생했습니다. 현재 5개의 설문이 운영 중이라면 5개의 설문 응답 테이블이 존재하며, 여기에 설문지 메타 정보를 관리하는 테이블까지 별도로 존재합니다.

더 큰 문제는 **설문지마다 문항 수와 형태가 상이**하다는 점입니다. 어떤 설문은 4개 문항의 간단한 척도 평가이고, 어떤 설문은 12개 문항에 자유 텍스트, 다중 선택, NPS 점수 등 다양한 형태를 포함합니다. 이로 인해 테이블 간 공통화할 수 있는 요소가 매우 제한적이며, 크로스 설문 분석 시 복잡한 UNION ALL 쿼리가 필요합니다.

#### 1.2 해결 방향

이러한 상황에서 **설문지 데이터를 One Big Table 형태로 통합**해야 한다는 결론에 도달했습니다. 통합 테이블에는 다음 요소들이 포함되어야 합니다.

첫째, **설문의 메타 정보**입니다. 어떤 설문인지 식별하는 survey_id, 설문 이름, 응답자 정보, 제출 시간 등 모든 설문에 공통으로 적용되는 필드들입니다.

둘째, **설문별 컨텍스트 정보**입니다. 직원 설문의 "부서명", 이벤트 피드백의 "이벤트명"처럼 특정 설문에만 해당하는 분류 정보입니다.

셋째, **설문 응답 데이터**입니다. 문항 수와 형태가 다양한 실제 응답 값들로, 이 부분은 **JSON 컬럼으로 통합**하여 스키마 유연성을 확보할 수 있습니다.

본 보고서는 이 해결 방향의 **기술적 타당성을 검증**하기 위해, 실제 ClickHouse Cloud 환경에서 5개의 레거시 설문 테이블을 생성하고, JSON 기반 통합 테이블로 마이그레이션하는 전 과정을 수행한 결과입니다.

#### 1.3 현재 아키텍처의 구조적 한계

현재 설문 시스템은 각 설문지마다 독립적인 테이블을 생성하는 구조입니다. 설문지의 문항이 테이블의 컬럼으로 정의되어 있어, 5개 문항의 설문은 8개 컬럼(공통 필드 포함), 12개 문항의 설문은 16개 컬럼을 가진 테이블이 됩니다.

**검증을 위해 테스트 환경에서 생성한 레거시 테이블 현황:**

```text
┌─table────────────────────────┬─column_count─┬─columns──────────────────────────────────────┐
│ survey_employee_satisfaction │           16 │ [response_id, respondent_id, submitted_at,  │
│                              │              │  department, q1_job_satisfaction, ...       │
│                              │              │  q12_additional_comments]                   │
│ survey_product_experience    │           11 │ [response_id, respondent_id, submitted_at,  │
│                              │              │  q1_usage_frequency, ... q8_overall_exp]    │
│ survey_event_feedback        │           10 │ [response_id, ... q6_suggestions]           │
│ survey_customer_satisfaction │            8 │ [response_id, ... q5_feedback]              │
│ survey_website_ux            │            7 │ [response_id, ... q4_overall_ux_score]      │
└──────────────────────────────┴──────────────┴──────────────────────────────────────────────┘

```

**레거시 테이블 생성 DDL 예시:**

```sql
-- 설문마다 새로운 테이블 생성 필요
CREATE TABLE survey.survey_customer_satisfaction (
    response_id UUID DEFAULT generateUUIDv4(),
    respondent_id UInt32,
    submitted_at DateTime DEFAULT now(),
    q1_overall_satisfaction UInt8,   -- 문항 1
    q2_service_quality UInt8,        -- 문항 2
    q3_price_satisfaction UInt8,     -- 문항 3
    q4_recommend_likelihood UInt8,   -- 문항 4
    q5_feedback String               -- 문항 5
) ENGINE = MergeTree()
ORDER BY (submitted_at, respondent_id)

-- 또 다른 설문 → 또 다른 테이블
CREATE TABLE survey.survey_employee_satisfaction (
    response_id UUID DEFAULT generateUUIDv4(),
    respondent_id UInt32,
    submitted_at DateTime DEFAULT now(),
    department String,
    q1_job_satisfaction UInt8,
    q2_work_life_balance UInt8,
    -- ... 12개 문항에 대한 컬럼들
    q12_additional_comments String
) ENGINE = MergeTree()
ORDER BY (submitted_at, respondent_id)

```

#### 1.4 구체적인 문제점

**첫째, 테이블 수 증가로 인한 Hard Limit 위험입니다.** ClickHouse Cloud는 서비스 티어에 따라 테이블 수에 제한이 있습니다. 현재 5개 설문에 5개 테이블이지만, 설문이 1,000개로 늘어나면 1,000개의 테이블이 필요합니다. 이는 단순히 제한에 걸리는 문제를 넘어서, ZooKeeper/Keeper의 메타데이터 관리 부담 증가, 백업 및 복구 복잡도 상승, 스키마 관리의 어려움 등 운영 전반에 영향을 미칩니다.

```sql
-- 현재 survey 스키마의 테이블 현황
SELECT name, engine, total_rows, formatReadableSize(total_bytes) as size
FROM system.tables WHERE database = 'survey' ORDER BY name

```

```text
┌─name─────────────────────────┬─engine───────────┬─total_rows─┬─size──────┐
│ survey_customer_satisfaction │ SharedMergeTree  │         15 │ 1.55 KiB  │
│ survey_employee_satisfaction │ SharedMergeTree  │         20 │ 2.79 KiB  │
│ survey_event_feedback        │ SharedMergeTree  │         18 │ 1.94 KiB  │
│ survey_metadata              │ SharedMergeTree  │          5 │ 1.24 KiB  │
│ survey_product_experience    │ SharedMergeTree  │         12 │ 1.89 KiB  │
│ survey_website_ux            │ SharedMergeTree  │         10 │ 1.17 KiB  │
└──────────────────────────────┴──────────────────┴────────────┴───────────┘

```

**둘째, 크로스 설문 분석의 복잡성입니다.** 여러 설문의 응답을 통합 분석하려면 UNION ALL을 사용해야 하며, 설문이 추가될 때마다 쿼리를 수정해야 합니다.

```sql
-- 레거시: 4개 설문의 만족도 비교 → UNION ALL 4회 필요
SELECT * FROM (
    SELECT 'SURV001' as survey_id, '고객 만족도' as survey_name,
           count() as cnt, avg(q1_overall_satisfaction) as avg_score
    FROM survey.survey_customer_satisfaction
    UNION ALL
    SELECT 'SURV003', '직원 만족도', count(), avg(q1_job_satisfaction)
    FROM survey.survey_employee_satisfaction
    UNION ALL
    SELECT 'SURV004', '이벤트 피드백', count(), avg(q1_event_satisfaction)
    FROM survey.survey_event_feedback
    UNION ALL
    SELECT 'SURV005', '웹사이트 UX', count(), avg(q1_navigation_ease)
    FROM survey.survey_website_ux
) ORDER BY survey_id

```

```text
┌─survey_id─┬─survey_name───┬─cnt─┬─avg_score─┐
│ SURV001   │ 고객 만족도    │  15 │       3.0 │
│ SURV003   │ 직원 만족도    │  20 │       3.2 │
│ SURV004   │ 이벤트 피드백  │  18 │      2.94 │
│ SURV005   │ 웹사이트 UX   │  10 │       2.0 │
└───────────┴───────────────┴─────┴───────────┘

```

**셋째, 운영 복잡도 증가입니다.** 신규 설문 추가 시마다 DDL 실행, 입수 파이프라인 설정, 권한 부여, 백업 정책 설정 등 반복적인 작업이 필요합니다. 설문이 수백 개로 늘어나면 이러한 운영 부담이 기하급수적으로 증가합니다.

---

### 2. 해결 방안: ClickHouse JSON과 View 활용

#### 2.1 ClickHouse JSON 타입 개요

ClickHouse 24.1+에서 도입된 새로운 JSON 타입은 기존 String 기반 JSON과 달리 **컬럼 지향 저장**을 지원합니다. JSON 내부의 각 경로(path)가 별도의 서브컬럼으로 저장되어 압축 효율과 쿼리 성능이 크게 향상됩니다.

**핵심 특징:**

- 동적 스키마: 사전 정의 없이 다양한 구조의 JSON 저장 가능
- 서브컬럼 접근: `column.path` 문법으로 직접 접근
- 타입 추론: 저장 시점에 자동 타입 감지
- 선택적 타입 힌트: 자주 사용하는 필드에 명시적 타입 지정 가능

#### 2.2 JSON 쿼리 패턴

#### 패턴 1: 기본 필드 접근

```sql
-- 점(.) 표기법으로 JSON 필드에 직접 접근
SELECT
    respondent_id,
    responses.q1_overall_satisfaction as q1,
    responses.q5_feedback as feedback
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'
LIMIT 5

```

```text
┌─respondent_id─┬─q1─┬─feedback───────────┐
│          1000 │ 1  │ 매우 만족합니다     │
│          1001 │ 4  │ 추천하고 싶습니다   │
│          1002 │ 1  │ 매우 만족합니다     │
│          1003 │ 2  │ 개선이 필요합니다   │
│          1004 │ 4  │ 추천하고 싶습니다   │
└───────────────┴────┴────────────────────┘

```

#### 패턴 2: 숫자 연산을 위한 타입 캐스팅

JSON에서 추출한 값은 Dynamic 타입이므로 집계 함수 사용 시 명시적 캐스팅이 필요합니다.

```sql
-- 방법 1: toUInt8OrZero + toString (안전한 변환, 실패 시 0 반환)
SELECT
    avg(toUInt8OrZero(toString(responses.q1_overall_satisfaction))) as avg_q1,
    avg(toUInt8OrZero(toString(responses.q2_service_quality))) as avg_q2
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'

```

```text
┌─avg_q1─┬─avg_q2─┐
│    3.0 │    3.0 │
└────────┴────────┘

```

```sql
-- 방법 2: 계산식에서의 캐스팅
SELECT
    respondent_id,
    toUInt8(toString(responses.q1_overall_satisfaction)) as q1_score,
    toUInt8(toString(responses.q2_service_quality)) as q2_score,
    (toUInt8(toString(responses.q1_overall_satisfaction)) +
     toUInt8(toString(responses.q2_service_quality))) / 2 as avg_score
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'
LIMIT 3

```

```text
┌─respondent_id─┬─q1_score─┬─q2_score─┬─avg_score─┐
│          1004 │        4 │        4 │       4.0 │
│          1005 │        4 │        4 │       4.0 │
│          1014 │        3 │        3 │       3.0 │
└───────────────┴──────────┴──────────┴───────────┘

```

#### 패턴 3: JSON 구조 탐색

설문별로 어떤 문항(키)이 있는지 동적으로 조회할 수 있습니다.

```sql
-- 설문별 JSON 키(문항) 목록 조회
SELECT
    survey_id,
    survey_name,
    groupUniqArray(arrayJoin(JSONAllPaths(responses))) as question_keys
FROM survey.survey_responses_unified
GROUP BY survey_id, survey_name
ORDER BY survey_id

```

```text
┌─survey_id─┬─survey_name─────────┬─question_keys─────────────────────────────────────────┐
│ SURV001   │ 고객 만족도 조사     │ [q1_overall_satisfaction, q2_service_quality,        │
│           │                     │  q3_price_satisfaction, q4_recommend_likelihood,     │
│           │                     │  q5_feedback]                                        │
│ SURV002   │ 제품 사용 경험       │ [q1_usage_frequency, q2_ease_of_use, ... (8개)]      │
│ SURV003   │ 직원 만족도 조사     │ [q1_job_satisfaction, q2_work_life_balance, (12개)]  │
│ SURV004   │ 이벤트 피드백        │ [q1_event_satisfaction, ... (6개)]                   │
│ SURV005   │ 웹사이트 UX         │ [q1_navigation_ease, ... (4개)]                      │
└───────────┴─────────────────────┴───────────────────────────────────────────────────────┘

```

#### 패턴 4: 필드 존재 여부 확인

```sql
-- IS NOT NULL로 필드 존재 여부 확인
SELECT
    survey_id,
    respondent_id,
    responses.q5_feedback IS NOT NULL as has_feedback,
    responses.q12_additional_comments IS NOT NULL as has_comments
FROM survey.survey_responses_unified
WHERE survey_id IN ('SURV001', 'SURV003')
LIMIT 4

```

```text
┌─survey_id─┬─respondent_id─┬─has_feedback─┬─has_comments─┐
│ SURV001   │          1004 │            1 │            0 │
│ SURV001   │          1005 │            1 │            0 │
│ SURV003   │          3014 │            0 │            1 │
│ SURV003   │          3017 │            0 │            1 │
└───────────┴───────────────┴──────────────┴──────────────┘

```

#### 패턴 5: 조건부 필터링

```sql
-- JSON 필드 값 기반 필터링
SELECT survey_id, respondent_id,
       toUInt8OrZero(toString(responses.q1_overall_satisfaction)) as score
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'
  AND toUInt8OrZero(toString(responses.q1_overall_satisfaction)) >= 4
ORDER BY score DESC

```

```text
┌─survey_id─┬─respondent_id─┬─score─┐
│ SURV001   │          1011 │     5 │
│ SURV001   │          1006 │     5 │
│ SURV001   │          1004 │     4 │
│ SURV001   │          1005 │     4 │
│ SURV001   │          1001 │     4 │
└───────────┴───────────────┴───────┘

```

#### 패턴 6: Context 필드를 활용한 그룹화

설문별 컨텍스트 정보(부서, 이벤트명 등)를 별도 JSON 컬럼에 저장하고 GROUP BY에 활용합니다.

```sql
-- 부서별 직원 만족도 분석
SELECT
    toString(context.department) as department,
    count() as response_count,
    round(avg(toUInt8OrZero(toString(responses.q1_job_satisfaction))), 2) as avg_satisfaction,
    round(avg(toUInt8OrZero(toString(responses.q11_recommend_employer))), 2) as avg_recommend
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV003'
GROUP BY department
ORDER BY avg_recommend DESC

```

```text
┌─department──┬─response_count─┬─avg_satisfaction─┬─avg_recommend─┐
│ Finance     │              5 │              5.0 │           9.0 │
│ HR          │              3 │              4.0 │          7.33 │
│ Sales       │              5 │              2.0 │           5.0 │
│ Marketing   │              5 │              3.0 │           5.0 │
│ Engineering │              2 │              1.0 │           3.5 │
└─────────────┴────────────────┴──────────────────┴───────────────┘

```

#### 패턴 7: 크로스 설문 통합 분석

UNION ALL 없이 단일 쿼리로 여러 설문을 비교 분석합니다.

```sql
-- multiIf로 설문별 다른 필드명 처리
SELECT
    survey_id,
    survey_name,
    count() as responses,
    round(avg(multiIf(
        survey_id = 'SURV001', toUInt8OrZero(toString(responses.q1_overall_satisfaction)),
        survey_id = 'SURV003', toUInt8OrZero(toString(responses.q1_job_satisfaction)),
        survey_id = 'SURV004', toUInt8OrZero(toString(responses.q1_event_satisfaction)),
        survey_id = 'SURV005', toUInt8OrZero(toString(responses.q1_navigation_ease)),
        0
    )), 2) as avg_primary_satisfaction
FROM survey.survey_responses_unified
WHERE survey_id IN ('SURV001', 'SURV003', 'SURV004', 'SURV005')
GROUP BY survey_id, survey_name
ORDER BY avg_primary_satisfaction DESC

```

```text
┌─survey_id─┬─survey_name──────────┬─responses─┬─avg_primary_satisfaction─┐
│ SURV003   │ 직원 만족도 조사      │        20 │                      3.2 │
│ SURV001   │ 고객 만족도 조사      │        15 │                      3.0 │
│ SURV004   │ 이벤트 피드백         │        18 │                     2.94 │
│ SURV005   │ 웹사이트 UX          │        10 │                      2.0 │
└───────────┴──────────────────────┴───────────┴──────────────────────────┘

```

#### 패턴 8: 텍스트 검색

```sql
-- LIKE 패턴으로 피드백 검색
SELECT respondent_id, toString(responses.q5_feedback) as feedback
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'
  AND toString(responses.q5_feedback) LIKE '%만족%'

```

```text
┌─respondent_id─┬─feedback──────────┐
│          1002 │ 매우 만족합니다    │
│          1012 │ 매우 만족합니다    │
│          1000 │ 매우 만족합니다    │
└───────────────┴───────────────────┘

```

#### 2.3 성능 최적화: Materialized View (제한적 활용)

**설문별로 MV를 생성하는 것은 권장하지 않습니다.** 대신, 전체 설문을 아우르는 **통합 분석 지표용 MV**를 소수만 생성하여 활용합니다.

```sql
-- 전체 설문 통합 일별 응답 현황 MV (단일 MV로 모든 설문 커버)
CREATE MATERIALIZED VIEW survey.mv_daily_survey_stats
ENGINE = SummingMergeTree()
ORDER BY (response_date, survey_id)
AS
SELECT
    toDate(submitted_at) as response_date,
    survey_id,
    survey_name,
    count() as daily_responses,
    uniq(respondent_id) as unique_respondents
FROM survey.survey_responses_unified
GROUP BY response_date, survey_id, survey_name

```

**통합 MV 활용 쿼리:**

```sql
-- 전체 설문의 일별 응답 추이를 빠르게 조회
SELECT
    response_date,
    sum(daily_responses) as total_responses,
    sum(unique_respondents) as total_respondents
FROM survey.mv_daily_survey_stats
WHERE response_date >= today() - 30
GROUP BY response_date
ORDER BY response_date

```

이 방식은 오브젝트 수를 최소화하면서도 대시보드나 모니터링에 필요한 핵심 지표를 빠르게 조회할 수 있게 합니다.

#### 2.4 마이그레이션 기간 한정: View의 임시 활용

View 역시 오브젝트 수에 포함되므로, **설문별 호환성 View를 상시 운영하는 것은 권장하지 않습니다.** 다만, 마이그레이션 기간 동안 기존 분석 쿼리를 즉시 수정하기 어려운 경우, **신규 유입 데이터 위주로 임시 View를 생성**하여 쿼리 전환 시간을 확보할 수 있습니다.

```sql
-- 임시 호환성 View (마이그레이션 완료 후 삭제 예정)
CREATE VIEW survey.v_temp_customer_satisfaction AS
SELECT
    response_id,
    respondent_id,
    submitted_at,
    toUInt8OrZero(toString(responses.q1_overall_satisfaction)) as q1_overall_satisfaction,
    toUInt8OrZero(toString(responses.q2_service_quality)) as q2_service_quality,
    toString(responses.q5_feedback) as q5_feedback
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001'

```

**임시 View 운영 원칙:**

- 마이그레이션 기간(예: 4주) 동안만 유지
- 쿼리 전환이 완료된 설문부터 순차적으로 View 삭제
- 최종 목표는 **모든 분석 쿼리가 통합 테이블을 직접 조회**하는 것

#### 2.5 JSON 타입 힌트로 성능 향상

스키마가 확정된 설문에는 JSON 서브컬럼에 타입을 명시하여 런타임 캐스팅을 제거할 수 있습니다.

```sql
CREATE TABLE survey.survey_responses_with_typed_json (
    response_id UUID DEFAULT generateUUIDv4(),
    survey_id String,
    survey_name String,
    respondent_id UInt32,
    submitted_at DateTime,
    context JSON DEFAULT '{}',
    -- JSON 서브컬럼에 타입 힌트 적용
    responses JSON(
        q1_overall_satisfaction UInt8,
        q2_service_quality UInt8,
        q3_price_satisfaction UInt8,
        q4_recommend_likelihood UInt8,
        q5_feedback String
    ),
    migrated_at DateTime DEFAULT now(),
    source_table String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(submitted_at)
ORDER BY (survey_id, submitted_at, respondent_id)

```

**타입 힌트 적용 후 쿼리 (캐스팅 불필요):**

```sql
SELECT
    avg(responses.q1_overall_satisfaction) as avg_q1,
    avg(responses.q2_service_quality) as avg_q2
FROM survey.survey_responses_with_typed_json

```

```text
┌─avg_q1─┬─avg_q2─┐
│    3.0 │    3.0 │
└────────┴────────┘

```

---

### 3. 통합 테이블 설계 원칙 및 활용 방안

#### 3.1 통합 테이블 스키마

```sql
CREATE TABLE survey.survey_responses_unified (
    -- 공통 메타 정보 (인덱싱 및 필터링용)
    response_id UUID DEFAULT generateUUIDv4(),
    survey_id String,              -- 설문 식별자
    survey_name String,            -- 설문 이름
    respondent_id UInt32,          -- 응답자 ID
    submitted_at DateTime,         -- 제출 시간

    -- 설문 컨텍스트 (분류 정보)
    context JSON DEFAULT '{}',     -- 부서명, 이벤트명 등

    -- 설문 응답 (유연한 저장)
    responses JSON,                -- 모든 문항 응답

    -- 마이그레이션 메타데이터
    migrated_at DateTime DEFAULT now(),
    source_table String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(submitted_at)
ORDER BY (survey_id, submitted_at, respondent_id)

```

#### 3.2 설계 원칙

**원칙 1: 공통 필드의 명시적 분리**

response_id, survey_id, respondent_id, submitted_at은 모든 설문에 공통으로 적용됩니다. 이들을 별도 컬럼으로 유지하면 ORDER BY와 WHERE 절에서 인덱스를 활용할 수 있습니다.

**원칙 2: 컨텍스트와 응답의 분리**

부서명이나 이벤트명처럼 분류에 사용되는 정보는 `context` JSON에, 실제 문항 응답은 `responses` JSON에 분리 저장합니다. 이를 통해 GROUP BY 성능을 최적화할 수 있습니다.

**원칙 3: 파티셔닝 전략**

`toYYYYMM(submitted_at)`으로 월별 파티션을 적용하여 시간 범위 쿼리 성능을 향상시킵니다.

#### 3.3 신규 설문 입수 (DDL 변경 불필요)

새로운 설문이 추가되어도 테이블 구조 변경 없이 데이터를 입수할 수 있습니다.

```sql
-- 신규 설문 데이터 입수
INSERT INTO survey.survey_responses_unified
    (survey_id, survey_name, respondent_id, submitted_at, context, responses, source_table)
VALUES
    ('SURV006', '신규 프로모션 피드백', 6001, now(),
     '{"campaign_name": "Summer Sale 2024"}',
     '{"q1_awareness": "social_media", "q2_interest_level": "5",
       "q3_purchase_intent": "yes", "q4_feedback": "좋은 이벤트입니다"}',
     'api_ingestion')

```

**입수된 데이터 확인:**

```sql
SELECT survey_id, survey_name, respondent_id, context, responses
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV006'

```

```text
┌─survey_id─┬─survey_name──────────┬─respondent_id─┬─context─────────────────────────┬─responses───────────────────────────────────┐
│ SURV006   │ 신규 프로모션 피드백  │          6001 │ {"campaign_name":"Summer Sale"} │ {"q1_awareness":"social_media", ...}       │
│ SURV006   │ 신규 프로모션 피드백  │          6002 │ {"campaign_name":"Summer Sale"} │ {"q1_awareness":"email", ...}              │
└───────────┴──────────────────────┴───────────────┴─────────────────────────────────┴─────────────────────────────────────────────┘

```

#### 3.4 최적화 전략 비교

| 전략 | 구현 복잡도 | 쿼리 성능 | 스토리지 비용 | 적용 시점 |
| --- | --- | --- | --- | --- |
| 기본 JSON 쿼리 | 낮음 | 보통 | 없음 | 모든 설문 |
| Materialized View | 중간 | 높음 | 추가 저장 | 자주 분석하는 설문 |
| JSON 타입 힌트 | 낮음 | 중상 | 없음 | 스키마 확정 설문 |
| 호환성 View | 낮음 | 보통 | 없음 | 마이그레이션 기간 |
| 프로젝션 | 중간 | 높음 | 추가 저장 | 집계 쿼리 다수 |

---

### 4. 마이그레이션의 실제

#### 4.1 마이그레이션 SQL

각 레거시 테이블의 데이터를 통합 테이블로 이관합니다. `toJSONString`과 `map` 함수를 사용하여 컬럼들을 JSON으로 변환합니다.

**고객 만족도 설문 마이그레이션:**

```sql
INSERT INTO survey.survey_responses_unified
    (response_id, survey_id, survey_name, respondent_id, submitted_at,
     context, responses, source_table)
SELECT
    response_id,
    'SURV001' as survey_id,
    '고객 만족도 조사' as survey_name,
    respondent_id,
    submitted_at,
    '{}' as context,
    toJSONString(map(
        'q1_overall_satisfaction', toString(q1_overall_satisfaction),
        'q2_service_quality', toString(q2_service_quality),
        'q3_price_satisfaction', toString(q3_price_satisfaction),
        'q4_recommend_likelihood', toString(q4_recommend_likelihood),
        'q5_feedback', q5_feedback
    )) as responses,
    'survey_customer_satisfaction' as source_table
FROM survey.survey_customer_satisfaction

```

**직원 만족도 설문 마이그레이션 (context에 department 포함):**

```sql
INSERT INTO survey.survey_responses_unified
    (response_id, survey_id, survey_name, respondent_id, submitted_at,
     context, responses, source_table)
SELECT
    response_id,
    'SURV003' as survey_id,
    '직원 만족도 조사' as survey_name,
    respondent_id,
    submitted_at,
    toJSONString(map('department', department)) as context,
    toJSONString(map(
        'q1_job_satisfaction', toString(q1_job_satisfaction),
        'q2_work_life_balance', toString(q2_work_life_balance),
        -- ... 나머지 문항들
        'q12_additional_comments', q12_additional_comments
    )) as responses,
    'survey_employee_satisfaction' as source_table
FROM survey.survey_employee_satisfaction

```

#### 4.2 데이터 정합성 검증

**건수 비교:**

```sql
SELECT
    survey_id, survey_name, source_table, count() as unified_count
FROM survey.survey_responses_unified
GROUP BY survey_id, survey_name, source_table
ORDER BY survey_id

```

```text
┌─survey_id─┬─survey_name──────────┬─source_table───────────────────┬─unified_count─┐
│ SURV001   │ 고객 만족도 조사      │ survey_customer_satisfaction   │            15 │
│ SURV002   │ 제품 사용 경험        │ survey_product_experience      │            12 │
│ SURV003   │ 직원 만족도 조사      │ survey_employee_satisfaction   │            20 │
│ SURV004   │ 이벤트 피드백         │ survey_event_feedback          │            18 │
│ SURV005   │ 웹사이트 UX          │ survey_website_ux              │            10 │
└───────────┴──────────────────────┴────────────────────────────────┴───────────────┘

```

**값 비교 (레거시 vs 통합):**

```sql
-- 레거시 테이블
SELECT respondent_id, q1_overall_satisfaction, q2_service_quality, q5_feedback
FROM survey.survey_customer_satisfaction ORDER BY respondent_id LIMIT 3

```

```text
┌─respondent_id─┬─q1_overall_satisfaction─┬─q2_service_quality─┬─q5_feedback────────┐
│          1000 │                       1 │                  1 │ 매우 만족합니다     │
│          1001 │                       4 │                  4 │ 추천하고 싶습니다   │
│          1002 │                       1 │                  1 │ 매우 만족합니다     │
└───────────────┴─────────────────────────┴────────────────────┴────────────────────┘

```

```sql
-- 통합 테이블
SELECT respondent_id,
       responses.q1_overall_satisfaction as q1,
       responses.q2_service_quality as q2,
       responses.q5_feedback as feedback
FROM survey.survey_responses_unified
WHERE survey_id = 'SURV001' ORDER BY respondent_id LIMIT 3

```

```text
┌─respondent_id─┬─q1─┬─q2─┬─feedback───────────┐
│          1000 │ 1  │ 1  │ 매우 만족합니다     │
│          1001 │ 4  │ 4  │ 추천하고 싶습니다   │
│          1002 │ 1  │ 1  │ 매우 만족합니다     │
└───────────────┴────┴────┴────────────────────┘

```

#### 4.3 스토리지 비교

```sql
SELECT
    'Legacy Tables (Sum)' as category,
    sum(total_rows) as total_rows,
    formatReadableSize(sum(total_bytes)) as compressed_size
FROM system.tables
WHERE database = 'survey'
  AND name IN ('survey_customer_satisfaction', 'survey_product_experience',
               'survey_employee_satisfaction', 'survey_event_feedback', 'survey_website_ux')

UNION ALL

SELECT 'Unified Table', total_rows, formatReadableSize(total_bytes)
FROM system.tables
WHERE database = 'survey' AND name = 'survey_responses_unified'

```

```text
┌─category─────────────┬─total_rows─┬─compressed_size─┐
│ Legacy Tables (Sum)  │         75 │ 9.34 KiB        │
│ Unified Table        │         78 │ 11.24 KiB       │
└──────────────────────┴────────────┴─────────────────┘

```

통합 테이블은 JSON 키 이름이 반복 저장되어 약 20% 정도 크기가 증가하지만, 테이블 수가 5개에서 1개로 80% 감소하는 이점이 훨씬 큽니다.

#### 4.4 테이블/컬럼 수 비교

```sql
SELECT
    'Legacy Tables Total' as category, sum(column_count) as total_columns
FROM (
    SELECT count() as column_count
    FROM system.columns
    WHERE database = 'survey'
      AND table IN ('survey_customer_satisfaction', 'survey_product_experience',
                    'survey_employee_satisfaction', 'survey_event_feedback', 'survey_website_ux')
    GROUP BY table
)
UNION ALL
SELECT 'Unified Table', count()
FROM system.columns
WHERE database = 'survey' AND table = 'survey_responses_unified'

```

```text
┌─category─────────────┬─total_columns─┐
│ Legacy Tables Total  │            52 │
│ Unified Table        │             9 │
└──────────────────────┴───────────────┘

```

#### 4.5 마이그레이션 단계별 계획

| Phase | 기간 | 작업 내용 |
| --- | --- | --- |
| Phase 1 | 2주 | 통합 테이블 생성, 신규 설문부터 통합 테이블에 입수 |
| Phase 2 | 4주 | 레거시 데이터 배치 마이그레이션, 호환성 View 생성 |
| Phase 3 | 2주 | 분석 쿼리 전환, MV 추가, 성능 모니터링 |
| Phase 4 | 2주 | 레거시 테이블 아카이브 및 정리 |

---

### 5. 정리

#### 5.1 핵심 검증 결과

본 POC에서 5개의 레거시 설문 테이블(총 75건, 52개 컬럼)을 JSON 기반 단일 통합 테이블(9개 컬럼)로 성공적으로 마이그레이션했습니다.

| 항목 | 레거시 | 통합 | 변화 |
| --- | --- | --- | --- |
| 테이블 수 | 5 | 1 | 80% 감소 |
| 총 컬럼 수 | 52 | 9 | 83% 감소 |
| 데이터 건수 | 75 | 75 | 100% 유지 |
| 압축 크기 | 9.34 KiB | 11.24 KiB | 20% 증가 |
| 신규 설문 추가 | DDL 필요 | DDL 불필요 | 운영 간소화 |
| 크로스 분석 | UNION ALL 필요 | 단일 쿼리 | 쿼리 단순화 |

#### 5.2 트레이드오프

**개선되는 점:**

- 테이블 Hard Limit 문제 근본 해결
- 신규 설문 추가 시 DDL 변경 불필요
- 크로스 설문 분석이 단일 쿼리로 가능
- 설문 메타데이터 중앙 관리

**비용:**

- 쿼리에 타입 캐스팅 필요 (MV/View로 해소 가능)
- JSON 키 저장으로 스토리지 약간 증가
- 기존 쿼리 수정 필요 (호환성 View로 점진적 전환)

#### 5.3 권장사항

**첫째, 마이그레이션을 진행합니다.** Hard Limit 리스크 대비 쿼리 복잡도 증가는 MV와 View로 충분히 보완 가능합니다.

**둘째, 자주 분석하는 설문에는 Materialized View를 적용합니다.** JSON 파싱 오버헤드를 제거하고 레거시 쿼리 형태를 유지할 수 있습니다.

**셋째, 점진적 전환을 수행합니다.** 호환성 View를 활용하여 기존 분석 쿼리를 수정 없이 유지하면서, 검증 후 단계적으로 신규 쿼리로 전환합니다.

**넷째, 문항 메타데이터 테이블을 추가로 관리합니다.** 각 설문의 문항 정의(question_id, question_text, question_type)를 별도 테이블로 관리하여 JSON 구조의 가시성을 보완합니다.

#### 5.4 생성된 오브젝트 요약

| 오브젝트 | 타입 | 용도 |
| --- | --- | --- |
| survey.survey_responses_unified | Table | 통합 응답 저장 |
| survey.survey_responses_with_typed_json | Table | 타입 힌트 적용 예시 |
| survey.mv_customer_satisfaction | Materialized View | 성능 최적화 예시 |
| survey.v_survey_customer_satisfaction | View | 호환성 레이어 예시 |

---

*실행 환경: ClickHouse Cloud (ap-northeast-2)*
