# Device360 PoC - ClickHouse Performance Testing

Complete automation framework for testing ClickHouse's performance on high-cardinality device ID analysis patterns. This addresses the "Device360" use case where BigQuery struggles with point lookups and journey analysis on billions of device events.

## Overview

This framework provides:

1. **Synthetic Data Generation**: Creates realistic advertising request data (300GB compressed) with power-law distributed device IDs
2. **S3 Storage**: Uploads data to S3 with progress tracking and parallel uploads
3. **ClickHouse Integration**: Automated schema setup and data ingestion from S3
4. **Query Benchmarks**: Comprehensive test suite covering device journey analysis, aggregations, and bot detection
5. **Performance Monitoring**: Automated timing and results tracking

## Architecture

```
┌─────────────────┐
│  Data Generator │  → Synthetic device events with realistic patterns
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   S3 Storage    │  → Parallel upload, gzip compression
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   ClickHouse    │  → device_id-first indexing, materialized views
│   Cloud         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Query Suite    │  → Journey analysis, bot detection, aggregations
└─────────────────┘
```

## Prerequisites

- Python 3.8+
- AWS account with S3 access
- ClickHouse Cloud account
- ~500GB disk space for data generation (optional, can generate less for testing)

## Quick Start

### 1. Setup Environment

```bash
# Copy template
cp .env.template .env

# Edit .env with your credentials
vim .env
```

Required environment variables:
```bash
# AWS
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
AWS_REGION=us-east-1
S3_BUCKET_NAME=device360-test-data

# ClickHouse
CLICKHOUSE_HOST=your-instance.clickhouse.cloud
CLICKHOUSE_PASSWORD=your_password
CLICKHOUSE_DATABASE=device360

# Data generation
TARGET_SIZE_GB=300
NUM_RECORDS=500000000
NUM_DEVICES=100000000
```

### 2. Install Dependencies

```bash
pip3 install -r requirements.txt
```

### 3. Run Setup

```bash
chmod +x setup.sh
./setup.sh
```

Select from menu:
- `1` - Generate synthetic data
- `2` - Upload to S3
- `3` - Setup S3 integration
- `4` - Ingest into ClickHouse
- `5` - Run benchmarks
- `6` - Complete workflow (all steps)

## Manual Step-by-Step Execution

### Phase 1: Data Generation

Generate realistic synthetic data with device360 patterns:

```bash
export DATA_OUTPUT_DIR=./data
export TARGET_SIZE_GB=30  # Start small for testing
export NUM_DEVICES=1000000
export NUM_RECORDS=5000000

python3 scripts/generate_data.py
```

**Data Characteristics:**
- Power-law distribution (1% devices → 50% traffic)
- 30-day time range
- Bot and legitimate user patterns
- High-cardinality device IDs, apps, IPs, locations

**Output:** `./data/device360_*.json.gz`

### Phase 2: S3 Upload

Upload generated files to S3:

```bash
python3 scripts/upload_to_s3.py
```

**Features:**
- Parallel upload (4 workers default)
- Progress tracking
- Upload speed monitoring

### Phase 3: S3 Integration Setup

Configure IAM role for ClickHouse Cloud:

```bash
python3 scripts/setup_s3_integration.py
```

**Steps:**
1. Creates IAM role for ClickHouse
2. Attaches S3 read policy
3. Outputs role ARN for ClickHouse configuration

