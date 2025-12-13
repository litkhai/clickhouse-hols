# Getting Started - Simplified Guide

## 🚀 Quick Start (3 Steps)

### Step 1: Configure (Optional - uses defaults if skipped)

```bash
./setup-simple.sh --configure
```

This sets:
- MinIO storage size (default: 20G)
- Ports for MinIO and catalogs

**Default ports:**
- MinIO API: 19000
- MinIO Console: 19001
- Nessie: 19120
- Hive: 9083
- Iceberg REST: 8181
- Polaris: 8182, 8183
- Unity: 8080

### Step 2: Start Services

```bash
# Start ALL catalogs (recommended for testing)
./setup-simple.sh --start

# Or start specific catalogs only
./setup-simple.sh --start nessie unity
./setup-simple.sh --start hive iceberg
```

### Step 3: Try It!

```bash
# Run basic example
./examples/basic-s3-read-write.sh

# Or test catalogs
./tests/test-catalogs.sh
```

---

## 📋 Available Commands

### Configuration
```bash
./setup-simple.sh --configure    # Interactive configuration
```

### Starting Services
```bash
./setup-simple.sh --start                    # Start ALL catalogs
./setup-simple.sh --start nessie unity       # Start specific catalogs
./setup-simple.sh --start all                # Same as no arguments
```

### Managing Services
```bash
./setup-simple.sh --stop      # Stop all services
./setup-simple.sh --status    # Check status
./setup-simple.sh --clean     # Remove all data
./setup-simple.sh --help      # Show help
```

---

## 🎯 Catalog Options

You can run **one or more catalogs simultaneously**:

| Catalog | Keyword | Port | Use Case |
|---------|---------|------|----------|
| **Nessie** | `nessie` | 19120 | Git-like versioning |
| **Hive Metastore** | `hive` | 9083 | Traditional, widely supported |
| **Iceberg REST** | `iceberg` | 8181 | Standard REST API |
| **Polaris** | `polaris` | 8182, 8183 | Apache Polaris |
| **Unity Catalog** | `unity` | 8080 | Databricks-compatible |

### Examples:

```bash
# Test all catalogs
./setup-simple.sh --start

# Just Unity and Nessie
./setup-simple.sh --start unity nessie

# Only Hive
./setup-simple.sh --start hive
```

---

## 🔍 Service Endpoints

After starting, access:

### MinIO
- **Console**: http://localhost:19001
- **API**: http://localhost:19000
- **Login**: admin / password123

### Catalogs (if started)
- **Nessie**: http://localhost:19120
- **Hive**: thrift://localhost:9083
- **Iceberg REST**: http://localhost:8181
- **Polaris**: http://localhost:8182
- **Unity**: http://localhost:8080

---

## 💡 Common Workflows

### Workflow 1: Quick Test

```bash
# 1. Start everything
./setup-simple.sh --start

# 2. Try basic example
./examples/basic-s3-read-write.sh

# 3. Check status
./setup-simple.sh --status
```

### Workflow 2: Unity Catalog Testing

```bash
# 1. Start MinIO + Unity
./setup-simple.sh --start unity

# 2. Start ClickHouse 25.11
cd ../oss-mac-setup
./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 3. Run Unity test
./tests/test-unity-deltalake.sh
```

### Workflow 3: Compare All Catalogs

```bash
# 1. Start all catalogs
./setup-simple.sh --start

# 2. Start ClickHouse
cd ../oss-mac-setup && ./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 3. Test all catalogs
./tests/test-catalogs.sh
```

---

## 🆚 setup.sh vs setup-simple.sh

| Feature | setup.sh (Old) | setup-simple.sh (New) |
|---------|----------------|----------------------|
| **Catalogs** | One at a time | Multiple simultaneously |
| **Configuration** | Must configure | Optional (has defaults) |
| **Usage** | More complex | Simpler commands |
| **Recommendation** | Legacy support | **Recommended** |

### Migration

If you're using the old `setup.sh`:

```bash
# Old way (one catalog)
./setup.sh --configure  # Select 1 catalog
./setup.sh --start

# New way (multiple catalogs)
./setup-simple.sh --start nessie unity  # Start multiple
```

---

## 🔧 Configuration File

Config is stored in: `config-simple.env`

You can edit manually:
```bash
nano config-simple.env
```

Or use interactive mode:
```bash
./setup-simple.sh --configure
```

---

## 🧹 Cleanup

### Stop services (keep data)
```bash
./setup-simple.sh --stop
```

### Remove all data
```bash
./setup-simple.sh --clean
```

---

## 📊 Check What's Running

```bash
./setup-simple.sh --status
```

Shows all running services with ports.

---

## 🐛 Troubleshooting

### Services won't start
```bash
# Check what's running
./setup-simple.sh --status

# Check Docker
docker ps

# Check logs
docker logs minio
docker logs unity-catalog
```

### Port conflicts
```bash
# Check port usage
lsof -i :19000

# Reconfigure with different ports
./setup-simple.sh --configure
```

### Can't connect to MinIO
```bash
# Test MinIO health
curl http://localhost:19000/minio/health/live

# Check MinIO logs
docker logs minio
```

---

## 📖 Next Steps

1. **Learn by example**: Check [examples/](examples/)
2. **Interactive learning**: Jupyter at http://localhost:8888
3. **Run tests**: Check [tests/](tests/)
4. **Read docs**: Check [docs/](docs/)

---

## 🆘 Need Help?

- **Quick reference**: `./setup-simple.sh --help`
- **Full docs**: [README.md](README.md)
- **Navigation**: [docs/NAVIGATION_GUIDE.md](docs/NAVIGATION_GUIDE.md)
- **Testing**: [docs/UNITY_DELTALAKE_TEST_GUIDE.md](docs/UNITY_DELTALAKE_TEST_GUIDE.md)

---

**Last updated**: 2025-12-13
**Version**: 3.1 (Simplified)
