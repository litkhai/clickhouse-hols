# 00-set.sh - TPC-DS Configuration Setup Script

## Overview

The `00-set.sh` script provides an intelligent, user-friendly way to configure your TPC-DS benchmark environment with proper security handling for sensitive information.

## Key Features

### 1. **Interactive Mode with Existing Config Reading** (Default)

When you run `./00-set.sh` without arguments, it will:
- ✅ Read your existing `config.sh` (if it exists)
- ✅ Show current value for each parameter
- ✅ Ask if you want to keep or replace each value
- ✅ Request confirmation for each new value
- ✅ **Never store passwords in config file**
- ✅ Allow final confirmation before saving

### 2. **Secure Password Handling**

**IMPORTANT:** Passwords are NEVER stored in `config.sh`

- Passwords are prompted during setup for connection testing only
- Config file uses environment variable placeholder: `${CLICKHOUSE_PASSWORD:-}`
- You must set password at runtime: `export CLICKHOUSE_PASSWORD='your-password'`
- This prevents accidental commits of sensitive credentials

### 3. **Three Operating Modes**

#### A. Interactive Mode (Default)
```bash
./00-set.sh
```
- Reads existing config
- Prompts for each parameter
- Shows current values
- Confirms before saving

#### B. Non-Interactive Mode
```bash
./00-set.sh --non-interactive --host 10.0.1.100 --port 9000 --user admin
```
- Uses CLI arguments only
- No prompts
- Good for automation/scripts

#### C. Docker Mode
```bash
./00-set.sh --docker
```
- Pre-configured for Docker containers
- Sets host to `clickhouse-server`
- Uses standard container ports

## Usage Examples

### First-Time Setup

```bash
# Interactive setup (recommended)
./00-set.sh

# You'll see:
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Parameter: ClickHouse Host
# Current value: localhost
# Keep current? (Y/n): n
# Enter new value: my-server.com
# New value: my-server.com
# Confirm this value? (Y/n): y
# ✓ Confirmed
```

### Updating Existing Configuration

```bash
# Run setup again - it reads your existing config
./00-set.sh

# You'll see your current values and can choose what to change:
# Found existing config.sh
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Parameter: ClickHouse Host
# Current value: my-server.com  ← Your existing value
# Keep current? (Y/n): y
# ✓ Keeping current value
```

### Quick Non-Interactive Setup

```bash
./00-set.sh --non-interactive \
  --host production-db.example.com \
  --port 9000 \
  --user benchmark_user \
  --database tpcds_100gb \
  --scale-factor 100 \
  --parallel 16
```

### Docker Environment

```bash
./00-set.sh --docker
# Automatically sets:
# - host: clickhouse-server
# - port: 9000
# - user: default
# - database: tpcds
```

## Interactive Flow Walkthrough

### Example Session

```
╔═══════════════════════════════════════════╗
║  TPC-DS Configuration Setup               ║
╚═══════════════════════════════════════════╝

Found existing config.sh
Interactive Configuration Mode
Press Enter to keep current values, or enter new values.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Parameter: ClickHouse Host
Current value: localhost
Keep current? (Y/n): n
Enter new value: my-clickhouse.com
New value: my-clickhouse.com
Confirm this value? (Y/n): y
✓ Confirmed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Parameter: ClickHouse Native Port
Current value: 9000
Keep current? (Y/n):
✓ Keeping current value

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Parameter: ClickHouse Password
⚠ IMPORTANT: Password will NOT be stored in config.sh
You must provide it via environment variable at runtime:
  export CLICKHOUSE_PASSWORD='your-password'

Enter password for connection test (optional, press Enter to skip):
[password hidden]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Parameter: Database Name
Current value: tpcds
Keep current? (Y/n):
✓ Keeping current value

... (continues for all parameters)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Final Configuration Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Host:           my-clickhouse.com
Native Port:    9000
HTTP Port:      8123
User:           default
Password:       ***NOT STORED IN CONFIG***
Database:       tpcds
Scale Factor:   1
Parallel Jobs:  4
S3 Bucket:      https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Save this configuration? (Y/n): y

Testing ClickHouse connection...
✓ Connection successful!

✓ Configuration saved to: ./config.sh

╔═══════════════════════════════════════════╗
║  ✓ Setup Complete!                        ║
╚═══════════════════════════════════════════╝

Next steps:
  1. Set password:    export CLICKHOUSE_PASSWORD='your-password'
  2. Create schema:   ./01-create-schema.sh
  3. Load data:       ./03-load-data.sh --source s3
  4. Run queries:     ./04-run-queries-sequential.sh

Or run everything: ./run-all.sh
```

## Parameter Confirmation Logic

For each non-sensitive parameter:
1. Show current value (from existing config or default)
2. Ask: "Keep current? (Y/n)"
3. If "n":
   - Prompt for new value
   - Display new value
   - Ask: "Confirm this value? (Y/n)"
   - If "n": Keep current value
   - If "y": Use new value
4. If "Y" or Enter: Keep current value

