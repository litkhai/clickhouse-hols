-- ClickHouse 26.1: Keeper HTTP API Test
-- New Feature: Built-in HTTP API and embedded web interface for ClickHouse Keeper

-- Note: This demo shows keeper-related queries and system tables
-- In a production environment with keeper enabled, you can access:
-- - HTTP API at keeper's HTTP port (typically 9182)
-- - Web UI at http://keeper-host:9182/
-- - REST endpoints for /status, /config, /metrics

-- ============================================
-- 1. Check Keeper Status via System Tables
-- ============================================

SELECT '========== 1. Keeper Status Information ==========';

-- Check if keeper is enabled (in single-node setup, may not be running)
SELECT
    'Checking Keeper Status' AS description,
    'In production, Keeper HTTP API available at port 9182' AS note;

-- Query zookeeper_info system table (new in 26.1)
-- Note: This requires keeper/zookeeper to be configured
SELECT '--- system.zookeeper_info table (new in 26.1) ---';

-- This table provides information about ZooKeeper integration
-- SELECT * FROM system.zookeeper_info LIMIT 5;
-- (Will work when keeper is configured)

-- ============================================
-- 2. Keeper Configuration Examples
-- ============================================

SELECT '========== 2. Keeper HTTP API Endpoints ==========';

SELECT 'HTTP API Endpoints Available in Production:' AS info;

SELECT
    endpoint,
    description,
    example_usage
FROM (
    SELECT '/status' AS endpoint, 'Keeper status and health' AS description, 'curl http://keeper:9182/status' AS example_usage
    UNION ALL
    SELECT '/config', 'Keeper configuration', 'curl http://keeper:9182/config'
    UNION ALL
    SELECT '/metrics', 'Prometheus-style metrics', 'curl http://keeper:9182/metrics'
    UNION ALL
    SELECT '/state', 'Current keeper state', 'curl http://keeper:9182/state'
    UNION ALL
    SELECT '/feature_flags', 'Available feature flags', 'curl http://keeper:9182/feature_flags'
) AS endpoints
ORDER BY endpoint;

-- ============================================
-- 3. Demonstrate Keeper rcfg Command (26.1)
-- ============================================

SELECT '========== 3. Keeper rcfg Command (New in 26.1) ==========';

SELECT 'The new rcfg four-letter command allows dynamic cluster configuration:' AS info;

SELECT
    command,
    description,
    example
FROM (
    SELECT 'rcfg' AS command,
           'Change cluster configuration' AS description,
           'echo "rcfg" | nc keeper-host 9181' AS example
    UNION ALL
    SELECT 'conf',
           'Show current configuration',
           'echo "conf" | nc keeper-host 9181'
    UNION ALL
    SELECT 'stat',
           'Show keeper statistics',
           'echo "stat" | nc keeper-host 9181'
    UNION ALL
    SELECT 'mntr',
           'Show keeper metrics',
           'echo "mntr" | nc keeper-host 9181'
) AS commands
ORDER BY command;

-- ============================================
-- 4. System Tables for Keeper Monitoring
-- ============================================

SELECT '========== 4. System Tables for Keeper Monitoring ==========';

-- Show available system tables related to keeper/zookeeper
SELECT
    name,
    comment
FROM system.tables
WHERE database = 'system'
  AND (name LIKE '%keeper%' OR name LIKE '%zookeeper%')
ORDER BY name;

-- ============================================
-- 5. Replication and Keeper Usage
-- ============================================

SELECT '========== 5. Replication Tables Using Keeper ==========';

-- Create a replicated table (in single-node, this is for demonstration)
DROP TABLE IF EXISTS replicated_example;

-- Note: In production with keeper, use ReplicatedMergeTree
-- CREATE TABLE replicated_example (
--     id UInt32,
--     timestamp DateTime,
--     value String
-- ) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/replicated_example', '{replica}')
-- ORDER BY (timestamp, id);

-- For single-node demo, use regular MergeTree
CREATE TABLE replicated_example (
    id UInt32,
    timestamp DateTime,
    value String
) ENGINE = MergeTree()
ORDER BY (timestamp, id);

INSERT INTO replicated_example VALUES
    (1, '2026-01-15 10:00:00', 'Sample data'),
    (2, '2026-01-15 10:01:00', 'More data'),
    (3, '2026-01-15 10:02:00', 'Test value');

SELECT 'In production with keeper, you can monitor:' AS info;

-- ============================================
-- 6. Keeper Web UI Features
-- ============================================

