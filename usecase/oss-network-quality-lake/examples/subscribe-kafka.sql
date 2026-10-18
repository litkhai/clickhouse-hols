-- Example, not run in this lab (it needs a Kafka broker): publish each minute's alerts to a
-- topic that an on-call app or chat bot subscribes to. Inserting into a Kafka-engine table
-- produces messages; a refreshable MV with APPEND does that once a minute.
CREATE TABLE oss_lake.alerts_topic
(
    area String, city UInt8, minute DateTime, cells UInt64, drop_db Float64, rsrp_now Float64
)
ENGINE = Kafka
SETTINGS kafka_broker_list = 'broker:9092',
         kafka_topic_list  = 'noc-alerts',
         kafka_group_name  = 'oss-lake',
         kafka_format      = 'JSONEachRow';

CREATE MATERIALIZED VIEW oss_lake.alerts_publish
REFRESH EVERY 1 MINUTE APPEND TO oss_lake.alerts_topic AS
SELECT area, city, minute, cells, drop_db, rsrp_now FROM oss_lake.uc_alert_areas;
