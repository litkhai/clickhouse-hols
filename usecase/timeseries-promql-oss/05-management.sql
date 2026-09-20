SELECT '===== 1. Two gotchas worth knowing before you hit them =====';

-- Left as comments rather than executed: `--multiquery` aborts on the first
-- exception, and this repo's release labs run end to end with zero
-- exceptions — so the failure modes below are documented, not demonstrated
-- live. Uncomment either line yourself in `clickhouse-client` to see it.

-- Forgetting the table-creation flag:
--   CREATE TABLE will_fail ENGINE = TimeSeries;
--   → Code: 344, SUPPORT_IS_DISABLED:
--     "Experimental TimeSeries table engine is not enabled
--      (the setting 'allow_experimental_time_series_table')"

-- Plain SQL SELECT on the outer table, even after it is created — as of
-- 26.8 only PromQL (03/04) or the inner tables below can read it back:
--   SELECT * FROM metrics LIMIT 1;
--   → Code: 48, NOT_IMPLEMENTED:
--     "SELECT is not supported by storage TimeSeries yet"

SET allow_experimental_time_series_table = 1;

SELECT '===== 3. Looking under the hood: the four inner tables =====';

-- `system.tables` is real SQL and works fine — it is only the TimeSeries
-- facade itself, not its storage, that SELECT cannot touch. This finds the
-- current `metrics` table's own inner tables by UUID, so it keeps working
-- even after 01-schema.sh has been re-run and the UUID has changed.
SELECT
    splitByChar('.', name)[3] AS role,
    total_rows,
    formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = currentDatabase()
  AND name LIKE '.inner_id.%.' || (SELECT toString(uuid) FROM system.tables WHERE name = 'metrics' AND database = currentDatabase())
ORDER BY role
FORMAT PrettyCompact;

SELECT '===== 4. recent_samples_ttl_seconds =====';

-- `recentsamples` above is a second, TTL-bounded copy of the same samples,
-- kept separately so that "give me the last N minutes across every series"
-- queries do not have to scan the full (potentially huge) `samples` table.
-- Default is 345600 seconds = 4 days; tables created with
-- `SETTINGS recent_samples_ttl_seconds = <n>` control the window explicitly.
SHOW CREATE TABLE metrics FORMAT Vertical;

SELECT '===== 5. Cleanup =====';

-- Dropping the outer table drops all four inner tables with it — nothing is
-- left behind to clean up separately.
DROP TABLE IF EXISTS metrics;

SELECT count() AS remaining_inner_tables
FROM system.tables
WHERE database = currentDatabase() AND name LIKE '.inner_id.%';
