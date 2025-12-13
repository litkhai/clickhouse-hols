# Changes in Version 3.1 - Simplified Setup

**Date**: 2025-12-13
**Status**: ✅ Complete

---

## 🎯 What Changed

### Major Improvements

1. **✨ Multiple Catalogs Simultaneously**
   - Before: Only 1 catalog at a time
   - After: Run any combination of catalogs together
   - Example: `./setup-simple.sh --start nessie unity hive`

2. **🚀 Simplified Setup**
   - Before: Must configure before starting
   - After: Sensible defaults, configuration optional
   - Example: `./setup-simple.sh --start` (just works!)

3. **📦 Cleaner Project Structure**
   - Legacy scripts moved to `scripts-legacy/`
   - Confusing scripts (generate_parquet, register_data, quickstart) removed from root
   - Clear separation of core vs legacy

---

## 📊 Comparison

### Old Flow (setup.sh)

```bash
# Step 1: Configure (REQUIRED)
./setup.sh --configure
# Select 1 catalog from menu (1-5)

# Step 2: Start
./setup.sh --start

# Problem: Want to try another catalog?
./setup.sh --stop
./setup.sh --configure  # Select different catalog
./setup.sh --start      # Restart everything
```

### New Flow (setup-simple.sh)

```bash
# One command, multiple catalogs!
./setup-simple.sh --start nessie unity hive

# Or start everything with defaults
./setup-simple.sh --start

# Want to test different combinations?
./setup-simple.sh --stop
./setup-simple.sh --start polaris iceberg  # Different catalogs
```

---

## 📁 New Files

| File | Purpose | Usage |
|------|---------|-------|
| `setup-simple.sh` | **Main setup script** | `./setup-simple.sh --start` |
| `config-simple.env` | New configuration | Auto-created with defaults |
| `GETTING_STARTED.md` | Quick start guide | Read first! |
| `README-SIMPLE.md` | Simplified readme | Full guide for v3.1 |
| `CHANGES_v3.1.md` | This file | What changed |

---

## 🗑️ Cleaned Up

| File | Action | New Location |
|------|--------|--------------|
| `generate_parquet.py` | Moved | `scripts-legacy/` |
| `register_data.py` | Moved | `scripts-legacy/` |
| `quickstart.sh` | Moved | `scripts-legacy/` |

**Reason**: These scripts were confusing and not essential for core functionality.

---

## 🔄 Migration Guide

### If you were using setup.sh

**Old commands still work!** But consider migrating:

| Old | New | Why |
|-----|-----|-----|
| `./setup.sh --configure` + `./setup.sh --start` | `./setup-simple.sh --start` | Simpler, has defaults |
| Multiple configure/start cycles for different catalogs | `./setup-simple.sh --start catalog1 catalog2` | Start multiple at once |
| One catalog at a time | Any combination | More flexible |

### Migration Steps

1. **Stop old setup**
   ```bash
   ./setup.sh --stop
   ```

2. **Use new setup**
   ```bash
   # Start what you need
   ./setup-simple.sh --start nessie unity

   # Or start everything
   ./setup-simple.sh --start
   ```

3. **Clean up (optional)**
   ```bash
   # Remove old data
   ./setup.sh --clean

   # Or use new clean
   ./setup-simple.sh --clean
   ```

---

## 🎮 New Commands

### Start Services

```bash
# All catalogs (default)
./setup-simple.sh --start

# Specific catalogs
./setup-simple.sh --start nessie unity
./setup-simple.sh --start hive iceberg polaris

# Just one catalog
./setup-simple.sh --start unity
```

### Manage Services

```bash
./setup-simple.sh --stop        # Stop all
./setup-simple.sh --status      # Check status
./setup-simple.sh --clean       # Remove data
./setup-simple.sh --configure   # Interactive config
./setup-simple.sh --help        # Show help
```

---

## 🌟 Key Benefits

### Before (v3.0)

❌ Issues:
- One catalog at a time only
- Must reconfigure to switch catalogs
- Confusing scripts in root directory
- No default configuration

Example workflow to test 3 catalogs:
```bash
# Total time: ~15 minutes with manual steps
./setup.sh --configure  # Select catalog 1
./setup.sh --start
# ... test ...
./setup.sh --stop

./setup.sh --configure  # Select catalog 2
./setup.sh --start
# ... test ...
./setup.sh --stop

./setup.sh --configure  # Select catalog 3
./setup.sh --start
# ... test ...
./setup.sh --stop
```

### After (v3.1)

✅ Benefits:
- Multiple catalogs simultaneously
- One command to start
- Cleaner structure
- Sensible defaults

Example workflow to test 3 catalogs:
```bash
# Total time: ~2 minutes
./setup-simple.sh --start catalog1 catalog2 catalog3
# ... test all three ...
./setup-simple.sh --stop
```

