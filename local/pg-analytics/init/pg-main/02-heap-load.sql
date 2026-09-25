-- Operational state before ILM: everything lives in PG heap (schema hot).
-- staging.* are pg_lake foreign tables over the Parquet that datagen wrote.
DROP SCHEMA IF EXISTS staging CASCADE;
CREATE SCHEMA staging;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['lineitem','orders','customer','part','partsupp','supplier','nation','region'] LOOP
    EXECUTE format('CREATE FOREIGN TABLE staging.%I () SERVER pg_lake OPTIONS (path %L)',
                   t, current_setting('bench.staging') || t || '/*.parquet');
  END LOOP;
END $$;

DROP SCHEMA IF EXISTS hot CASCADE;
CREATE SCHEMA hot;
CREATE TABLE hot.lineitem (
  l_orderkey bigint NOT NULL, l_partkey bigint NOT NULL, l_suppkey bigint NOT NULL,
  l_linenumber int NOT NULL, l_quantity numeric(15,2) NOT NULL,
  l_extendedprice numeric(15,2) NOT NULL, l_discount numeric(15,2) NOT NULL,
  l_tax numeric(15,2) NOT NULL, l_returnflag text NOT NULL, l_linestatus text NOT NULL,
  l_shipdate date NOT NULL, l_commitdate date NOT NULL, l_receiptdate date NOT NULL,
  l_shipinstruct text NOT NULL, l_shipmode text NOT NULL, l_comment text NOT NULL);
CREATE TABLE hot.orders (
  o_orderkey bigint NOT NULL, o_custkey bigint NOT NULL, o_orderstatus text NOT NULL,
  o_totalprice numeric(15,2) NOT NULL, o_orderdate date NOT NULL,
  o_orderpriority text NOT NULL, o_clerk text NOT NULL, o_shippriority int NOT NULL,
  o_comment text NOT NULL);
CREATE TABLE hot.customer (
  c_custkey bigint NOT NULL, c_name text NOT NULL, c_address text NOT NULL,
  c_nationkey int NOT NULL, c_phone text NOT NULL, c_acctbal numeric(15,2) NOT NULL,
  c_mktsegment text NOT NULL, c_comment text NOT NULL);
CREATE TABLE hot.part (
  p_partkey bigint NOT NULL, p_name text NOT NULL, p_mfgr text NOT NULL, p_brand text NOT NULL,
  p_type text NOT NULL, p_size int NOT NULL, p_container text NOT NULL,
  p_retailprice numeric(15,2) NOT NULL, p_comment text NOT NULL);
CREATE TABLE hot.partsupp (
  ps_partkey bigint NOT NULL, ps_suppkey bigint NOT NULL, ps_availqty int NOT NULL,
  ps_supplycost numeric(15,2) NOT NULL, ps_comment text NOT NULL);
CREATE TABLE hot.supplier (
  s_suppkey bigint NOT NULL, s_name text NOT NULL, s_address text NOT NULL,
  s_nationkey int NOT NULL, s_phone text NOT NULL, s_acctbal numeric(15,2) NOT NULL,
  s_comment text NOT NULL);
CREATE TABLE hot.nation (
  n_nationkey int NOT NULL, n_name text NOT NULL, n_regionkey int NOT NULL, n_comment text NOT NULL);
CREATE TABLE hot.region (
  r_regionkey int NOT NULL, r_name text NOT NULL, r_comment text NOT NULL);

\timing on
INSERT INTO hot.region   SELECT * FROM staging.region;
INSERT INTO hot.nation   SELECT * FROM staging.nation;
INSERT INTO hot.supplier SELECT * FROM staging.supplier;
INSERT INTO hot.customer SELECT * FROM staging.customer;
INSERT INTO hot.part     SELECT * FROM staging.part;
INSERT INTO hot.partsupp SELECT * FROM staging.partsupp;
-- :bulk (setup.py --bulk) keeps only the hot months in heap; 03 then writes
-- the cold months straight into Iceberg instead of the monthly tiering job.
\if :bulk
INSERT INTO hot.orders   SELECT * FROM staging.orders   WHERE o_orderdate >= current_setting('ilm.hot_cutoff')::date;
INSERT INTO hot.lineitem SELECT * FROM staging.lineitem WHERE l_shipdate  >= current_setting('ilm.hot_cutoff')::date;
\else
INSERT INTO hot.orders   SELECT * FROM staging.orders;
INSERT INTO hot.lineitem SELECT * FROM staging.lineitem;
\endif
\timing off

-- OLTP-side indexes the application would have. They make the tiering
-- DELETEs and the C6 point lookup honest on the heap side.
CREATE INDEX ON hot.orders (o_orderdate);
CREATE INDEX ON hot.orders (o_orderkey);
CREATE INDEX ON hot.lineitem (l_shipdate);
CREATE INDEX ON hot.lineitem (l_orderkey);
CREATE UNIQUE INDEX ON hot.customer (c_custkey);
CREATE UNIQUE INDEX ON hot.part (p_partkey);
CREATE UNIQUE INDEX ON hot.supplier (s_suppkey);
CREATE UNIQUE INDEX ON hot.partsupp (ps_partkey, ps_suppkey);
ANALYZE;
