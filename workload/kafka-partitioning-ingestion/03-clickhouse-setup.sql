-- ============================================================================
-- kafka-partitioning-ingestion Step 3: ClickHouse targets + Kafka-engine consumers
-- 카프카 파티셔닝 인제스천 3단계: ClickHouse 타겟 + Kafka 엔진 컨슈머
-- ============================================================================
-- This lab compares THREE ingestion paths × TWO partitioning strategies. Every
-- target is the SAME MergeTree (ORDER BY (customer_id, ts), granularity 8192,
-- merges stopped). The only thing that varies is how each path turns Kafka
-- partitions into ClickHouse parts:
--
--   PATH A  Kafka engine, DEFAULT       1 consumer multiplexes all partitions
--           (kafka_default_aligned)     into one INSERT block → locality DILUTED
--                                       even when the topic is range-partitioned.
--
--   PATH B  Kafka engine, TUNED         kafka_num_consumers = NUM_PARTITIONS +
--           (kafka_misaligned/aligned)  kafka_thread_per_consumer=1 → each
--                                       consumer flushes its OWN partition →
--                                       part = one partition's key range.
--
--   PATH C  Kafka Connect Sink          batches per topic-partition by design
--           (connect_*, see step 04)    → locality preserved with no tuning,
--                                       but many small parts (rely on merges).
--
-- 이 실습은 세 가지 인제스천 경로 × 두 가지 파티셔닝 전략을 비교한다. 모든 타겟은
-- 동일한 MergeTree다. 경로가 Kafka 파티션을 ClickHouse part로 바꾸는 방식만 다르다.
--   A) Kafka 엔진 기본값: 단일 컨슈머가 모든 파티션을 한 INSERT 블록에 멀티플렉싱 →
--      range 토픽이어도 지역성 희석.
--   B) Kafka 엔진 튜닝: 컨슈머=파티션수 + thread_per_consumer=1 → 컨슈머별 분리 flush.
--   C) Kafka Connect Sink: 설계상 topic-partition 단위 배치 → 무튜닝으로 지역성 유지,
--      대신 작은 part 다수(머지에 의존).
--
-- NOTE: kafka_num_consumers is hard-coded to 8 below. If you change
--       NUM_PARTITIONS in .env, change these to match.
--
-- Apply:
--   docker compose exec -T clickhouse clickhouse-client --multiquery < 03-clickhouse-setup.sql
-- ============================================================================

CREATE DATABASE IF NOT EXISTS kpart;

-- ─────────────────────────────────────────────────────────────────────────
-- 3.0 A dedicated user for the Kafka Connect Sink (step 04). The stock image's
--     `default` user rejects HTTP auth over the network, so Connect needs its own.
-- 3.0 Kafka Connect Sink용 전용 유저. 기본 이미지의 default 유저는 네트워크 HTTP 인증을
--     거부하므로 Connect 전용 유저가 필요하다.
-- ─────────────────────────────────────────────────────────────────────────
CREATE USER IF NOT EXISTS connect IDENTIFIED WITH plaintext_password BY 'connect';
GRANT SELECT, INSERT, CREATE, DROP, TRUNCATE, ALTER ON kpart.* TO connect;
GRANT SELECT ON system.* TO connect;

-- Clean any previous run.
DROP TABLE IF EXISTS kpart.mv_misaligned;
DROP TABLE IF EXISTS kpart.mv_aligned;
DROP TABLE IF EXISTS kpart.mv_default_aligned;
DROP TABLE IF EXISTS kpart.kafka_misaligned;
DROP TABLE IF EXISTS kpart.kafka_aligned;
DROP TABLE IF EXISTS kpart.kafka_default_aligned;
DROP TABLE IF EXISTS kpart.engine_misaligned;
DROP TABLE IF EXISTS kpart.engine_aligned;
DROP TABLE IF EXISTS kpart.engine_default_aligned;
DROP TABLE IF EXISTS kpart.connect_misaligned;
DROP TABLE IF EXISTS kpart.connect_aligned;