---

## 📖 Documentation Updates

### New Docs
- **[GETTING_STARTED.md](GETTING_STARTED.md)** - Start here!
- **[README-SIMPLE.md](README-SIMPLE.md)** - Full guide for v3.1
- **[CHANGES_v3.1.md](CHANGES_v3.1.md)** - This file

### Updated Docs
- **[README.md](README.md)** - Updated with v3.1 info
- **[STRUCTURE_SUMMARY.md](STRUCTURE_SUMMARY.md)** - New structure

### Unchanged Docs
- **[docs/NAVIGATION_GUIDE.md](docs/NAVIGATION_GUIDE.md)** - Still accurate
- **[docs/UNITY_DELTALAKE_TEST_GUIDE.md](docs/UNITY_DELTALAKE_TEST_GUIDE.md)** - Still accurate
- **[docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)** - Still accurate

---

## 🧪 Testing

All existing tests still work:

```bash
# Test all catalogs
./tests/test-catalogs.sh

# Test Unity + Delta Lake
./tests/test-unity-deltalake.sh

# Examples
./examples/basic-s3-read-write.sh
./examples/delta-lake-simple.sh
```

---

## ⚙️ Technical Details

### Configuration

**Old**: `config.env`
- Single catalog selection via `CATALOG_TYPE`
- Must configure before starting

**New**: `config-simple.env`
- All catalog ports defined
- No catalog selection (all available)
- Auto-created with defaults

### Docker Compose Profiles

**Old approach**:
```bash
# Only one profile at a time
docker-compose --profile nessie up -d
```

**New approach**:
```bash
# Multiple profiles simultaneously
docker-compose --profile nessie --profile unity --profile hive up -d
```

### Backward Compatibility

✅ Old `setup.sh` still works
✅ Old `config.env` still works
✅ All existing tests work
✅ All existing examples work

---

## 📊 Impact Analysis

### What Breaks
❌ Nothing! Old scripts still work.

### What's Better
✅ Faster workflow (multiple catalogs at once)
✅ Simpler commands
✅ Cleaner directory
✅ Better defaults

### What to Update
📝 Update scripts that use `./setup.sh` to use `./setup-simple.sh`
📝 Update documentation references
📝 Update user workflows

---

## 🎓 Learning Path Update

### Recommended for New Users

```
1. GETTING_STARTED.md (new!)
   ↓
2. ./setup-simple.sh --start (simplified!)
   ↓
3. ./examples/basic-s3-read-write.sh
   ↓
4. docs/ (as needed)
```

### Old Learning Path (Still Valid)

```
1. README.md
   ↓
2. ./setup.sh --configure
   ↓
3. ./setup.sh --start
   ↓
4. examples/
```

---

## 🔮 Future Improvements

Potential enhancements:
- [ ] Web UI for configuration
- [ ] Docker Compose v2 syntax (remove version warning)
- [ ] Health checks for all catalogs
- [ ] Automated catalog testing
- [ ] Performance monitoring

---

## 📝 Changelog Summary

### Added
- ✨ `setup-simple.sh` - New simplified setup script
- ✨ `config-simple.env` - Auto-created configuration
- 📚 `GETTING_STARTED.md` - Quick start guide
- 📚 `README-SIMPLE.md` - Simplified documentation
- 📚 `CHANGES_v3.1.md` - This changelog

### Changed
- 📦 Moved legacy scripts to `scripts-legacy/`
- 📖 Updated README.md with v3.1 info
- 🏗️ Updated STRUCTURE_SUMMARY.md

### Deprecated
- ⚠️ `setup.sh` - Still works but `setup-simple.sh` recommended
- ⚠️ `config.env` - Still works but `config-simple.env` is new default

### Removed
- ❌ Nothing removed (backward compatible)

---

## ✅ Checklist for Users

- [ ] Read [GETTING_STARTED.md](GETTING_STARTED.md)
- [ ] Try `./setup-simple.sh --start`
- [ ] Test with examples: `./examples/basic-s3-read-write.sh`
- [ ] Run tests: `./tests/test-catalogs.sh`
- [ ] Update your workflows to use `setup-simple.sh`

---

## 🆘 Getting Help

- **Quick Start**: [GETTING_STARTED.md](GETTING_STARTED.md)
- **Full Guide**: [README-SIMPLE.md](README-SIMPLE.md)
- **Commands**: `./setup-simple.sh --help`
- **Navigation**: [docs/NAVIGATION_GUIDE.md](docs/NAVIGATION_GUIDE.md)

---

**Version**: 3.1
**Release Date**: 2025-12-13
**Status**: ✅ Production Ready
**Recommendation**: Use `setup-simple.sh` for all new work
