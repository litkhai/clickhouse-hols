#!/bin/bash

#################################################
# TPC-DS Schema Creation Script
# Creates all TPC-DS tables in ClickHouse
#################################################

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load configuration
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found. Please create it from config.sh.example"
    echo "  cp config.sh.example config.sh"
    exit 1
fi

# Initialize
initialize_directories
log "INFO" "Starting TPC-DS schema creation"

# Test connection
log "INFO" "Testing ClickHouse connection..."
if ! test_connection; then
    log "ERROR" "Failed to connect to ClickHouse"
    exit 1
fi

# Create database
log "INFO" "Creating database: $CLICKHOUSE_DATABASE"
execute_query "CREATE DATABASE IF NOT EXISTS $CLICKHOUSE_DATABASE" "default" || {
    log "ERROR" "Failed to create database"
    exit 1
}

# Check if DDL file exists
DDL_FILE="$SCRIPT_DIR/clickhouse-tpcds-ddl.sql"
if [ ! -f "$DDL_FILE" ]; then
    log "ERROR" "DDL file not found: $DDL_FILE"
    exit 1
fi

log "INFO" "Creating tables from: $DDL_FILE"

# Execute DDL file
if execute_sql_file "$DDL_FILE" "$CLICKHOUSE_DATABASE"; then
    log "INFO" "Schema created successfully"
else
    log "ERROR" "Failed to create schema"
    exit 1
fi

# Verify tables were created
log "INFO" "Verifying tables..."
TABLES=$(execute_query "SHOW TABLES FROM $CLICKHOUSE_DATABASE" "default")
TABLE_COUNT=$(echo "$TABLES" | wc -l)

echo ""
echo "========================================"
echo "Schema Creation Complete"
echo "========================================"
echo "Database: $CLICKHOUSE_DATABASE"
echo "Tables created: $TABLE_COUNT"
echo ""
echo "Tables:"
echo "$TABLES"
echo ""
echo "========================================"

# List tables with row counts
log "INFO" "Table details:"
echo ""
printf "%-30s %15s\n" "TABLE" "ROWS"
echo "--------------------------------------------------------"

for table in $TABLES; do
    if [ -n "$table" ]; then
        count=$(execute_query "SELECT count() FROM $CLICKHOUSE_DATABASE.$table" "default" 2>/dev/null || echo "0")
        printf "%-30s %'15d\n" "$table" "$count"
    fi
done

echo ""
log "INFO" "Schema creation completed successfully"

# Save table list for reference
TABLE_LIST_FILE="$LOG_DIR/tables_created.txt"
echo "$TABLES" > "$TABLE_LIST_FILE"
log "INFO" "Table list saved to: $TABLE_LIST_FILE"

exit 0
