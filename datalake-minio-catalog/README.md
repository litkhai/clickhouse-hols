# Data Lake with MinIO and Catalog

A complete setup for running a local data lake environment with MinIO object storage and choice of data catalogs (Nessie, Hive Metastore, or Iceberg REST).

## Features

- **MinIO Object Storage**: S3-compatible object storage
- **Multiple Catalog Options**:
  - **Nessie** (Default): Git-like catalog with branching and versioning
  - **Hive Metastore**: Traditional, widely-supported catalog
  - **Iceberg REST**: Standard REST API catalog
- **Apache Iceberg**: Table format for huge analytic datasets
- **Jupyter Notebooks**: Interactive data exploration
- **Sample Data**: Pre-loaded JSON and Parquet files

## Prerequisites

- Docker and Docker Compose
- Python 3.8+ (for data generation scripts)
- 20GB+ disk space (configurable)

## Quick Start

### 1. Configure the Setup

```bash
./setup.sh --configure
```

This will prompt you to:
- Set MinIO storage size (default: 20GB)
- Choose data catalog: Nessie (1), Hive (2), or Iceberg REST (3)

### 2. Generate Sample Data

```bash
# Install Python dependencies
pip install pandas pyarrow

# Generate Parquet file
python3 generate_parquet.py
```

### 3. Start Services

```bash
./setup.sh --start
```

This will:
- Create necessary directories
- Start Docker containers
- Wait for services to be ready
- Display connection endpoints

### 4. Register Sample Data

```bash
# Install Python dependencies
pip install minio pyiceberg

# Upload and register data
python3 register_data.py
```

## Service Endpoints

After starting the services, you'll have access to:

### MinIO Object Storage
- **Console UI**: http://localhost:9001
- **API Endpoint**: http://localhost:9000
- **Credentials**:
  - Access Key: `admin`
  - Secret Key: `password123`

### Data Catalogs

#### Nessie (Default)
- **API**: http://localhost:19120/api/v2
- **UI**: http://localhost:19120
- **Features**: Git-like versioning, branching, time-travel

#### Hive Metastore
- **Thrift URI**: `thrift://localhost:9083`
- **PostgreSQL**: `localhost:5432`
  - Database: `metastore`
  - User: `hive`
  - Password: `hive`

#### Iceberg REST Catalog
- **API**: http://localhost:8181
- **Spec**: Standard Iceberg REST API

### Jupyter Notebook
- **URL**: http://localhost:8888
- **No password required**
- Pre-configured with sample notebooks

## Usage Commands

```bash
# Configure setup
./setup.sh --configure

# Start all services
./setup.sh --start

# Stop all services
./setup.sh --stop

# Restart all services
./setup.sh --restart

# Show service status
./setup.sh --status

# Show endpoints
./setup.sh --endpoints

# Clean up (remove all data)
./setup.sh --clean
```

## Directory Structure

```
datalake-minio-catalog/
├── config.env              # Configuration file
├── docker-compose.yml      # Docker services definition
├── setup.sh               # Main setup script
├── generate_parquet.py    # Generate sample Parquet data
├── register_data.py       # Register data with catalog
├── minio-storage/         # MinIO data (auto-created)
├── sample-data/           # Sample data files
│   ├── customers.json     # Sample JSON data
│   └── orders.parquet     # Sample Parquet data
└── notebooks/             # Jupyter notebooks
    ├── 01_minio_connection.ipynb
    └── 02_iceberg_nessie.ipynb
```

## Sample Data

### customers.json
JSON file with 10 customer records including:
- customer_id, name, email, age
- city, registration_date, lifetime_value

### orders.parquet
Parquet file with 100 order records including:
- order_id, customer_id, product_name
- quantity, unit_price, total_amount
- order_date, status

## Python Connection Examples

### MinIO Connection

```python
from minio import Minio

client = Minio(
    "localhost:9000",
    access_key="admin",
    secret_key="password123",
    secure=False
)

# List buckets
buckets = client.list_buckets()
for bucket in buckets:
    print(bucket.name)
```

### Iceberg with Nessie

```python
from pyiceberg.catalog import load_catalog

catalog = load_catalog(
    "nessie",
    **{
        "uri": "http://localhost:19120/api/v2",
        "warehouse": "s3://warehouse/",
        "s3.endpoint": "http://localhost:9000",
        "s3.access-key-id": "admin",
        "s3.secret-access-key": "password123",
        "s3.path-style-access": "true",
    }
)

# Load table
table = catalog.load_table("demo.orders")
df = table.scan().to_pandas()
```

