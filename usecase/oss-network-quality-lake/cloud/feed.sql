-- Cloud only (cloud/load.py runs it after 01-05): the data keeps flowing by itself.
-- Locally the live demo's button does what feed_rmv does here.

-- A feed that never stops needs every layer to forget: the TTLs are in 01-schema.sql (bronze and
-- silver 1 day, gold 2 days, whole parts dropped). Not params: one row a minute is small, and an
-- emptied params would restart the feed at 1970 after a long pause.

-- Every minute: the next minutes of device traces, from the lake's 'now' up to the wall clock
-- (at most 5 per run, so a pause is caught up gradually). The WHERE makes a repeated run
-- insert nothing until anchor_rmv has moved 'now' past what is already in bronze.
CREATE MATERIALIZED VIEW oss_lake.feed_rmv
REFRESH EVERY 1 MINUTE APPEND TO oss_lake.ue_trace_raw AS
SELECT event_ts, h3_res09, imsi, rsrp, rsrq, sinr, cqi, pci, probe
FROM oss_lake.synth_traces(
    start = (SELECT max(anchor_ts) FROM oss_lake.params),
    minutes = (SELECT toUInt32(least(5, greatest(0, dateDiff('minute', max(anchor_ts), toStartOfMinute(now())))))
               FROM oss_lake.params))
WHERE (SELECT max(event_ts) FROM oss_lake.ue_trace_raw) < (SELECT max(anchor_ts) FROM oss_lake.params);

-- Then move the lake's 'now' to just after the last complete minute in bronze.
CREATE MATERIALIZED VIEW oss_lake.anchor_rmv
REFRESH EVERY 1 MINUTE DEPENDS ON oss_lake.feed_rmv APPEND TO oss_lake.params AS
SELECT toStartOfMinute(max(event_ts)) + INTERVAL 1 MINUTE AS anchor_ts
FROM oss_lake.ue_trace_raw
HAVING anchor_ts > (SELECT max(anchor_ts) FROM oss_lake.params);

-- And the 20 serving rows after that, so the screen never runs ahead of the data.
ALTER TABLE oss_lake.cell_rank_rmv MODIFY REFRESH EVERY 1 MINUTE DEPENDS ON oss_lake.anchor_rmv;

SELECT view, status, next_refresh_time FROM system.view_refreshes WHERE database = 'oss_lake'
ORDER BY view FORMAT PrettyCompactMonoBlock;
