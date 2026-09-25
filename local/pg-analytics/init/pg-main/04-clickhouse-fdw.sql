-- Path C: pg_clickhouse foreign tables over ClickHouse's bench.* views, which
-- in turn read the same Iceberg tables through Polaris (DataLakeCatalog).
DROP SERVER IF EXISTS ch CASCADE;
CREATE SERVER ch FOREIGN DATA WRAPPER clickhouse_fdw
  OPTIONS (driver 'binary', host 'clickhouse', port '9000', dbname 'bench');
CREATE USER MAPPING FOR CURRENT_USER SERVER ch OPTIONS (user 'default', password '');
DROP SCHEMA IF EXISTS ch CASCADE;
CREATE SCHEMA ch;
IMPORT FOREIGN SCHEMA bench FROM SERVER ch INTO ch;
SELECT foreign_table_name FROM information_schema.foreign_tables WHERE foreign_table_schema = 'ch' ORDER BY 1;
