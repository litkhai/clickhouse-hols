-- Expansion example, not run in this lab. Runs on (Managed) Postgres, where an operations app
-- keeps tickets and area owners; pg_clickhouse reads the lake's alert view in place.
-- Same statements as clickhouse-managed-postgres-hols extensions/pg-clickhouse-lab
-- (verified there 2026-10-01 on pg_clickhouse 0.11.0, PostgreSQL 18.6); host and password are placeholders.
CREATE EXTENSION IF NOT EXISTS pg_clickhouse;

CREATE SERVER lake FOREIGN DATA WRAPPER clickhouse_fdw
    OPTIONS (driver 'binary', host '<clickhouse host>', port '9000', dbname 'oss_lake');
CREATE USER MAPPING FOR CURRENT_USER SERVER lake
    OPTIONS (user 'oss_reader', password '<password>');

CREATE SCHEMA lake;
IMPORT FOREIGN SCHEMA oss_lake LIMIT TO (uc_alert_areas) FROM SERVER lake INTO lake;

-- who to call: this minute's alert areas with their owner team and open tickets
SELECT a.area, a.cells, a.drop_db, o.team, count(t.id) AS open_tickets
FROM lake.uc_alert_areas AS a
JOIN ops.area_owner AS o ON o.area = a.area
LEFT JOIN ops.ticket AS t ON t.area = a.area AND t.status = 'open'
GROUP BY a.area, a.cells, a.drop_db, o.team
ORDER BY a.cells DESC;
