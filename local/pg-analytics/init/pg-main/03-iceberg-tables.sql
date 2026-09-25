-- Cold tier: Iceberg tables pg_lake owns, registered in Polaris (catalog = 'rest').
-- Schema tpch becomes the Polaris namespace ilm.tpch.
DROP SCHEMA IF EXISTS tpch CASCADE;
CREATE SCHEMA tpch;

CREATE TABLE tpch.lineitem_cold (LIKE hot.lineitem) USING iceberg
  WITH (catalog = 'rest', partition_by = 'month(l_shipdate)', autovacuum_enabled = 'false');
CREATE TABLE tpch.orders_cold (LIKE hot.orders) USING iceberg
  WITH (catalog = 'rest', partition_by = 'month(o_orderdate)', autovacuum_enabled = 'false');

-- Bulk mode: the cold months go in as one commit per table, straight from
-- the staged Parquet (pg_lake runs the INSERT … SELECT inside DuckDB).
\if :bulk
INSERT INTO tpch.orders_cold   SELECT * FROM staging.orders   WHERE o_orderdate < current_setting('ilm.hot_cutoff')::date;
-- lineitem one year per commit: a single 54 M-row partitioned write (SF10)
-- gets pg-main OOM-killed at the 4 GB cap.
INSERT INTO tpch.lineitem_cold SELECT * FROM staging.lineitem WHERE l_shipdate >= DATE '1992-01-01' AND l_shipdate < least(DATE '1993-01-01', current_setting('ilm.hot_cutoff')::date);
INSERT INTO tpch.lineitem_cold SELECT * FROM staging.lineitem WHERE l_shipdate >= DATE '1993-01-01' AND l_shipdate < least(DATE '1994-01-01', current_setting('ilm.hot_cutoff')::date);
INSERT INTO tpch.lineitem_cold SELECT * FROM staging.lineitem WHERE l_shipdate >= DATE '1994-01-01' AND l_shipdate < least(DATE '1995-01-01', current_setting('ilm.hot_cutoff')::date);
INSERT INTO tpch.lineitem_cold SELECT * FROM staging.lineitem WHERE l_shipdate >= DATE '1995-01-01' AND l_shipdate < least(DATE '1996-01-01', current_setting('ilm.hot_cutoff')::date);
INSERT INTO tpch.lineitem_cold SELECT * FROM staging.lineitem WHERE l_shipdate >= DATE '1996-01-01' AND l_shipdate < least(DATE '1997-01-01', current_setting('ilm.hot_cutoff')::date);
INSERT INTO tpch.lineitem_cold SELECT * FROM staging.lineitem WHERE l_shipdate >= DATE '1997-01-01' AND l_shipdate < least(DATE '1998-01-01', current_setting('ilm.hot_cutoff')::date);
INSERT INTO tpch.lineitem_cold SELECT * FROM staging.lineitem WHERE l_shipdate >= DATE '1998-01-01' AND l_shipdate < least(DATE '1999-01-01', current_setting('ilm.hot_cutoff')::date);
\endif

-- D1 (all-lake): dimension snapshots also exist in the lake. They stay in
-- heap too; scenario D2 reads them from there.
CREATE TABLE tpch.customer USING iceberg WITH (catalog = 'rest', autovacuum_enabled = 'false') AS SELECT * FROM hot.customer;
CREATE TABLE tpch.part     USING iceberg WITH (catalog = 'rest', autovacuum_enabled = 'false') AS SELECT * FROM hot.part;
CREATE TABLE tpch.partsupp USING iceberg WITH (catalog = 'rest', autovacuum_enabled = 'false') AS SELECT * FROM hot.partsupp;
CREATE TABLE tpch.supplier USING iceberg WITH (catalog = 'rest', autovacuum_enabled = 'false') AS SELECT * FROM hot.supplier;
CREATE TABLE tpch.nation   USING iceberg WITH (catalog = 'rest', autovacuum_enabled = 'false') AS SELECT * FROM hot.nation;
CREATE TABLE tpch.region   USING iceberg WITH (catalog = 'rest', autovacuum_enabled = 'false') AS SELECT * FROM hot.region;

SELECT table_namespace, table_name, metadata_location FROM iceberg_tables ORDER BY 2;
