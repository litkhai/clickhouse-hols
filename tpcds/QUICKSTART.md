# TPC-DS Quick Start Guide

Get up and running with TPC-DS benchmark on ClickHouse in minutes.

## Prerequisites

- ClickHouse server running (local or remote)
- `clickhouse-client` installed
- Bash shell

## Quick Setup (5 minutes with S3 data)

### 1. Configure Connection

Run the setup script to generate your configuration:

```bash
# Interactive mode (recommended)
./00-set.sh --interactive

# Or provide parameters directly
./00-set.sh --host localhost --port 9000 --user default --database tpcds

# For Docker environments
./00-set.sh --docker
```

The setup script will:
- Generate `config.sh` with your settings
- Test the connection to ClickHouse
- Verify all parameters are correct

### 2. Run Complete Benchmark

Use the all-in-one script:
```bash
./run-all.sh
```

This will:
- Create the TPC-DS schema (24 tables)
- Load data from S3 (~1GB dataset)
- Run queries sequentially
- Run queries in parallel

**Estimated time**: 10-15 minutes

## Step-by-Step Execution

If you prefer to run each step manually:

### Step 0: Setup Configuration (if not done)

```bash
./00-set.sh --interactive
```

### Step 1: Create Schema (30 seconds)

```bash
./01-create-schema.sh
```

Verifies connection and creates all TPC-DS tables.

### Step 2: Load Data (5-10 minutes)

**Option A: Load from S3 (faster)**
```bash
./03-load-data.sh --source s3
```

**Option B: Generate and load locally**
```bash
# Generate data (scale factor 1 = ~1GB)
./02-generate-data.sh --scale-factor 1

# Load generated data
./03-load-data.sh --source local
```

### Step 3: Add Query Files

Download TPC-DS queries and place them in the `queries/` directory:

```bash
# Query files should be named: query01.sql, query02.sql, etc.
ls queries/
# query01.sql
# query02.sql
# ...
```

See [queries/README.md](queries/README.md) for sources.

### Step 4: Run Sequential Queries

```bash
./04-run-queries-sequential.sh
```

Options:
```bash
# Run specific queries
./04-run-queries-sequential.sh --queries "query01,query05,query10"

# Run with multiple iterations
./04-run-queries-sequential.sh --iterations 3

# Run with warmup
./04-run-queries-sequential.sh --warmup --iterations 3
```

### Step 5: Run Parallel Queries

```bash
./05-run-queries-parallel.sh --parallel 4
```

Options:
```bash
# Run with more parallel streams
./05-run-queries-parallel.sh --parallel 8 --iterations 5

# Run TPC-DS power test
./05-run-queries-parallel.sh --power-test

# Run TPC-DS throughput test
./05-run-queries-parallel.sh --throughput-test --parallel 4
```

## Viewing Results

Results are saved in the `results/` directory:

```bash
# List all results
ls -lh results/sequential/
ls -lh results/parallel/

# View latest summary
cat results/sequential/summary_*.txt | tail -50
cat results/parallel/summary_*.txt | tail -50
```

## Common Use Cases

### Use Case 1: Quick Performance Check

```bash
./run-all.sh
```

### Use Case 2: Test Specific Queries

```bash
./04-run-queries-sequential.sh --queries "query01,query13,query42" --iterations 5
```

### Use Case 3: Benchmark Different Scale Factors

```bash
# 1GB dataset
./02-generate-data.sh --scale-factor 1
./03-load-data.sh --source local

# 10GB dataset
./02-generate-data.sh --scale-factor 10
./03-load-data.sh --source local
```

### Use Case 4: Parallel Performance Testing

```bash
# Test with different parallelism levels
for p in 2 4 8 16; do
    echo "Testing with $p parallel streams..."
    ./05-run-queries-parallel.sh --parallel $p --iterations 10
done
```

### Use Case 5: Standard TPC-DS Benchmark

```bash
# Power Test (single stream)
./05-run-queries-parallel.sh --power-test

# Throughput Test (multiple streams)
./05-run-queries-parallel.sh --throughput-test --parallel 4
```

## Troubleshooting

### Connection Failed

```bash
# Test connection manually
clickhouse-client --host localhost --port 9000 --query "SELECT version()"
```

### Missing Queries

```bash
# Check if queries directory has SQL files
ls -l queries/*.sql
```

If empty, download TPC-DS queries (see [queries/README.md](queries/README.md))

### Data Loading Errors

```bash
# Check disk space
df -h

# Check ClickHouse logs
tail -f /var/log/clickhouse-server/clickhouse-server.log
```

### Out of Memory

Edit `config.sh` and reduce parallel jobs:
```bash
export PARALLEL_JOBS=2
```

## Environment Variables

Override settings via environment variables:

```bash
# Use different database
CLICKHOUSE_DATABASE="tpcds_test" ./01-create-schema.sh

# Use different host
CLICKHOUSE_HOST="remote-server" ./run-all.sh

# Increase parallelism
PARALLEL_JOBS=8 ./05-run-queries-parallel.sh
```

## Performance Tips

1. **Warm up cache**: Use `--warmup` flag for consistent results
2. **Multiple iterations**: Run queries 3-5 times and average results
3. **Monitor resources**: Watch CPU, memory, and I/O during execution
4. **Optimize settings**: Tune ClickHouse settings for your hardware
5. **Use larger datasets**: Scale factor 10+ for realistic benchmarking

## Next Steps

- Customize queries for your use case
- Compare performance across different ClickHouse versions
- Test different hardware configurations
- Analyze query plans with EXPLAIN
- Optimize slow queries

## Resources

- [Full README](README.md)
- [TPC-DS Specification](http://www.tpc.org/tpcds/)
- [ClickHouse TPC-DS Guide](https://clickhouse.com/docs/en/getting-started/example-datasets/tpcds)