For sensitive parameters (passwords):
- Always prompt (never show existing value)
- Hide input (`read -s`)
- Request confirmation
- Never store in config file

## Generated Config File

The generated `config.sh` will look like:

```bash
#!/bin/bash

#################################################
# TPC-DS Benchmark Configuration
# Auto-generated by 00-set.sh on 2025-11-08 17:30:00
#
# IMPORTANT: Password is NOT stored in this file
# Set password via environment variable:
#   export CLICKHOUSE_PASSWORD='your-password'
#################################################

# ClickHouse Connection Settings
export CLICKHOUSE_HOST="my-clickhouse.com"
export CLICKHOUSE_PORT="9000"
export CLICKHOUSE_HTTP_PORT="8123"
export CLICKHOUSE_USER="default"
export CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-}"  # Set via environment variable

# Database
export CLICKHOUSE_DATABASE="tpcds"

# TPC-DS Data Generation Settings
export SCALE_FACTOR="1"
export DATA_DIR="${DATA_DIR:-./data}"

# Query Execution Settings
export QUERIES_DIR="${QUERIES_DIR:-./queries}"
export RESULTS_DIR="${RESULTS_DIR:-./results}"
export PARALLEL_JOBS="4"
export QUERY_ITERATIONS="${QUERY_ITERATIONS:-1}"

# S3 Data Source
export S3_BUCKET="https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data"

# ... (helper functions follow)
```

## Security Best Practices

### ✅ DO:
- Use the interactive mode for initial setup
- Set password via environment variable: `export CLICKHOUSE_PASSWORD='secret'`
- Add `config.sh` to `.gitignore` (already done)
- Review the final configuration before confirming

### ❌ DON'T:
- Don't commit `config.sh` with credentials
- Don't pass passwords via command line arguments (visible in process list)
- Don't store passwords in plain text files

## Setting Password at Runtime

### Option 1: Environment Variable (Recommended)
```bash
export CLICKHOUSE_PASSWORD='your-password'
./01-create-schema.sh
```

### Option 2: Inline for Single Command
```bash
CLICKHOUSE_PASSWORD='your-password' ./01-create-schema.sh
```

### Option 3: Read from Secure File
```bash
export CLICKHOUSE_PASSWORD=$(cat ~/.clickhouse-password)
./run-all.sh
```

## Command-Line Options

| Option | Argument | Description | Default |
|--------|----------|-------------|---------|
| `-h`, `--host` | HOST | ClickHouse host | localhost |
| `-p`, `--port` | PORT | Native port | 9000 |
| `--http-port` | PORT | HTTP port | 8123 |
| `-u`, `--user` | USER | Username | default |
| `-P`, `--password` | PASSWORD | Password (not stored) | - |
| `-d`, `--database` | DATABASE | Database name | tpcds |
| `-s`, `--scale-factor` | N | Scale factor | 1 |
| `-j`, `--parallel` | N | Parallel jobs | 4 |
| `--s3-bucket` | URL | S3 bucket URL | Tokyo bucket |
| `--interactive` | - | Force interactive mode | - |
| `--non-interactive` | - | CLI args only | - |
| `--docker` | - | Docker settings | - |
| `--help` | - | Show help | - |

## Troubleshooting

### Config Not Found Error
If other scripts show "config.sh not found":
```bash
./00-set.sh  # Run setup first
```

### Connection Test Fails
1. Verify ClickHouse is running: `ps aux | grep clickhouse`
2. Check host/port: `telnet <host> <port>`
3. Test manually: `clickhouse-client --host <host> --port <port>`
4. Continue anyway if you want to set up config for later

### Password Not Working
Make sure you exported the password:
```bash
# Check if set
echo $CLICKHOUSE_PASSWORD

# Set if empty
export CLICKHOUSE_PASSWORD='your-password'
```

### Want to Start Fresh
```bash
# Backup current config
mv config.sh config.sh.backup

# Run setup again
./00-set.sh
```

## Advanced Usage

### Automation/CI/CD
```bash
# Non-interactive for automation
./00-set.sh --non-interactive \
  --host $CI_DB_HOST \
  --port $CI_DB_PORT \
  --user $CI_DB_USER \
  --database "tpcds_ci_${CI_BUILD_ID}"
```

### Multiple Environments
```bash
# Development
./00-set.sh --non-interactive --host dev-db.local --database tpcds_dev
cp config.sh config.dev.sh

# Production
./00-set.sh --non-interactive --host prod-db.com --database tpcds_prod
cp config.sh config.prod.sh

# Use specific config
source config.dev.sh && ./run-all.sh
```

## Summary

The enhanced `00-set.sh` script provides:
- 🔒 **Secure**: Passwords never stored in files
- 🔄 **Smart**: Reads and updates existing configuration
- ✅ **Verified**: Confirms each change before applying
- 🚀 **Flexible**: Interactive, CLI, and Docker modes
- 📝 **Clear**: Color-coded output with helpful messages

Perfect for both first-time setup and ongoing configuration management!
