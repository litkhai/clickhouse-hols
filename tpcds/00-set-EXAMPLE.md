# Enhanced 00-set.sh - Interactive Example

This document shows what the enhanced interactive mode looks like.

## What's New

✅ **Each parameter shows:**
- Current value (from existing config or default)
- Available options with descriptions
- Real-world examples
- Validation hints and recommendations
- System-aware suggestions (e.g., CPU count detection)

✅ **Better UX:**
- Parameter numbering (1/8, 2/8, etc.)
- Color-coded display
- Clear choice presentation
- Confirmation for changes

## Example Interactive Session

```
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║           TPC-DS Benchmark Configuration Setup                   ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

✓ Found existing config.sh

Interactive Configuration Mode
Configure each parameter step-by-step with guidance and examples.

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
✓ Confirmed: my-clickhouse.internal

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
✓ Keeping: 9000

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
✓ Keeping: 8123

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
✓ Keeping: default

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
✓ Keeping: tpcds

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
✓ Confirmed: 10

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
✓ Confirmed: 8

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

## Key Features Demonstrated

### 1. **Current Value Display**
Every parameter shows its current value prominently, making it easy to see what you already have configured.

### 2. **Available Options**
Each parameter lists all common/valid options with descriptions, helping users understand their choices.

### 3. **Real-World Examples**
Practical examples for each parameter help users understand typical use cases.

### 4. **Validation Hints**
Smart hints like "System CPUs detected: 10" help users make informed decisions.

### 5. **Easy Keep/Change Flow**
- Press Enter → Keep current value
- Type new value → Confirm before applying
- Any mistakes → Easy to retry

### 6. **Secure Password Handling**
- Clear warning that passwords aren't stored
- Instructions on how to set at runtime
- Double-entry confirmation
- Used only for connection testing

### 7. **Visual Progress**
- Parameter numbering (1/8, 2/8, etc.)
- Color coding for different types of information
- Clear section separators

### 8. **Smart Defaults**
- Detects system resources (CPU count)
- Reads existing configuration
- Provides context-aware recommendations

## Comparison: Before vs After

### Before
```
Enter ClickHouse host [localhost]:
```

### After
```
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

Your choice:
```

Much more informative and user-friendly!
