# ClickHouse MCP Server

Python-based MCP (Model Context Protocol) server for ClickHouse database integration.

## Quick Start

1. Create environment file:
```bash
cp .env.example .env
# Edit .env with your ClickHouse connection details
```

2. Build and start the server:
```bash
docker-compose up -d --build
```

3. Check status:
```bash
docker-compose ps
docker-compose logs -f
```

4. Test health endpoint:
```bash
curl http://localhost:3001/health
```

## Configuration

Environment variables in `.env` file:

- `CLICKHOUSE_HOST`: ClickHouse server host (default: `clickhouse-latest` for local Docker setup)
- `CLICKHOUSE_PORT`: ClickHouse HTTP port (default: 8123)
- `CLICKHOUSE_USER`: Database user (default: default)
- `CLICKHOUSE_PASSWORD`: User password (default: empty)
- `CLICKHOUSE_DATABASE`: Default database (default: default)
- `CLICKHOUSE_SECURE`: Use HTTPS (default: false)

**Note**: The MCP server connects to the local ClickHouse Docker container (`clickhouse-latest`) via the `clickhouse-network`. Make sure the ClickHouse container is running before starting the MCP server.

## Usage with LibreChat

This MCP server can be integrated with LibreChat to provide ClickHouse query capabilities to AI assistants.

1. Ensure this server is running on port 3001
2. Configure LibreChat to connect to `http://mcp-clickhouse-server:3001`
3. LibreChat will be able to query ClickHouse through the MCP protocol

## Tools Available

- **query**: Execute SELECT queries
- **list_databases**: List all databases
- **list_tables**: List tables in a database
- **describe_table**: Get table schema
- **execute**: Run DDL/DML statements (with safety checks)

## Stopping

```bash
docker-compose down
```

## Troubleshooting

### Container keeps restarting
Check logs:
```bash
docker-compose logs mcp-clickhouse
```

### Can't connect to ClickHouse
- Verify ClickHouse is running: `docker ps | grep clickhouse`
- Check ClickHouse port: `curl http://localhost:8123/ping`
- Verify connection settings in `.env`

### Health check failing
Wait 10-15 seconds after startup for the server to initialize.
