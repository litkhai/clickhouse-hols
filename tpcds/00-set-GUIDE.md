# 00-set.sh - Complete Configuration Guide

## Table of Contents
1. [Overview](#overview)
2. [Key Features](#key-features)
3. [Interactive Example](#interactive-example)
4. [Usage Guide](#usage-guide)
5. [Security Best Practices](#security-best-practices)
6. [All Parameters Reference](#all-parameters-reference)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The `00-set.sh` script provides an intelligent, user-friendly way to configure your TPC-DS benchmark environment with proper security handling for sensitive information.

### What's New in the Enhanced Version

✅ **Each parameter shows:**
- Current value (from existing config or default)
- Available options with descriptions
- Real-world examples
- Validation hints and recommendations
- System-aware suggestions (e.g., CPU count detection)

✅ **Better UX:**
- Parameter numbering (1/8, 2/8, etc.)
- Color-coded display (Green, Yellow, Blue, Cyan, Red)
- Clear choice presentation
- Confirmation for changes
- No screen clearing in interactive mode (preserves context)

---

## Key Features

### 1. Interactive Mode with Existing Config Reading (Default)

When you run `./00-set.sh` without arguments, it will:
- ✅ Read your existing `config.sh` (if it exists)
- ✅ Show current value for each parameter
- ✅ Display all available options and examples
- ✅ Ask if you want to keep or replace each value
- ✅ Request confirmation for each new value
- ✅ **Never store passwords in config file**
- ✅ Allow final confirmation before saving

### 2. Secure Password Handling

**IMPORTANT:** Passwords are NEVER stored in `config.sh`

- Passwords are prompted during setup for connection testing only
- Config file uses environment variable placeholder: `${CLICKHOUSE_PASSWORD:-}`
- You must set password at runtime: `export CLICKHOUSE_PASSWORD='your-password'`
- This prevents accidental commits of sensitive credentials
- Clear security warnings displayed with instructions

### 3. Three Operating Modes

#### A. Interactive Mode (Default)
```bash
./00-set.sh
```
- Reads existing config
- Prompts for each parameter with options and examples
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

### 4. Visual Enhancements

- **Color Coding:**
  - 🟢 Green = current values, success
  - 🟡 Yellow = warnings, notes, user input
  - 🔵 Blue = informational text
  - 🔴 Red = sensitive information, errors
  - 🔵 Cyan = examples, options

- **Box Borders:** Clear visual separation for each parameter
- **Progress Indicator:** "Parameter 1/8" shows where you are
- **Emoji Icons:** 🐋 Docker, 🔌 Connection test, 📝 Saving, ✓ Success, ⚠ Warning

---

## Interactive Example

Here's what the complete interactive session looks like:

```
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║           TPC-DS Benchmark Configuration Setup                   ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

✓ Found existing config.sh

Interactive Configuration Mode
Configure each parameter step-by-step with guidance and examples.

For each parameter:
  • Current value and available options will be shown
  • Press Enter to keep current value
  • Type a new value to change it

Press Enter to start...

╔════════════════════════════════════════════════════════════════╗
║ Parameter 1/8: ClickHouse Server Host
╚════════════════════════════════════════════════════════════════╝

Current value: localhost

Available options:
  • localhost       - Local ClickHouse instance
  • 127.0.0.1       - Local via IP
  • clickhouse-server - Docker container name
  • 10.x.x.x        - Remote server IP
  • hostname.domain - Remote server hostname

Examples:
  localhost              (development)
  clickhouse.mycompany.com (production)
  10.0.1.100            (internal network)

Note: Use 'localhost' for local development, IP/hostname for remote

Options:
  [Enter]  Keep current value: localhost
  [New value]  Enter new value to replace current

Your choice: my-clickhouse.internal

New value entered: my-clickhouse.internal
Confirm this value? (Y/n): y
  ✓ Confirmed new value: my-clickhouse.internal

→ Host: my-clickhouse.internal

╔════════════════════════════════════════════════════════════════╗
║ Parameter 2/8: ClickHouse Native Protocol Port
╚════════════════════════════════════════════════════════════════╝

Current value: 9000

Available options:
  • 9000  - Default ClickHouse native protocol port
  • 9440  - Default secure native protocol port (TLS)

Examples:
  9000  (standard, most common)
  9440  (with TLS encryption)

Note: Port 9000 is standard for non-TLS connections

Options:
  [Enter]  Keep current value: 9000
  [New value]  Enter new value to replace current

Your choice: [Enter pressed]

  ✓ Keeping current value: 9000

→ Native Port: 9000

╔════════════════════════════════════════════════════════════════╗
║ Parameter 3/8: ClickHouse HTTP Interface Port
╚════════════════════════════════════════════════════════════════╝

Current value: 8123

Available options:
  • 8123  - Default HTTP interface port
  • 8443  - Default HTTPS interface port (TLS)

Examples:
  8123  (standard HTTP)
  8443  (HTTPS with TLS)

Note: HTTP port is used for web interface and some tools

Options:
  [Enter]  Keep current value: 8123
  [New value]  Enter new value to replace current

Your choice: [Enter pressed]

  ✓ Keeping current value: 8123

→ HTTP Port: 8123

╔════════════════════════════════════════════════════════════════╗
║ Parameter 4/8: ClickHouse Username
╚════════════════════════════════════════════════════════════════╝

Current value: default

Available options:
  • default  - Default ClickHouse user (no password by default)
  • admin    - Common admin user
  • readonly - Read-only user (if configured)
  • custom   - Your custom username

Examples:
  default       (standard user)
  benchmark_user (dedicated benchmark account)
  readonly      (for query-only access)

Note: Use 'default' for standard setup, or your custom user

Options:
  [Enter]  Keep current value: default
  [New value]  Enter new value to replace current

Your choice: [Enter pressed]

  ✓ Keeping current value: default

→ Username: default

╔════════════════════════════════════════════════════════════════╗
║ Parameter 5/8: ClickHouse Password
╚════════════════════════════════════════════════════════════════╝

⚠  SECURITY: Password will NOT be stored in config.sh
   Passwords must be set via environment variable at runtime:
   export CLICKHOUSE_PASSWORD='your-password'

For connection testing only:

Enter password (or press Enter to skip): [hidden input]
Confirm password: [hidden input]
✓ Password confirmed (for testing only)

→ Password: ***provided (for testing)***

╔════════════════════════════════════════════════════════════════╗
║ Parameter 6/8: Database Name
╚════════════════════════════════════════════════════════════════╝

Current value: tpcds

Available options:
  • tpcds         - Default TPC-DS database name
  • tpcds_dev     - Development environment
  • tpcds_prod    - Production environment
  • tpcds_100gb   - Database with specific scale
  • custom_name   - Your custom database name

Examples:
  tpcds           (standard)
  tpcds_test_sf10  (test with scale factor 10)
  benchmark_db     (custom name)

Note: Database will be created if it doesn't exist

Options:
  [Enter]  Keep current value: tpcds
  [New value]  Enter new value to replace current

Your choice: [Enter pressed]

  ✓ Keeping current value: tpcds

→ Database: tpcds

╔════════════════════════════════════════════════════════════════╗
║ Parameter 7/8: TPC-DS Scale Factor (Data Size)
╚════════════════════════════════════════════════════════════════╝

Current value: 1

Available options:
  • 1     ~1 GB    - Quick testing, CI/CD (minutes)
  • 10    ~10 GB   - Small benchmark (30min - 1hr)
  • 100   ~100 GB  - Medium benchmark (hours)
  • 1000  ~1 TB    - Large benchmark (many hours)
  • 10000 ~10 TB   - Enterprise benchmark (days)

Examples:
  1     (development and testing)
  10    (realistic small-scale benchmark)
  100   (production-like benchmark)

Note: Larger scale = more data = longer generation & load time

Options:
  [Enter]  Keep current value: 1
  [New value]  Enter new value to replace current

Your choice: 10

New value entered: 10
Confirm this value? (Y/n): y
  ✓ Confirmed new value: 10

→ Scale Factor: 10 (~10GB)

╔════════════════════════════════════════════════════════════════╗
║ Parameter 8/8: Number of Parallel Query Streams
╚════════════════════════════════════════════════════════════════╝

Current value: 4

Available options:
  • 1   - Sequential (slowest, lowest resource usage)
  • 2   - Light parallel
  • 4   - Moderate parallel (recommended for most systems)
  • 8   - Heavy parallel (8+ core systems)
  • 16  - Maximum parallel (16+ core systems)
  • 32  - Extreme parallel (high-end servers)

Examples:
  4   (laptop/desktop with 4-8 cores)
  8   (workstation with 8-16 cores)
  16  (server with 16+ cores)

Note: System CPUs detected: 10. Recommended: 50-100% of CPU count

Options:
  [Enter]  Keep current value: 4
  [New value]  Enter new value to replace current

Your choice: 8

New value entered: 8
Confirm this value? (Y/n): y
  ✓ Confirmed new value: 8

→ Parallel Jobs: 8

╔════════════════════════════════════════════════════════════════╗
║ Advanced: S3 Data Source
╚════════════════════════════════════════════════════════════════╝

Current S3 bucket: https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data

This is for loading pre-generated TPC-DS data from S3.
Default Tokyo bucket is usually fine for most users.

Change S3 bucket? (y/N): n
✓ Using default S3 bucket


╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║                Configuration Summary                             ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

Connection:
  Host:              my-clickhouse.internal
  Native Port:       9000
  HTTP Port:         8123
  User:              default
  Password:          ***NOT STORED IN CONFIG***
  Database:          tpcds

Benchmark Settings:
  Scale Factor:      10 (~10GB)
  Parallel Jobs:     8

Data Source:
  S3 Bucket:         https://tpcds-tokyo-bucket.s3.ap-northeast-1.amazonaws.com/data...

──────────────────────────────────────────────────────────────────

💾 Save this configuration? (Y/n): y

🔌 Testing ClickHouse connection...
✓ Connection successful!

📝 Generating config.sh...
✓ Configuration saved to: ./config.sh

╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║                    ✓ Setup Complete!                             ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

Next Steps:

  1. Set password:    export CLICKHOUSE_PASSWORD='your-password'
  2. Create schema:   ./01-create-schema.sh
  3. Load data:       ./03-load-data.sh --source s3
  4. Run queries:     ./04-run-queries-sequential.sh

  Or run everything: ./run-all.sh

```

---

## Usage Guide

### First-Time Setup

```bash
# Interactive setup (recommended)
./00-set.sh
```

### Updating Existing Configuration

```bash
# Run setup again - it reads your existing config
./00-set.sh

# You'll see your current values and can choose what to change
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

### Command-Line Options

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

---

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

### Setting Password at Runtime

#### Option 1: Environment Variable (Recommended)
```bash
export CLICKHOUSE_PASSWORD='your-password'
./01-create-schema.sh
```

#### Option 2: Inline for Single Command
```bash
CLICKHOUSE_PASSWORD='your-password' ./01-create-schema.sh
```

#### Option 3: Read from Secure File
```bash
export CLICKHOUSE_PASSWORD=$(cat ~/.clickhouse-password)
./run-all.sh
```

---

## All Parameters Reference

### Parameter 1: ClickHouse Host

**Options:**
- `localhost` - Local ClickHouse instance
- `127.0.0.1` - Local via IP
- `clickhouse-server` - Docker container name
- `10.x.x.x` - Remote server IP
- `hostname.domain` - Remote server hostname

**Examples:**
- `localhost` (development)
- `clickhouse.mycompany.com` (production)
- `10.0.1.100` (internal network)

**Note:** Use 'localhost' for local development, IP/hostname for remote

---

### Parameter 2: Native Port

**Options:**
- `9000` - Default ClickHouse native protocol port
- `9440` - Default secure native protocol port (TLS)

**Examples:**
- `9000` (standard, most common)
- `9440` (with TLS encryption)

**Note:** Port 9000 is standard for non-TLS connections

---

### Parameter 3: HTTP Port

**Options:**
- `8123` - Default HTTP interface port
- `8443` - Default HTTPS interface port (TLS)

**Examples:**
- `8123` (standard HTTP)
- `8443` (HTTPS with TLS)

**Note:** HTTP port is used for web interface and some tools

---

### Parameter 4: Username

**Options:**
- `default` - Default ClickHouse user (no password by default)
- `admin` - Common admin user
- `readonly` - Read-only user (if configured)
- `custom` - Your custom username

**Examples:**
- `default` (standard user)
- `benchmark_user` (dedicated benchmark account)
- `readonly` (for query-only access)

**Note:** Use 'default' for standard setup, or your custom user

---

### Parameter 5: Password

**Security:** NOT stored in config, prompted with confirmation, hidden input

**Runtime:** Must be set via `export CLICKHOUSE_PASSWORD='your-password'`

**Important:**
- ⚠️ Password will NOT be stored in config.sh
- Passwords must be set via environment variable at runtime
- For connection testing only during setup
- Double-entry confirmation required
- Input is hidden for security

---

### Parameter 6: Database Name

**Options:**
- `tpcds` - Default TPC-DS database name
- `tpcds_dev` - Development environment
- `tpcds_prod` - Production environment
- `tpcds_100gb` - Database with specific scale
- `custom_name` - Your custom database name

**Examples:**
- `tpcds` (standard)
- `tpcds_test_sf10` (test with scale factor 10)
- `benchmark_db` (custom name)

**Note:** Database will be created if it doesn't exist

---

### Parameter 7: Scale Factor

**Options:**
- `1` (~1GB) - Quick testing, CI/CD (minutes)
- `10` (~10GB) - Small benchmark (30min-1hr)
- `100` (~100GB) - Medium benchmark (hours)
- `1000` (~1TB) - Large benchmark (many hours)
- `10000` (~10TB) - Enterprise benchmark (days)

**Examples:**
- `1` (development and testing)
- `10` (realistic small-scale benchmark)
- `100` (production-like benchmark)

**Note:** Larger scale = more data = longer generation & load time

---

### Parameter 8: Parallel Jobs

**Options:**
- `1` - Sequential (slowest, lowest resource usage)
- `2` - Light parallel
- `4` - Moderate parallel (recommended for most systems)
- `8` - Heavy parallel (8+ core systems)
- `16` - Maximum parallel (16+ core systems)
- `32` - Extreme parallel (high-end servers)

**Examples:**
- `4` (laptop/desktop with 4-8 cores)
- `8` (workstation with 8-16 cores)
- `16` (server with 16+ cores)

**Smart Feature:** Auto-detects system CPU count

**Note:** System recommends 50-100% of CPU count

---

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

### "Your choice:" Appears Without Options

This issue has been fixed in the latest version. The problem was that output was being captured by command substitution. All display output now goes to stderr (`>&2`) so it's visible immediately.

---

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

---

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

---

## Summary

The enhanced `00-set.sh` script provides:

- 🔒 **Secure**: Passwords never stored in files
- 🔄 **Smart**: Reads and updates existing configuration
- ✅ **Verified**: Confirms each change before applying
- 🚀 **Flexible**: Interactive, CLI, and Docker modes
- 📝 **Clear**: Color-coded output with helpful messages
- 🎓 **Educational**: Options, examples, and hints for every parameter
- 👀 **Visible**: All information displayed before prompts (no output capture issues)
- 💡 **Intelligent**: System-aware (CPU detection) and context-aware

### Benefits

1. **No Guessing:** All options clearly listed for each parameter
2. **Context-Aware:** System detects CPU count, shows existing config
3. **Safe:** Confirmation step prevents mistakes
4. **Educational:** Examples and descriptions help understand each choice
5. **Secure:** Passwords never stored, clear security warnings
6. **Flexible:** Easy to keep current values or change specific ones
7. **Visual:** Color-coded, well-organized, progress indicator
8. **Professional:** Enterprise-grade configuration experience

Perfect for both first-time setup and ongoing configuration management!