SELECT '========== 6. Keeper Web UI Features ==========';

SELECT
    feature,
    description
FROM (
    SELECT 'Dashboard' AS feature, 'Overview of keeper cluster status' AS description
    UNION ALL
    SELECT 'Metrics Viewer', 'Real-time metrics and performance graphs'
    UNION ALL
    SELECT 'Configuration', 'View and modify keeper configuration'
    UNION ALL
    SELECT 'Znode Browser', 'Browse and inspect znodes'
    UNION ALL
    SELECT 'Health Checks', 'Automated health status monitoring'
    UNION ALL
    SELECT 'Cluster View', 'Visualize cluster topology'
) AS features
ORDER BY feature;

-- ============================================
-- 7. Monitoring Example Queries
-- ============================================

SELECT '========== 7. Monitoring Queries for Keeper ==========';

-- Check system metrics
SELECT
    metric,
    value,
    description
FROM system.metrics
WHERE metric LIKE '%Keeper%' OR metric LIKE '%Zoo%'
ORDER BY metric
LIMIT 10;

-- Check system events related to keeper
SELECT
    event,
    value,
    description
FROM system.events
WHERE event LIKE '%Keeper%' OR event LIKE '%Zoo%'
ORDER BY value DESC
LIMIT 10;

-- ============================================
-- 8. Integration with Monitoring Tools
-- ============================================

SELECT '========== 8. Integration with External Monitoring ==========';

SELECT 'HTTP API enables integration with:' AS info;

SELECT
    tool,
    integration_method,
    use_case
FROM (
    SELECT 'Prometheus' AS tool,
           'Scrape /metrics endpoint' AS integration_method,
           'Time-series monitoring and alerting' AS use_case
    UNION ALL
    SELECT 'Grafana',
           'Use Prometheus as data source',
           'Visualization and dashboards'
    UNION ALL
    SELECT 'Custom Scripts',
           'Poll /status endpoint',
           'Automated health checks'
    UNION ALL
    SELECT 'Kubernetes',
           'Use /status for liveness probe',
           'Container orchestration'
    UNION ALL
    SELECT 'Nagios/Icinga',
           'HTTP check plugin',
           'Infrastructure monitoring'
) AS integrations
ORDER BY tool;

-- ============================================
-- 9. Example Health Check Script
-- ============================================

SELECT '========== 9. Sample Health Check Commands ==========';

SELECT 'Example shell commands for keeper monitoring:' AS info;

SELECT
    command_type,
    command,
    description
FROM (
    SELECT 'Basic Status' AS command_type,
           'curl -s http://keeper:9182/status | jq' AS command,
           'Get keeper status in JSON format' AS description
    UNION ALL
    SELECT 'Metrics',
           'curl -s http://keeper:9182/metrics',
           'Get Prometheus metrics'
    UNION ALL
    SELECT 'Configuration',
           'curl -s http://keeper:9182/config | jq',
           'View keeper configuration'
    UNION ALL
    SELECT 'Health Check',
           'curl -f http://keeper:9182/status || exit 1',
           'Simple health check for scripts'
    UNION ALL
    SELECT 'Four-Letter',
           'echo "stat" | nc keeper-host 9181',
           'Legacy four-letter commands'
) AS commands
ORDER BY command_type;

-- ============================================
-- 10. Production Best Practices
-- ============================================

SELECT '========== 10. Production Best Practices ==========';

SELECT
    category,
    recommendation
FROM (
    SELECT 'Monitoring' AS category, 'Use HTTP API for automated health checks' AS recommendation
    UNION ALL
    SELECT 'Monitoring', 'Set up Prometheus scraping on /metrics endpoint'
    UNION ALL
    SELECT 'High Availability', 'Deploy keeper in 3 or 5 node cluster'
    UNION ALL
    SELECT 'Security', 'Use authentication for HTTP API endpoints'
    UNION ALL
    SELECT 'Alerting', 'Configure alerts for keeper failures'
    UNION ALL
    SELECT 'Backup', 'Regular snapshots of keeper data'
    UNION ALL
    SELECT 'Network', 'Ensure low latency between keeper nodes'
    UNION ALL
    SELECT 'Resources', 'Dedicated machines for keeper in production'
) AS practices
ORDER BY category, recommendation;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS replicated_example;

SELECT '========== Test Complete ==========';
SELECT 'Keeper HTTP API provides easy monitoring and management without external tools!' AS summary;