### Using boto3 (S3-compatible)

```python
import boto3

s3 = boto3.client(
    's3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id='admin',
    aws_secret_access_key='password123'
)

# List objects
response = s3.list_objects_v2(Bucket='warehouse')
```

## ClickHouse Integration

### Using ClickHouse with MinIO

```sql
-- Create table with S3 engine
CREATE TABLE orders_from_s3
ENGINE = S3(
    'http://localhost:9000/warehouse/data/orders.parquet',
    'admin',
    'password123',
    'Parquet'
);

-- Query data
SELECT * FROM orders_from_s3 LIMIT 10;
```

### Using ClickHouse with Iceberg

```sql
-- Enable Iceberg integration (requires ClickHouse 23.3+)
SET allow_experimental_object_type = 1;

-- Create Iceberg table
CREATE TABLE orders_iceberg
ENGINE = Iceberg(
    'http://localhost:19120/api/v2',
    'warehouse',
    'demo.orders'
)
SETTINGS
    s3_endpoint = 'http://localhost:9000',
    s3_access_key_id = 'admin',
    s3_secret_access_key = 'password123';
```

## Jupyter Notebooks

The setup includes pre-configured Jupyter notebooks:

1. **01_minio_connection.ipynb**
   - Connect to MinIO
   - Read JSON and Parquet files
   - Basic data analysis

2. **02_iceberg_nessie.ipynb**
   - Configure Nessie catalog
   - Query Iceberg tables
   - Work with Nessie branches

Access Jupyter at: http://localhost:8888

## Troubleshooting

### Services not starting
```bash
# Check Docker logs
docker logs minio
docker logs nessie  # or hive-metastore, iceberg-rest

# Verify Docker Compose
docker compose ps
```

### Cannot connect to MinIO
```bash
# Check if MinIO is healthy
curl http://localhost:9000/minio/health/live

# Check MinIO logs
docker logs minio
```

### Catalog connection issues
```bash
# For Nessie
curl http://localhost:19120/api/v2/config

# For Iceberg REST
curl http://localhost:8181/v1/config

# Check catalog logs
docker logs nessie  # or iceberg-rest
```

### Port conflicts
Edit [config.env](config.env) to change default ports:
```bash
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
NESSIE_PORT=19120
# ... etc
```

## Switching Catalogs

To switch between catalog types:

1. Stop current services:
   ```bash
   ./setup.sh --stop
   ```

2. Reconfigure:
   ```bash
   ./setup.sh --configure
   ```

3. Start with new catalog:
   ```bash
   ./setup.sh --start
   ```

## Data Persistence

- MinIO data is persisted in [minio-storage/](minio-storage/)
- PostgreSQL data (for Hive) is in Docker volume `postgres-data`
- To clean all data: `./setup.sh --clean`

## Python Dependencies

For local development:

```bash
pip install minio boto3 pandas pyarrow pyiceberg pynessie
```

For Jupyter notebooks (already included in container):
- All above packages plus PySpark

## Architecture

```
┌─────────────────────────────────────────────┐
│           Data Lake Architecture            │
├─────────────────────────────────────────────┤
│                                             │
│  ┌──────────┐      ┌────────────────┐      │
│  │  MinIO   │◄────►│  Data Catalog  │      │
│  │ (Storage)│      │ (Nessie/Hive/  │      │
│  └──────────┘      │  Iceberg REST) │      │
│       ▲            └────────────────┘      │
│       │                     ▲               │
│       │                     │               │
│  ┌────┴─────┐      ┌───────┴──────┐       │
│  │ Jupyter  │      │  ClickHouse  │       │
│  │ Notebook │      │   (External) │       │
│  └──────────┘      └──────────────┘       │
│                                             │
└─────────────────────────────────────────────┘
```

## Resources

- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [Apache Iceberg](https://iceberg.apache.org/)
- [Project Nessie](https://projectnessie.org/)
- [ClickHouse S3 Integration](https://clickhouse.com/docs/en/engines/table-engines/integrations/s3)

## License

This is a demonstration project for educational purposes.

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Docker logs
3. Verify configuration in [config.env](config.env)
