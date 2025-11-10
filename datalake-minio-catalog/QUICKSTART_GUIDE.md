# Quick Start Guide

Get your data lake up and running in 5 minutes!

## One-Command Setup

```bash
./quickstart.sh
```

This single command will:
- Install all Python dependencies
- Generate sample data
- Start all Docker services
- Register data with the catalog

## Manual Setup (Step-by-Step)

### Step 1: Configure
```bash
./setup.sh --configure
```
Choose:
- MinIO storage size (default: 20GB)
- Catalog type: Nessie, Hive, or Iceberg REST

### Step 2: Generate Sample Data
```bash
pip install pandas pyarrow
python3 generate_parquet.py
```

### Step 3: Start Services
```bash
./setup.sh --start
```

### Step 4: Register Data
```bash
pip install minio pyiceberg
python3 register_data.py
```

## Access Your Data Lake

After setup completes, open these URLs:

| Service | URL | Credentials |
|---------|-----|-------------|
| MinIO Console | http://localhost:9001 | admin / password123 |
| Jupyter Notebook | http://localhost:8888 | No password |
| Nessie UI | http://localhost:19120 | N/A |

## What's Included

### Sample Data
- **customers.json**: 10 customer records
- **orders.parquet**: 100 order records

### Jupyter Notebooks
1. **01_minio_connection.ipynb** - Connect to MinIO, read data
2. **02_iceberg_nessie.ipynb** - Query Iceberg tables with Nessie
3. **03_clickhouse_integration.ipynb** - Connect ClickHouse to data lake

## Common Commands

```bash
# Check service status
./setup.sh --status

# Show all endpoints
./setup.sh --endpoints

# Stop services
./setup.sh --stop

# Restart services
./setup.sh --restart

# Clean everything (removes all data)
./setup.sh --clean
```

## First Steps After Setup

### 1. Explore MinIO Console
- Open http://localhost:9001
- Login with admin / password123
- Browse the `warehouse` bucket
- View your data files

### 2. Try Jupyter Notebooks
- Open http://localhost:8888
- Navigate to `work/` folder
- Open `01_minio_connection.ipynb`
- Run all cells to see data in action

### 3. Query Data with Python

```python
from minio import Minio

client = Minio(
    "localhost:9000",
    access_key="admin",
    secret_key="password123",
    secure=False
)

# List files
objects = client.list_objects("warehouse", recursive=True)
for obj in objects:
    print(obj.object_name)
```

## Troubleshooting

### Services won't start
```bash
# Check Docker is running
docker ps

# Check logs
docker logs minio
docker logs nessie
```

### Can't connect to MinIO
```bash
# Test connection
curl http://localhost:9000/minio/health/live

# Check if port is in use
lsof -i :9000
```

### Port conflicts
Edit [config.env](config.env) and change the ports, then restart:
```bash
./setup.sh --restart
```

## Next Steps

1. Read the full [README.md](README.md) for detailed documentation
2. Explore the Jupyter notebooks
3. Try connecting ClickHouse (see notebook 03)
4. Experiment with different catalog types

## Architecture Overview

```
┌─────────────────────────────────────────┐
│                                         │
│  ┌──────────┐      ┌────────────────┐  │
│  │  MinIO   │◄────►│     Nessie     │  │
│  │ Storage  │      │    Catalog     │  │
│  └──────────┘      └────────────────┘  │
│       ▲                     ▲           │
│       │                     │           │
│  ┌────┴─────┐      ┌───────┴──────┐   │
│  │ Jupyter  │      │  ClickHouse  │   │
│  │          │      │  (External)  │   │
│  └──────────┘      └──────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

## Support

- Check [README.md](README.md) for full documentation
- Review [notebooks/](notebooks/) for examples
- Check Docker logs for errors

## Clean Up

When done experimenting:

```bash
# Stop services (keep data)
./setup.sh --stop

# Remove everything (including data)
./setup.sh --clean
```

---

**Ready to start?** Run `./quickstart.sh` and you'll be up in minutes!
