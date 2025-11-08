#!/bin/bash

# ClickHouse OSS environment initial setup script
# Usage: ./setup.sh [VERSION]
# Example: ./setup.sh 25.10
#          ./setup.sh latest
#          ./setup.sh (defaults to latest)

set -e

# Version parameter (default to latest if not specified)
CLICKHOUSE_VERSION="${1:-latest}"
BASE_DIR="/Users/kenlee/clickhouse/oss"
SCRIPT_NAME="ClickHouse OSS Setup"

echo "🚀 $SCRIPT_NAME"
echo "=================================="
echo "📍 Installation directory: $BASE_DIR"
echo "📦 ClickHouse version: $CLICKHOUSE_VERSION"
echo "🔒 Security: Seccomp profile enabled (fixes get_mempolicy error)"
echo ""

# Check Docker environment
echo "🐳 Checking Docker environment..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed!"
    echo "   Install from https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker is not running!"
    echo "   Please start Docker Desktop."
    exit 1
fi

echo "✅ Docker environment check complete"

# Create directory
echo "📁 Creating directory..."
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

# Create seccomp profile (fixes get_mempolicy error)
echo "📝 Creating seccomp security profile..."
cat > seccomp-profile.json << 'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32",
    "SCMP_ARCH_AARCH64",
    "SCMP_ARCH_ARM"
  ],
  "syscalls": [
    {
      "names": [
        "accept",
        "accept4",
        "access",
        "adjtimex",
        "alarm",
        "bind",
        "brk",
        "capget",
        "capset",
        "chdir",
        "chmod",
        "chown",
        "chown32",
        "clone",
        "clone3",
        "clock_adjtime",
        "clock_getres",
        "clock_gettime",
        "clock_nanosleep",
        "close",
        "connect",
        "copy_file_range",
        "creat",
        "dup",
        "dup2",
        "dup3",
        "epoll_create",
        "epoll_create1",
        "epoll_ctl",
        "epoll_ctl_old",
        "epoll_pwait",
        "epoll_wait",
        "epoll_wait_old",
        "eventfd",
        "eventfd2",
        "execve",
        "execveat",
        "exit",
        "exit_group",
        "faccessat",
        "faccessat2",
        "fadvise64",
        "fadvise64_64",
        "fallocate",
        "fanotify_mark",
        "fchdir",
        "fchmod",
        "fchmodat",
        "fchown",
        "fchown32",
        "fchownat",
        "fcntl",
        "fcntl64",
        "fdatasync",
        "fgetxattr",
        "flistxattr",
        "flock",
        "fork",
        "fremovexattr",
        "fsetxattr",
        "fstat",
        "fstat64",
        "fstatat64",
        "fstatfs",
        "fstatfs64",
        "fsync",
        "ftruncate",
        "ftruncate64",
        "futex",
        "futimesat",
        "getcpu",
        "getcwd",
        "getdents",
        "getdents64",
        "getegid",
        "getegid32",
        "geteuid",
        "geteuid32",
        "getgid",
        "getgid32",
        "getgroups",
        "getgroups32",
        "getitimer",
        "get_mempolicy",
        "getpeername",
        "getpgid",
        "getpgrp",
        "getpid",
        "getppid",
        "getpriority",
        "getrandom",
        "getresgid",
        "getresgid32",
        "getresuid",
        "getresuid32",
        "getrlimit",
        "get_robust_list",
        "getrusage",
        "getsid",
        "getsockname",
        "getsockopt",
        "get_thread_area",
        "gettid",
        "gettimeofday",
        "getuid",
        "getuid32",
        "getxattr",
        "inotify_add_watch",
        "inotify_init",
        "inotify_init1",
        "inotify_rm_watch",
        "io_cancel",
        "ioctl",
        "io_destroy",
        "io_getevents",
        "io_pgetevents",
        "ioprio_get",
        "ioprio_set",
        "io_setup",
        "io_submit",
        "io_uring_enter",
        "io_uring_register",
        "io_uring_setup",
        "ipc",
        "kill",
        "lchown",
        "lchown32",
        "lgetxattr",
        "link",
        "linkat",
        "listen",
        "listxattr",
        "llistxattr",
        "_llseek",
        "lremovexattr",
        "lseek",
        "lsetxattr",
        "lstat",
        "lstat64",
        "madvise",
        "mbind",
        "membarrier",
        "memfd_create",
        "mincore",
        "mkdir",
        "mkdirat",
        "mknod",
        "mknodat",
        "mlock",
        "mlock2",
        "mlockall",
        "mmap",
        "mmap2",
        "mprotect",
        "mq_getsetattr",
        "mq_notify",
        "mq_open",
        "mq_timedreceive",
        "mq_timedsend",
        "mq_unlink",
        "mremap",
        "msgctl",
        "msgget",
        "msgrcv",
        "msgsnd",
        "msync",
        "munlock",
        "munlockall",
        "munmap",
        "nanosleep",
        "newfstatat",
        "_newselect",
        "open",
        "openat",
        "openat2",
        "pause",
        "pipe",
        "pipe2",
        "poll",
        "ppoll",
        "prctl",
        "pread64",
        "preadv",
        "preadv2",
        "prlimit64",
        "pselect6",
        "pwrite64",
        "pwritev",
        "pwritev2",
        "read",
        "readahead",
        "readlink",
        "readlinkat",
        "readv",
        "recv",
        "recvfrom",
        "recvmmsg",
        "recvmsg",
        "remap_file_pages",
        "removexattr",
        "rename",
        "renameat",
        "renameat2",
        "restart_syscall",
        "rmdir",
        "rt_sigaction",
        "rt_sigpending",
        "rt_sigprocmask",
        "rt_sigqueueinfo",
        "rt_sigreturn",
        "rt_sigsuspend",
        "rt_sigtimedwait",
        "rt_tgsigqueueinfo",
        "sched_getaffinity",
        "sched_getattr",
        "sched_getparam",
        "sched_get_priority_max",
        "sched_get_priority_min",
        "sched_getscheduler",
        "sched_rr_get_interval",
        "sched_setaffinity",
        "sched_setattr",
        "sched_setparam",
        "sched_setscheduler",
        "sched_yield",
        "seccomp",
        "select",
        "semctl",
        "semget",
        "semop",
        "semtimedop",
        "send",
        "sendfile",
        "sendfile64",
        "sendmmsg",
        "sendmsg",
        "sendto",
        "setfsgid",
        "setfsgid32",
        "setfsuid",
        "setfsuid32",
        "setgid",
        "setgid32",
        "setgroups",
        "setgroups32",
        "setitimer",
        "set_mempolicy",
        "setpgid",
        "setpriority",
        "setregid",
        "setregid32",
        "setresgid",
        "setresgid32",
        "setresuid",
        "setresuid32",
        "setreuid",
        "setreuid32",
        "setrlimit",
        "set_robust_list",
        "setsid",
        "setsockopt",
        "set_thread_area",
        "set_tid_address",
        "setuid",
        "setuid32",
        "setxattr",
        "shmat",
        "shmctl",
        "shmdt",
        "shmget",
        "shutdown",
        "sigaltstack",
        "signalfd",
        "signalfd4",
        "sigprocmask",
        "sigreturn",
        "socket",
        "socketcall",
        "socketpair",
        "splice",
        "stat",
        "stat64",
        "statfs",
        "statfs64",
        "statx",
        "symlink",
        "symlinkat",
        "sync",
        "sync_file_range",
        "syncfs",
        "sysinfo",
        "tee",
        "tgkill",
        "time",
        "timer_create",
        "timer_delete",
        "timer_getoverrun",
        "timer_gettime",
        "timer_settime",
        "timerfd_create",
        "timerfd_gettime",
        "timerfd_settime",
        "times",
        "tkill",
        "truncate",
        "truncate64",
        "ugetrlimit",
        "umask",
        "uname",
        "unlink",
        "unlinkat",
        "utime",
        "utimensat",
        "utimes",
        "vfork",
        "vmsplice",
        "wait4",
        "waitid",
        "waitpid",
        "write",
        "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF

# Create docker-compose.yml (using Named Volume)
echo "📝 Creating Docker Compose configuration..."
cat > docker-compose.yml << EOF
services:
  clickhouse:
    image: clickhouse/clickhouse-server:${CLICKHOUSE_VERSION}
    container_name: clickhouse-oss
    hostname: clickhouse
    ports:
      - "8123:8123"  # HTTP Interface
      - "9000:9000"  # TCP Interface
    volumes:
      # Using Named volume (resolves macOS permission issues)
      - clickhouse_data:/var/lib/clickhouse
      - clickhouse_logs:/var/log/clickhouse-server
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ""
    restart: unless-stopped
    security_opt:
      - seccomp=${BASE_DIR}/seccomp-profile.json
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8123/ping"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s
    ulimits:
      nofile:
        soft: 262144
        hard: 262144

volumes:
  clickhouse_data:
    driver: local
  clickhouse_logs:
    driver: local

networks:
  default:
    name: clickhouse-network
    driver: bridge
EOF

# Create .env file
echo "📝 Creating environment variables file..."
cat > .env << 'EOF'
# ClickHouse configuration
CLICKHOUSE_DB=default
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=

# Docker Compose configuration
COMPOSE_PROJECT_NAME=clickhouse-oss
EOF

# Create start.sh script
echo "📝 Creating start script..."
cat > start.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting ClickHouse..."
echo "========================"

# Clean up existing container if present
if docker ps -a --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "🔄 Cleaning up existing container..."
    docker-compose down
fi

# Start ClickHouse
echo "▶️  Starting ClickHouse container..."
docker-compose up -d

# Wait for initialization
echo "⏳ Waiting for ClickHouse initialization..."
echo "   (up to 45 seconds)"

# Check status (wait up to 45 seconds)
for i in {1..45}; do
    if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
        echo ""
        echo "✅ ClickHouse started successfully!"
        break
    fi

    if [ $i -eq 45 ]; then
        echo ""
        echo "⚠️  Startup is taking longer than expected. Check logs:"
        echo "   docker-compose logs clickhouse"
        exit 1
    fi

    echo -ne "\r   Waiting... ${i}s"
    sleep 1
done

echo ""
echo "🎯 Connection Information:"
echo "   📍 Web UI: http://localhost:8123/play"
echo "   📍 HTTP API: http://localhost:8123"
echo "   📍 TCP: localhost:9000"
echo "   👤 User: default (no password)"
echo ""
echo "🔧 Management Commands:"
echo "   ./stop.sh              - Stop ClickHouse (preserve data)"
echo "   ./stop.sh --cleanup    - Stop and delete all data"
echo "   ./status.sh            - Check status and resource usage"
echo "   ./client.sh            - Connect to CLI client"
echo "   docker logs clickhouse-oss - View container logs"
echo ""
echo "✅ ClickHouse is ready! (No get_mempolicy errors with seccomp profile)"
EOF

# Create stop.sh script
echo "📝 Creating stop script..."
cat > stop.sh << 'EOF'
#!/bin/bash

echo "🛑 Stopping ClickHouse..."
echo "======================="

# Check for cleanup flag
CLEANUP=false
if [ "$1" = "--cleanup" ] || [ "$1" = "-c" ]; then
    CLEANUP=true
    echo ""
    echo "⚠️  Cleanup mode enabled - will delete all data!"
    echo ""
fi

# Stop with Docker Compose
if [ -f "docker-compose.yml" ]; then
    echo "▶️  Stopping with Docker Compose..."
    if [ "$CLEANUP" = true ]; then
        docker-compose down -v
    else
        docker-compose down
    fi
else
    echo "▶️  Stopping container directly..."
    docker stop clickhouse-oss 2>/dev/null || true
    docker rm clickhouse-oss 2>/dev/null || true
fi

# Check status
if docker ps --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "⚠️  Container is still running."
    echo "   Force stop: docker kill clickhouse-oss"
else
    echo "✅ ClickHouse stopped successfully."
fi

# Additional cleanup if requested
if [ "$CLEANUP" = true ]; then
    echo ""
    echo "🗑️  Removing Docker volumes..."
    docker volume rm clickhouse-oss_clickhouse_data 2>/dev/null && echo "   ✓ Removed clickhouse_data volume" || true
    docker volume rm clickhouse-oss_clickhouse_logs 2>/dev/null && echo "   ✓ Removed clickhouse_logs volume" || true

    echo ""
    echo "🧹 Cleaning up network..."
    docker network rm clickhouse-network 2>/dev/null && echo "   ✓ Removed clickhouse-network" || true

    echo ""
    echo "✅ Complete cleanup finished!"
fi

echo ""
if [ "$CLEANUP" = true ]; then
    echo "🔧 To setup again: cd /path/to/setup && ./set.sh"
else
    echo "🔧 To restart: ./start.sh"
    echo "🧹 To stop with cleanup: ./stop.sh --cleanup"
fi
EOF

# Create status.sh script
echo "📝 Creating status check script..."
cat > status.sh << 'EOF'
#!/bin/bash

echo "📊 ClickHouse Status"
echo "=================="

# Container status
echo "🐳 Container Status:"
if docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep clickhouse-oss; then
    echo ""
else
    echo "❌ ClickHouse container is not running."
    echo "   To start: ./start.sh"
    echo ""
    exit 1
fi

# Service health check
echo "💓 Service Status:"
if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "✅ HTTP Interface: OK (port 8123)"

    # Version information
    VERSION=$(curl -s http://localhost:8123/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
    if [ -n "$VERSION" ]; then
        echo "✅ $VERSION"
    fi
else
    echo "❌ HTTP Interface: Connection failed (port 8123)"
fi

# TCP port check
if nc -z localhost 9000 2>/dev/null; then
    echo "✅ TCP Interface: OK (port 9000)"
else
    echo "❌ TCP Interface: Connection failed (port 9000)"
fi

echo ""

# Resource usage
echo "💾 Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" clickhouse-oss 2>/dev/null

echo ""

# Volume information
echo "💿 Data Volumes:"
docker volume ls | grep clickhouse || echo "Volume information not found."

echo ""
echo "🔧 Management Commands:"
echo "   ./start.sh     - Start ClickHouse"
echo "   ./stop.sh      - Stop ClickHouse"
echo "   ./client.sh    - Connect to CLI client"
echo "   docker-compose logs -f  - View real-time logs"
EOF

# Create client.sh script
echo "📝 Creating client connection script..."
cat > client.sh << 'EOF'
#!/bin/bash

echo "🔌 ClickHouse Client Connection"
echo "============================"

# Check container status
if ! docker ps --format '{{.Names}}' | grep -q '^clickhouse-oss$'; then
    echo "❌ ClickHouse is not running."
    echo "   To start: ./start.sh"
    exit 1
fi

# Check service status
if ! curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse service is not responding."
    echo "   Check status: ./status.sh"
    exit 1
fi

echo "✅ Connecting..."
echo "   To exit: type 'exit' or press Ctrl+D"
echo ""

# Connect to client
docker-compose exec clickhouse clickhouse-client
EOF

# Create cleanup.sh script (for complete data deletion)
echo "📝 Creating cleanup script..."
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 ClickHouse Complete Cleanup"
echo "======================"
echo ""
echo "⚠️  Warning: This will delete all ClickHouse data!"
echo "   - All databases"
echo "   - All tables"
echo "   - All logs"
echo ""

read -p "Are you sure you want to delete all data? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 1
fi

echo "🛑 Stopping and removing containers..."
docker-compose down -v

echo "🗑️  Removing Docker volumes..."
docker volume rm clickhouse-oss_clickhouse_data 2>/dev/null || true
docker volume rm clickhouse-oss_clickhouse_logs 2>/dev/null || true

echo "🧹 Cleaning up network..."
docker network rm clickhouse-network 2>/dev/null || true

echo "✅ Cleanup complete!"
echo ""
echo "🔄 To restart: ./start.sh"
EOF

# Create README.md
echo "📝 Creating documentation..."
cat > README.md << 'EOF'
# ClickHouse OSS Environment

ClickHouse development environment optimized for macOS with seccomp security profile.

## ✨ Features

- 🔒 **Seccomp Security Profile** - Fixes `get_mempolicy: Operation not permitted` errors
- 📦 **Version Control** - Specify ClickHouse version or use latest
- 🐳 **Docker Named Volumes** - Persistent data storage with proper macOS permissions
- 🧹 **Easy Cleanup** - Built-in cleanup options for data management
- 🌐 **Multiple Interfaces** - Web UI, HTTP API, and TCP access

## 🚀 Quick Start

```bash
# 1. Setup (first time only) - defaults to latest version
./set.sh

# Or specify a version
./set.sh 25.10

# 2. Start
./start.sh

# 3. Connect
./client.sh
```

## 📍 Connection Information

- **Web UI**: http://localhost:8123/play
- **HTTP API**: http://localhost:8123
- **TCP**: localhost:9000
- **User**: default (no password)

## 🛠 Management Scripts

### Setup
- `./set.sh [VERSION]` - Initial environment setup (first time only)
  - `./set.sh` - Install latest version
  - `./set.sh 25.10` - Install specific version
  - `./set.sh latest` - Explicitly install latest

### Operations
- `./start.sh` - Start ClickHouse (creates seccomp profile automatically)
- `./stop.sh` - Stop ClickHouse (preserves data)
- `./stop.sh --cleanup` or `./stop.sh -c` - Stop and delete all data
- `./status.sh` - Check container status, health, and resource usage
- `./client.sh` - Connect to CLI client
- `./cleanup.sh` - Complete data deletion (with confirmation prompt)

## 🔧 Advanced Usage

```bash
# View real-time logs
docker-compose logs -f

# Execute SQL directly
docker-compose exec clickhouse clickhouse-client --query "SHOW DATABASES"

# Access container shell
docker-compose exec clickhouse bash
```

## 📂 Data Storage

Data is stored in Docker Named Volumes for persistence:
- `clickhouse-oss_clickhouse_data` - Database files
- `clickhouse-oss_clickhouse_logs` - Log files

## 🔄 Updates

```bash
# Update to new version
docker-compose pull
docker-compose up -d
```

## 🔧 Troubleshooting

### get_mempolicy Error
This setup includes a custom seccomp profile that resolves the common `get_mempolicy: Operation not permitted` error. The profile allows necessary NUMA memory policy syscalls (`get_mempolicy`, `set_mempolicy`, `mbind`).

### Container Won't Start
1. Check Docker is running: `docker info`
2. Check logs: `docker logs clickhouse-oss`
3. Verify seccomp profile exists: `ls -la /Users/kenlee/clickhouse/oss/seccomp-profile.json`

### Permission Issues on macOS
This setup uses Docker Named Volumes instead of bind mounts to avoid macOS permission issues with ClickHouse data directories.

## 📋 System Requirements

- macOS (optimized for Apple Silicon and Intel)
- Docker Desktop for Mac
- 4GB+ RAM recommended
- 10GB+ disk space

## 🔐 Security

- Includes custom seccomp profile for container security
- Default user with no password (suitable for development)
- Network isolation with dedicated Docker network
- Data persistence with named volumes
EOF

# Grant script execution permissions
echo "🔐 Setting execution permissions..."
chmod +x *.sh

# Download Docker image
echo "📥 Downloading ClickHouse image..."
docker pull clickhouse/clickhouse-server:${CLICKHOUSE_VERSION}

echo ""
echo "✅ ClickHouse OSS environment setup complete!"
echo ""
echo "📋 What was configured:"
echo "   ✓ Seccomp profile (fixes NUMA syscall errors)"
echo "   ✓ Docker Compose with version $CLICKHOUSE_VERSION"
echo "   ✓ Named volumes for data persistence"
echo "   ✓ Management scripts (start/stop/status/client/cleanup)"
echo ""
echo "🎯 Next steps:"
echo "   1. Start ClickHouse: cd $BASE_DIR && ./start.sh"
echo "   2. Access Web UI: http://localhost:8123/play"
echo "   3. Connect CLI: cd $BASE_DIR && ./client.sh"
echo ""
echo "🔧 Useful commands:"
echo "   ./status.sh          - Check system status"
echo "   ./stop.sh            - Stop (preserve data)"
echo "   ./stop.sh --cleanup  - Stop and delete all data"
echo ""
echo "📖 For more details, see README.md"
