/**
 * ClickHouse MCP (Model Context Protocol) Server
 * Provides ClickHouse database access to LibreChat via MCP
 */

const express = require('express');
const http = require('http');

const app = express();
app.use(express.json());

// Configuration from environment variables
const config = {
  clickhouse: {
    host: process.env.CLICKHOUSE_HOST || 'localhost',
    port: parseInt(process.env.CLICKHOUSE_PORT || '8123'),
    user: process.env.CLICKHOUSE_USER || 'default',
    password: process.env.CLICKHOUSE_PASSWORD || '',
    database: process.env.CLICKHOUSE_DATABASE || 'default',
  },
  server: {
    port: parseInt(process.env.PORT || '3001'),
  },
};

// Simple ClickHouse HTTP client
class ClickHouseClient {
  constructor(config) {
    this.config = config;
  }

  async query(sql, format = 'JSONCompact') {
    const url = `http://${this.config.host}:${this.config.port}/?database=${this.config.database}&default_format=${format}`;

    const auth = Buffer.from(`${this.config.user}:${this.config.password}`).toString('base64');

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${auth}`,
          'Content-Type': 'text/plain',
        },
        body: sql,
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`ClickHouse error: ${errorText}`);
      }

      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Query error:', error);
      throw error;
    }
  }

  async execute(sql) {
    const url = `http://${this.config.host}:${this.config.port}/?database=${this.config.database}`;

    const auth = Buffer.from(`${this.config.user}:${this.config.password}`).toString('base64');

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${auth}`,
          'Content-Type': 'text/plain',
        },
        body: sql,
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`ClickHouse error: ${errorText}`);
      }

      return await response.text();
    } catch (error) {
      console.error('Execute error:', error);
      throw error;
    }
  }
}

const clickhouse = new ClickHouseClient(config.clickhouse);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'clickhouse-mcp-server' });
});

// MCP endpoints

// List available tools
app.get('/api/tools', (req, res) => {
  res.json({
    tools: [
      {
        name: 'query',
        description: 'Execute a SELECT query on ClickHouse',
        parameters: {
          sql: { type: 'string', description: 'SQL SELECT query to execute' },
        },
      },
      {
        name: 'execute',
        description: 'Execute a DDL/DML statement on ClickHouse',
        parameters: {
          sql: { type: 'string', description: 'SQL statement to execute' },
        },
      },
      {
        name: 'list_tables',
        description: 'List all tables in the current database',
        parameters: {},
      },
      {
        name: 'describe_table',
        description: 'Get the schema of a specific table',
        parameters: {
          table: { type: 'string', description: 'Table name to describe' },
        },
      },
      {
        name: 'get_databases',
        description: 'List all databases',
        parameters: {},
      },
    ],
  });
});

// Execute tool
app.post('/api/tools/execute', async (req, res) => {
  const { tool, parameters } = req.body;

  try {
    let result;

    switch (tool) {
      case 'query':
        result = await clickhouse.query(parameters.sql);
        break;

      case 'execute':
        result = await clickhouse.execute(parameters.sql);
        break;

      case 'list_tables':
        result = await clickhouse.query(
          `SELECT name, engine, total_rows, total_bytes
           FROM system.tables
           WHERE database = '${config.clickhouse.database}'
           ORDER BY name`
        );
        break;

      case 'describe_table':
        result = await clickhouse.query(
          `DESCRIBE TABLE ${parameters.table}`
        );
        break;

      case 'get_databases':
        result = await clickhouse.query(
          `SELECT name, engine, tables, total_rows, total_bytes
           FROM system.databases
           ORDER BY name`
        );
        break;

      default:
        return res.status(400).json({ error: 'Unknown tool' });
    }

    res.json({ result });
  } catch (error) {
    console.error('Tool execution error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Query endpoint (simplified)
app.post('/api/query', async (req, res) => {
  const { sql } = req.body;

  if (!sql) {
    return res.status(400).json({ error: 'SQL query is required' });
  }

  try {
    const result = await clickhouse.query(sql);
    res.json({ result });
  } catch (error) {
    console.error('Query error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Schema information endpoint
app.get('/api/schema', async (req, res) => {
  try {
    const tables = await clickhouse.query(
      `SELECT name, engine, total_rows, total_bytes
       FROM system.tables
       WHERE database = '${config.clickhouse.database}'
       ORDER BY name`
    );

    const schema = {
      database: config.clickhouse.database,
      tables: tables.data || [],
    };

    res.json(schema);
  } catch (error) {
    console.error('Schema error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Start server
const PORT = config.server.port;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`ClickHouse MCP Server running on port ${PORT}`);
  console.log(`Connected to ClickHouse: ${config.clickhouse.host}:${config.clickhouse.port}`);
  console.log(`Database: ${config.clickhouse.database}`);
});