-- ─────────────────────────────────────────────────────────────────────────
-- 3.1 Target MergeTree tables — IDENTICAL schema/ORDER BY across all 5.
-- 3.1 타겟 MergeTree — 5개 모두 스키마·ORDER BY 동일.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE kpart.engine_misaligned     (customer_id UInt32, ts DateTime, val UInt32) ENGINE=MergeTree ORDER BY (customer_id, ts) SETTINGS index_granularity=8192;
CREATE TABLE kpart.engine_aligned        (customer_id UInt32, ts DateTime, val UInt32) ENGINE=MergeTree ORDER BY (customer_id, ts) SETTINGS index_granularity=8192;
CREATE TABLE kpart.engine_default_aligned(customer_id UInt32, ts DateTime, val UInt32) ENGINE=MergeTree ORDER BY (customer_id, ts) SETTINGS index_granularity=8192;
CREATE TABLE kpart.connect_misaligned    (customer_id UInt32, ts DateTime, val UInt32) ENGINE=MergeTree ORDER BY (customer_id, ts) SETTINGS index_granularity=8192;
CREATE TABLE kpart.connect_aligned       (customer_id UInt32, ts DateTime, val UInt32) ENGINE=MergeTree ORDER BY (customer_id, ts) SETTINGS index_granularity=8192;

-- Freeze merges so per-path part-level differences stay visible during the lab.
-- 머지를 멈춰 경로별 part 단위 차이를 실습 내내 관찰 가능하게 둔다.
SYSTEM STOP MERGES kpart.engine_misaligned;
SYSTEM STOP MERGES kpart.engine_aligned;
SYSTEM STOP MERGES kpart.engine_default_aligned;
SYSTEM STOP MERGES kpart.connect_misaligned;
SYSTEM STOP MERGES kpart.connect_aligned;

-- ─────────────────────────────────────────────────────────────────────────
-- 3.2 PATH B — Kafka engine, TUNED: one consumer per partition, parallel flush.
-- 3.2 경로 B — Kafka 엔진 튜닝: 파티션당 컨슈머 1개, 병렬 flush.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE kpart.kafka_misaligned (customer_id UInt32, ts DateTime, val UInt32)
ENGINE = Kafka SETTINGS
  kafka_broker_list = 'kafka:9092', kafka_topic_list = 'events_misaligned',
  kafka_group_name = 'ch_misaligned', kafka_format = 'JSONEachRow',
  kafka_num_consumers = 8, kafka_thread_per_consumer = 1, kafka_max_block_size = 1048576;

CREATE TABLE kpart.kafka_aligned (customer_id UInt32, ts DateTime, val UInt32)
ENGINE = Kafka SETTINGS
  kafka_broker_list = 'kafka:9092', kafka_topic_list = 'events_aligned',
  kafka_group_name = 'ch_aligned', kafka_format = 'JSONEachRow',
  kafka_num_consumers = 8, kafka_thread_per_consumer = 1, kafka_max_block_size = 1048576;

CREATE MATERIALIZED VIEW kpart.mv_misaligned TO kpart.engine_misaligned AS
  SELECT customer_id, ts, val FROM kpart.kafka_misaligned;
CREATE MATERIALIZED VIEW kpart.mv_aligned TO kpart.engine_aligned AS
  SELECT customer_id, ts, val FROM kpart.kafka_aligned;

-- ─────────────────────────────────────────────────────────────────────────
-- 3.3 PATH A — Kafka engine, DEFAULT (the gotcha): a single consumer with no
--     thread_per_consumer multiplexes ALL partitions into each INSERT block,
--     so even the range-partitioned topic produces full-range (wide) parts.
-- 3.3 경로 A — Kafka 엔진 기본값(함정): 단일 컨슈머가 모든 파티션을 INSERT 블록에
--     멀티플렉싱 → range 토픽조차 전 범위(넓은) part 생성.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE kpart.kafka_default_aligned (customer_id UInt32, ts DateTime, val UInt32)
ENGINE = Kafka SETTINGS
  kafka_broker_list = 'kafka:9092', kafka_topic_list = 'events_aligned',
  kafka_group_name = 'ch_aligned_default', kafka_format = 'JSONEachRow';
  -- (no kafka_num_consumers, no kafka_thread_per_consumer → defaults)

CREATE MATERIALIZED VIEW kpart.mv_default_aligned TO kpart.engine_default_aligned AS
  SELECT customer_id, ts, val FROM kpart.kafka_default_aligned;

SELECT 'setup complete — next: ./04-register-connectors.sh, then python 05-produce.py' AS status;
