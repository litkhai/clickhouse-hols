# ClickHouse MCP Server Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install git (required for pip install from git)
RUN apt-get update && \
    apt-get install -y git && \
    rm -rf /var/lib/apt/lists/*

# Install the ClickHouse MCP server from GitHub
RUN pip install --no-cache-dir git+https://github.com/ClickHouse/mcp-clickhouse.git

# Expose port for HTTP/SSE transport
EXPOSE 3001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import http.client; conn = http.client.HTTPConnection('localhost', 3001); conn.request('GET', '/health'); r = conn.getresponse(); exit(0 if r.status == 200 else 1)"

# Run the MCP server with HTTP transport
CMD ["python", "-m", "mcp_clickhouse.main"]
