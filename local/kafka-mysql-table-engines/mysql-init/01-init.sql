-- Create target table for ClickHouse MySQL engine
CREATE TABLE IF NOT EXISTS testdb.aggregated_events (
    event_date DATE NOT NULL,
    query_kind VARCHAR(50) NOT NULL,
    query_count BIGINT NOT NULL,
    total_duration_ms BIGINT NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (event_date, query_kind)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create raw events table for monitoring
CREATE TABLE IF NOT EXISTS testdb.raw_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_time TIMESTAMP NOT NULL,
    query_kind VARCHAR(50) NOT NULL,
    query_duration_ms INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

GRANT ALL PRIVILEGES ON testdb.* TO 'clickhouse'@'%';
FLUSH PRIVILEGES;
