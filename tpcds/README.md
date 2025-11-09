(This is under development)

# TPC-DS Benchmark for ClickHouse

This directory contains scripts and resources for running the TPC-DS benchmark on ClickHouse.

## Overview

TPC-DS (Transaction Processing Performance Council - Decision Support) is a decision support benchmark that models several generally applicable aspects of a decision support system, including queries and data maintenance. The benchmark provides a representative evaluation of performance as a general purpose decision support system.

## Prerequisites

- ClickHouse server (running locally or accessible via network)
- TPC-DS data generation toolkit (dsdgen)
- Bash shell environment
- `clickhouse-client` installed and accessible
- Sufficient disk space for data generation and loading

## Quick Start

```bash
# 1. Configure your environment (generates config.sh)
./00-set.sh --host localhost --port 9000 --user default

# Or use interactive mode
./00-set.sh --interactive

# 2. Create the schema
./01-create-schema.sh

# 3. Generate TPC-DS data (optional - can use pre-generated S3 data)
./02-generate-data.sh --scale-factor 1

# 4. Load data into ClickHouse
./03-load-data.sh

# 5. Run queries sequentially
./04-run-queries-sequential.sh

# 6. Run queries in parallel (for performance testing)
./05-run-queries-parallel.sh --parallel 4
```

## Directory Structure

```
tpcds/
├── README.md                           # This file
├── QUICKSTART.md                       # Quick start guide
├── 00-set.sh                          # Setup script (generates config.sh)
├── config.sh                           # Configuration file (auto-generated)
├── config.sh.example                   # Example configuration
├── 01-create-schema.sh                # Schema creation script
├── 02-generate-data.sh                # Data generation script (using tpcds-kit)
├── 03-load-data.sh                    # Data loading script
├── 04-run-queries-sequential.sh       # Sequential query execution
├── 05-run-queries-parallel.sh         # Parallel query execution
├── run-all.sh                         # Complete workflow runner
├── sql/                               # SQL files
│   ├── clickhouse-tpcds-ddl.sql      # Schema definitions
│   └── clickhouse-tpcds-load.sql     # Data loading from S3
├── queries/                           # TPC-DS query templates
│   ├── query01.sql
│   ├── query02.sql
│   └── ...
├── results/                           # Query execution results
│   ├── sequential/
│   └── parallel/
├── logs/                              # Execution logs
└── data/                              # Generated data files (optional)
```

## Configuration

Generate `config.sh` using the setup script with your ClickHouse connection details:

```bash
# Interactive mode (recommended for first-time setup)
./00-set.sh --interactive

# Command-line mode with parameters
./00-set.sh \
  --host localhost \
  --port 9000 \
  --user default \
  --password "" \
  --database tpcds \
  --scale-factor 1 \
  --parallel 4

# Docker mode (for containerized ClickHouse)
./00-set.sh --docker

# Show all options
./00-set.sh --help
```

Generated configuration includes:
- ClickHouse connection settings (host, port, user, password)
- Database name
- Scale factor for data generation
- Parallel execution settings
- Data directories and S3 bucket URLs

## Schema Setup

The TPC-DS schema consists of 24 tables:

**Dimension Tables:**
- call_center, catalog_page, customer, customer_address, customer_demographics
- date_dim, household_demographics, income_band, item, promotion
- reason, ship_mode, store, time_dim, warehouse, web_page, web_site

**Fact Tables:**
- catalog_sales, catalog_returns, inventory, store_sales
- store_returns, web_sales, web_returns

Run schema creation:
```bash
./01-create-schema.sh
```

## Data Generation

### Option 1: Generate Data Locally

Install TPC-DS toolkit (dsdgen):
```bash
git clone https://github.com/gregrahn/tpcds-kit.git
cd tpcds-kit/tools
make OS=LINUX
```

Generate data:
```bash
./02-generate-data.sh --scale-factor 1
```

Scale factors:
- 1 = ~1GB
- 10 = ~10GB
- 100 = ~100GB
- 1000 = ~1TB

### Option 2: Use Pre-generated Data from S3

The loading script supports loading pre-generated data from S3:
```bash
./03-load-data.sh --source s3
```

## Data Loading

Load data into ClickHouse:
```bash
./03-load-data.sh [--source local|s3]
```

Options:
- `--source local`: Load from locally generated data files (default: ./data)
- `--source s3`: Load from pre-generated S3 bucket (faster)

## Running Queries

### Sequential Execution

Run all queries one by one:
```bash
./04-run-queries-sequential.sh [OPTIONS]

Options:
  --queries PATTERN    Run specific queries (e.g., "query01,query05,query10")
  --iterations N       Run each query N times (default: 1)
  --output DIR        Output directory for results (default: ./results/sequential)
```

### Parallel Execution

Run queries in parallel for performance testing:
```bash
./05-run-queries-parallel.sh [OPTIONS]

Options:
  --parallel N        Number of parallel jobs (default: 4)
  --queries PATTERN   Run specific queries
  --iterations N      Run each query N times (default: 3)
  --output DIR       Output directory for results (default: ./results/parallel)
```

## Query Templates

TPC-DS includes 99 query templates covering various analytical patterns:
- Reporting queries
- Ad-hoc queries
- Iterative OLAP queries
- Data mining queries

Query parameters can be substituted using the query template engine.

## Results Analysis

Results are stored in the specified output directory with:
- Query execution times
- Row counts
- Resource usage statistics
- Performance metrics

Example result file format:
```
Query: query01.sql
Execution Time: 1.234s
Rows Returned: 100
Peak Memory: 256MB
```

## Performance Tips

1. **Optimize ClickHouse settings**:
   - Increase `max_threads` for parallel query execution
   - Adjust `max_memory_usage` based on available RAM
   - Enable `allow_suspicious_low_cardinality_types`

2. **Use appropriate scale factor**:
   - Start with scale factor 1 for testing
   - Use higher scale factors for realistic benchmarking

3. **Warm up the cache**:
   - Run queries once before measuring performance
   - Results may vary on first execution vs. cached execution

4. **Monitor system resources**:
   - CPU utilization
   - Memory usage
   - Disk I/O
   - Network throughput (if using remote storage)

## Troubleshooting

**Connection Issues:**
```bash
# Test connection
clickhouse-client --host $CLICKHOUSE_HOST --port $CLICKHOUSE_PORT --user $CLICKHOUSE_USER --password $CLICKHOUSE_PASSWORD --query "SELECT version()"
```

**Data Loading Failures:**
- Check disk space: `df -h`
- Verify data file permissions
- Check ClickHouse server logs

**Query Execution Errors:**
- Verify schema is created correctly
- Ensure data is loaded completely
- Check query syntax for ClickHouse compatibility

## References

- [TPC-DS Specification](http://www.tpc.org/tpcds/)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [TPC-DS Kit on GitHub](https://github.com/gregrahn/tpcds-kit)
- [ClickHouse TPC-DS Guide](https://clickhouse.com/docs/en/getting-started/example-datasets/tpcds)

## License

TPC-DS is a trademark of the Transaction Processing Performance Council (TPC). The benchmark specifications and tools are subject to TPC licensing terms.
