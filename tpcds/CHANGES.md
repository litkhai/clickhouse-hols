# TPC-DS Structure Changes

## Summary of Changes

This document describes the reorganization of the TPC-DS benchmark directory structure.

## What Changed

### 1. New Setup Script: `00-set.sh`

Created a parameter-driven setup script that generates `config.sh` dynamically.

**Features:**
- Interactive mode with prompts
- Command-line parameter mode
- Docker mode for containerized environments
- Connection testing before generating config
- Comprehensive help and examples

**Usage examples:**
```bash
# Interactive mode
./00-set.sh --interactive

# Command-line mode
./00-set.sh --host localhost --port 9000 --user default --database tpcds

# Docker mode
./00-set.sh --docker

# Full parameterization
./00-set.sh \
  -h myserver.com \
  -p 9000 \
  -u myuser \
  -P mypassword \
  -d tpcds_prod \
  -s 100 \
  -j 16
```

### 2. SQL Files Reorganization

**Before:**
```
tpcds/
├── clickhouse-tpcds-ddl.sql
├── clickhouse-tpcds-load.sql
└── ...
```

**After:**
```
tpcds/
├── sql/
│   ├── clickhouse-tpcds-ddl.sql
│   └── clickhouse-tpcds-load.sql
└── ...
```

All SQL files are now organized in the `sql/` subdirectory for better structure.

### 3. Updated Scripts

All benchmark scripts have been updated to:
- Reference the new `sql/` subdirectory for DDL and load files
- Point users to `./00-set.sh` instead of manually editing config files
- Maintain backward compatibility with existing workflows

**Updated scripts:**
- `01-create-schema.sh` - References `sql/clickhouse-tpcds-ddl.sql`
- `03-load-data.sh` - References `sql/clickhouse-tpcds-load.sql`
- `02-generate-data.sh` - Updated error messages
- `04-run-queries-sequential.sh` - Updated error messages
- `05-run-queries-parallel.sh` - Updated error messages
- `run-all.sh` - Updated error messages

### 4. Updated Documentation

**Files updated:**
- `README.md` - Updated Quick Start, Directory Structure, and Configuration sections
- `QUICKSTART.md` - Updated setup instructions to use `00-set.sh`

## Directory Structure

```
tpcds/
├── 00-set.sh                          # NEW: Setup script (generates config.sh)
├── 01-create-schema.sh                # Schema creation
├── 02-generate-data.sh                # Data generation
├── 03-load-data.sh                    # Data loading
├── 04-run-queries-sequential.sh       # Sequential query execution
├── 05-run-queries-parallel.sh         # Parallel query execution
├── run-all.sh                         # Complete workflow runner
├── config.sh                           # Auto-generated configuration
├── config.sh.example                   # Example configuration (for reference)
├── README.md                          # Main documentation
├── QUICKSTART.md                      # Quick start guide
├── CHANGES.md                         # This file
├── .gitignore                         # Git ignore rules
├── sql/                               # NEW: SQL files directory
│   ├── clickhouse-tpcds-ddl.sql      # Schema definitions
│   └── clickhouse-tpcds-load.sql     # Data loading from S3
├── queries/                           # TPC-DS query templates
│   └── README.md
├── results/                           # Query execution results
│   ├── sequential/
│   └── parallel/
├── logs/                              # Execution logs
└── data/                              # Generated data files (optional)
```

## Migration Guide

### For Existing Users

If you already have a working `config.sh`:

**Option 1: Keep your existing config**
- Your existing `config.sh` will continue to work
- No changes needed

**Option 2: Regenerate with new setup script**
```bash
# Backup your current config
cp config.sh config.sh.backup

# Generate new config with 00-set.sh
./00-set.sh --host <your_host> --port <your_port> --user <your_user> ...

# Compare and verify
diff config.sh.backup config.sh
```

### For New Users

Simply run the setup script:
```bash
./00-set.sh --interactive
```

## Benefits

1. **Easier Setup**: No need to manually edit config files
2. **Better Organization**: SQL files separated into subdirectory
3. **Connection Testing**: Setup script verifies connection before proceeding
4. **Flexibility**: Support for interactive, CLI, and Docker modes
5. **Documentation**: Clearer instructions for getting started
6. **Maintainability**: Easier to manage and update configurations

## Backward Compatibility

- Existing `config.sh` files continue to work
- `config.sh.example` is preserved for reference
- All scripts maintain their existing functionality
- No breaking changes to the workflow

## Examples

### Quick Start (New Users)

```bash
# 1. Setup (generates config.sh)
./00-set.sh --interactive

# 2. Run benchmark
./run-all.sh
```

### Manual Setup (Power Users)

```bash
# 1. Generate config with specific parameters
./00-set.sh \
  --host 10.0.1.100 \
  --port 9000 \
  --user benchmark_user \
  --password secret123 \
  --database tpcds_100gb \
  --scale-factor 100 \
  --parallel 16

# 2. Create schema
./01-create-schema.sh

# 3. Load data
./03-load-data.sh --source s3

# 4. Run queries
./04-run-queries-sequential.sh --warmup --iterations 3
./05-run-queries-parallel.sh --parallel 16 --iterations 10
```

### Docker Environment

```bash
# Setup for Docker container
./00-set.sh --docker

# Rest of workflow is the same
./run-all.sh
```

## Notes

- The `config.sh.example` file remains as a reference
- Git will ignore the generated `config.sh` to avoid committing credentials
- All helper functions in config remain unchanged
- SQL files are functionally identical, just moved to subdirectory