**Manual alternative:** Follow [ClickHouse S3 integration docs](https://clickhouse.com/docs/en/integrations/s3)

### Phase 4: ClickHouse Ingestion

Create schema and load data:

```bash
python3 scripts/ingest_from_s3.py
```

**What it does:**
1. Creates `device360` database
2. Creates `ad_requests` table with device_id-first ordering
3. Creates materialized views for aggregations
4. Loads data from S3 using `s3()` table function
5. Tracks ingestion rate and performance

**Key Design Decision:**
```sql
ORDER BY (device_id, event_date, event_ts)
```
Device ID comes FIRST for sub-second point lookups.

### Phase 5: Run Benchmarks

Execute comprehensive query suite:

```bash
python3 scripts/run_benchmarks.py
```

**Query Categories:**

1. **Device Journey Analysis** (`queries/01_device_journey_queries.sql`)
   - Single device lookups (target: <100ms)
   - Journey timelines with time gaps
   - Session detection (30-min inactivity)
   - Cross-app funnels
   - Location journey and impossible travel

2. **Aggregation Queries** (`queries/02_aggregation_queries.sql`)
   - Daily device request counts
   - Frequency distributions
   - High-cardinality GROUP BY operations
   - Approximate vs exact cardinality

3. **Bot Detection** (`queries/03_bot_detection_queries.sql`)
   - Multi-signal bot scoring
   - IP anomaly detection
   - Temporal pattern analysis
   - Impossible travel detection
   - 24/7 activity patterns

4. **Materialized Views** (`queries/04_materialized_view_queries.sql`)
   - Pre-aggregated vs real-time comparison
   - Device profiles
   - Daily summaries
   - Bot candidates

**Output:** `./results/benchmark_results_TIMESTAMP.json`

## Performance Targets

Based on test plan requirements:

| Query Pattern | Target | BigQuery Baseline | Expected Improvement |
|---------------|--------|-------------------|---------------------|
| Single device lookup | < 100ms | 10-30s | 100-300x |
| Device journey timeline | < 500ms | 30-60s | 60-120x |
| Session detection | < 1s | 1-2min | 60-120x |
| Daily device GROUP BY | < 1s | 30-60s | 30-60x |
| Bot detection | < 3s | 1-3min | 20-60x |

## Scaling Tests

To test ingestion performance at scale:

### Test 1: Small Scale (10GB)
```bash
export TARGET_SIZE_GB=10
export NUM_DEVICES=1000000
export NUM_RECORDS=17000000
./setup.sh
```

### Test 2: Medium Scale (50GB)
```bash
export TARGET_SIZE_GB=50
export NUM_DEVICES=10000000
export NUM_RECORDS=85000000
./setup.sh
```

### Test 3: Full Scale (300GB)
```bash
export TARGET_SIZE_GB=300
export NUM_DEVICES=100000000
export NUM_RECORDS=500000000
./setup.sh
```

Monitor ingestion rate to assess parallel scalability.

## Project Structure

```
device-360/
├── .env.template              # Environment configuration template
├── README.md                  # This file
├── requirements.txt           # Python dependencies
├── setup.sh                   # Main automation script
├── device360-test-plan.md     # Detailed test plan document
├── scripts/
│   ├── generate_data.py       # Synthetic data generator
│   ├── upload_to_s3.py        # S3 upload with progress tracking
│   ├── setup_s3_integration.py # IAM role setup
│   ├── ingest_from_s3.py      # ClickHouse data ingestion
│   └── run_benchmarks.py      # Query benchmark runner
├── sql/
│   ├── 01_create_database.sql
│   ├── 02_create_main_table.sql
│   └── 03_create_materialized_views.sql
├── queries/
│   ├── 01_device_journey_queries.sql
│   ├── 02_aggregation_queries.sql
│   ├── 03_bot_detection_queries.sql
│   └── 04_materialized_view_queries.sql
├── data/                      # Generated data files (gitignored)
├── logs/                      # Execution logs
└── results/                   # Benchmark results (JSON)
```

## Key Features

### 1. Realistic Data Distribution

- **Power-law device distribution:**
  - 1% heavy users (bots) → 50% traffic
  - 10% regular users → 30% traffic
  - 89% light users → 20% traffic

- **Bot characteristics:**
  - High fraud scores (60-100)
  - Multiple IPs and countries
  - Consistent request intervals
  - 24/7 activity patterns

### 2. Optimized Schema Design

```sql
-- Main table with device-first ordering
CREATE TABLE device360.ad_requests (
    event_ts DateTime,
    event_date Date,
    device_id String,  -- PRIMARY KEY (first in ORDER BY)
    ...
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (device_id, event_date, event_ts);
```

This enables:
- Millisecond device lookups
- Efficient date-range filtering within device
- Optimal for Device360 query patterns

### 3. Materialized Views

Pre-aggregated views for common queries:
- **device_profiles**: Lifetime statistics per device
- **device_daily_stats**: Daily aggregates
- **bot_candidates**: High-frequency devices
- **hourly_app_stats**: App performance metrics
- **geo_stats**: Geographic distributions

### 4. Comprehensive Query Suite

40+ queries covering:
- Point lookups and scans
- Window functions (lag, lead, session detection)
- Geographic calculations (geoDistance)
- Temporal analysis
- High-cardinality GROUP BY
- Bot detection algorithms

## Monitoring & Results

### During Ingestion

Monitor:
- Rows/second ingestion rate
- Network throughput
- Memory usage
- Disk I/O

Expected rates:
- Small instance: 100K-500K rows/sec
- Medium instance: 500K-2M rows/sec
- Large instance: 2M-5M rows/sec

### Query Performance

Results include:
- Execution time (ms)
- Rows scanned vs returned
- Memory usage
- Cache hit rates

Compare against targets in test plan.

## Troubleshooting

### Data Generation Slow

```bash
# Generate smaller dataset for testing
export TARGET_SIZE_GB=10
export NUM_RECORDS=17000000
```

### S3 Upload Fails

```bash
# Check AWS credentials
aws s3 ls s3://$S3_BUCKET_NAME/

# Reduce parallel workers
export S3_UPLOAD_WORKERS=2
```

### ClickHouse Connection Issues

```bash
# Test connection
clickhouse-client --host $CLICKHOUSE_HOST \
  --user $CLICKHOUSE_USER \
  --password $CLICKHOUSE_PASSWORD \
  --secure \
  --query "SELECT version()"
```

### Slow Query Performance

1. Check data distribution:
```sql
SELECT count(), uniq(device_id)
FROM device360.ad_requests;
```

2. Verify ORDER BY key:
```sql
SELECT partition, name, rows, marks_size
FROM system.parts
WHERE database = 'device360' AND table = 'ad_requests';
```

3. Check for cold queries (first run slower due to cache)

## Advanced Configuration

### Adjust Data Volume

Edit in `.env` or export before running:

```bash
# Small test (1GB)
export NUM_RECORDS=1700000
export NUM_DEVICES=100000

# Medium (50GB)
export NUM_RECORDS=85000000
export NUM_DEVICES=10000000

# Large (300GB)
export NUM_RECORDS=500000000
export NUM_DEVICES=100000000
```

### Parallel Ingestion

For faster ingestion with multiple ClickHouse nodes:

1. Split S3 files into batches
2. Run multiple `ingest_from_s3.py` instances
3. Use different file patterns per instance

### Custom Queries

Add your own queries to `queries/` directory:

```sql
-- queries/05_custom_queries.sql
SELECT ...
FROM device360.ad_requests
WHERE ...;
```

Run with:
```bash
python3 scripts/run_benchmarks.py
```

## Cost Estimation

### AWS S3 Costs (us-east-1)

- Storage: 300GB × $0.023/GB/month = $6.90/month
- PUT requests: ~500 files × $0.005/1000 = $0.003
- GET requests: ~500 files × $0.0004/1000 = $0.0002

**Total:** ~$7/month

### ClickHouse Cloud Costs

Depends on instance size and usage:
- Development: $0.15-0.30/hour
- Production: $0.60-2.00/hour

For 300GB data, recommend:
- 16GB RAM minimum
- 100GB disk
- Vertical autoscaling enabled

## References

- [Test Plan Document](./device360-test-plan.md)
- [ClickHouse MergeTree Documentation](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- [ClickHouse S3 Integration](https://clickhouse.com/docs/en/integrations/s3)
- [Query Optimization Guide](https://clickhouse.com/docs/en/guides/improving-query-performance)

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review logs in `./logs/` directory
3. Examine query results in `./results/`
4. Consult test plan document for expected behavior

## License

This is a proof-of-concept framework for testing purposes.
