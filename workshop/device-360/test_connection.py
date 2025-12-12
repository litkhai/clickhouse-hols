#!/usr/bin/env python3
import os
import sys
import clickhouse_connect

# Load .env file manually
def load_env():
    env_file = '.env'
    if not os.path.exists(env_file):
        print(f"ERROR: {env_file} not found")
        sys.exit(1)

    with open(env_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value

# Load environment
load_env()

host = os.getenv('CLICKHOUSE_HOST')
port = int(os.getenv('CLICKHOUSE_PORT', '8443'))
user = os.getenv('CLICKHOUSE_USER', 'default')
password = os.getenv('CLICKHOUSE_PASSWORD')

print(f"Connecting to {host}:{port} as {user}...")

try:
    client = clickhouse_connect.get_client(
        host=host,
        port=port,
        user=user,
        password=password,
        secure=True
    )

    result = client.query('SELECT version()')
    version = result.result_rows[0][0]
    print(f"✓ ClickHouse version: {version}")

    # Test database query
    result = client.query('SHOW DATABASES')
    databases = [row[0] for row in result.result_rows]
    print(f"✓ Available databases: {', '.join(databases)}")

    print("\n✓ Connection test successful!")

except Exception as e:
    print(f"✗ Connection failed: {e}")
    import traceback
    traceback.print_exc()
