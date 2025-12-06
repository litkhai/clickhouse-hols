#!/bin/bash

# ClickHouse OSS environment initial setup script
# Usage: ./set.sh [VERSION1] [VERSION2] [VERSION3] ...
# Example: ./set.sh 24.10 25.6 25.10
#          ./set.sh 25.10
#          ./set.sh (defaults to latest)

set -e

# Version parameters (default to latest if not specified)
if [ $# -eq 0 ]; then
    CLICKHOUSE_VERSIONS=("latest")
else
    CLICKHOUSE_VERSIONS=("$@")
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="ClickHouse OSS Multi-Version Setup"

echo "🚀 $SCRIPT_NAME"
echo "=================================="
echo "📍 Installation directory: $BASE_DIR"
echo "📦 ClickHouse versions: ${CLICKHOUSE_VERSIONS[*]}"
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

# Function to convert version to port number (e.g., 24.10 -> 2410, 25.6 -> 2506)
version_to_port() {
    local version=$1
    if [ "$version" = "latest" ]; then
        echo "9999"
    else
        # Split version by dot and pad the minor version to 2 digits
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        printf "%02d%02d" "$major" "$minor"
    fi
}

# Start docker-compose.yml
cat > docker-compose.yml << 'COMPOSE_START'
services:
COMPOSE_START

# Add service for each version
for version in "${CLICKHOUSE_VERSIONS[@]}"; do
    PORT=$(version_to_port "$version")
    HTTP_PORT="${PORT}"
    TCP_PORT="${PORT}1"
    CONTAINER_NAME="clickhouse-${version//./-}"

    cat >> docker-compose.yml << EOF
  clickhouse-${version//./-}:
    image: clickhouse/clickhouse-server:${version}
    container_name: ${CONTAINER_NAME}
    hostname: clickhouse-${version//./-}
    ports:
      - "${HTTP_PORT}:8123"  # HTTP Interface
      - "${TCP_PORT}:9000"   # TCP Interface
    volumes:
      - clickhouse_data_${version//./_}:/var/lib/clickhouse
      - clickhouse_logs_${version//./_}:/var/log/clickhouse-server
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

EOF
done

# Add volumes section
cat >> docker-compose.yml << 'VOLUMES_START'
volumes:
VOLUMES_START

for version in "${CLICKHOUSE_VERSIONS[@]}"; do
    cat >> docker-compose.yml << EOF
  clickhouse_data_${version//./_}:
    driver: local
  clickhouse_logs_${version//./_}:
    driver: local
EOF
done

# Add networks section
cat >> docker-compose.yml << 'NETWORKS_END'

networks:
  default:
    name: clickhouse-network
    driver: bridge
NETWORKS_END

# Create .env file
echo "📝 Creating environment variables file..."
cat > .env << EOF
# ClickHouse configuration
CLICKHOUSE_DB=default
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=

# Docker Compose configuration
COMPOSE_PROJECT_NAME=clickhouse-oss

# Configured versions
CLICKHOUSE_VERSIONS="${CLICKHOUSE_VERSIONS[*]}"
EOF

# Create start.sh script
echo "📝 Creating start script..."
cat > start.sh << 'STARTSH'
#!/bin/bash

echo "🚀 Starting ClickHouse Multi-Version..."
echo "======================================"

# Function to convert version to port number
version_to_port() {
    local version=$1
    if [ "$version" = "latest" ]; then
        echo "9999"
    else
        # Split version by dot and pad the minor version to 2 digits
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        printf "%02d%02d" "$major" "$minor"
    fi
}

# Load configured versions from .env
if [ -f .env ]; then
    source .env
    IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
else
    echo "❌ .env file not found. Please run ./set.sh first."
    exit 1
fi

echo "📦 Configured versions: ${VERSIONS[*]}"
echo ""

# Clean up existing containers if present
echo "🔄 Cleaning up old containers..."
docker-compose down 2>/dev/null || true

# Pull latest images
echo "📥 Pulling ClickHouse images..."
docker-compose pull

# Start all ClickHouse containers
echo "▶️  Starting ClickHouse containers..."
docker-compose up -d

echo ""
echo "⏳ Waiting for ClickHouse initialization..."
echo "   (checking each version, up to 45 seconds per version)"
echo ""

# Check status for each version
ALL_STARTED=true
for version in "${VERSIONS[@]}"; do
    PORT=$(version_to_port "$version")
    CONTAINER_NAME="clickhouse-${version//./-}"

    echo "Checking version ${version} on port ${PORT}..."

    # Wait up to 45 seconds
    STARTED=false
    for i in {1..45}; do
        if curl -s http://localhost:${PORT}/ping > /dev/null 2>&1; then
            echo "✅ Version ${version} started successfully! (port ${PORT})"
            STARTED=true
            break
        fi

        echo -ne "\r   Waiting... ${i}s"
        sleep 1
    done

    if [ "$STARTED" = false ]; then
        echo ""
        echo "⚠️  Version ${version} startup timeout. Check logs:"
        echo "   docker logs ${CONTAINER_NAME}"
        ALL_STARTED=false
    fi
    echo ""
done

if [ "$ALL_STARTED" = true ]; then
    echo "✅ All ClickHouse versions started successfully!"
else
    echo "⚠️  Some versions failed to start. Check logs above."
fi

echo ""
echo "🎯 Connection Information:"
for version in "${VERSIONS[@]}"; do
    PORT=$(version_to_port "$version")
    echo "   Version ${version}:"
    echo "      📍 Web UI: http://localhost:${PORT}/play"
    echo "      📍 HTTP API: http://localhost:${PORT}"
    echo "      📍 TCP: localhost:${PORT}1"
    echo "      👤 User: default (no password)"
    echo ""
done

echo "🔧 Management Commands:"
echo "   ./stop.sh              - Stop all versions (preserve data)"
echo "   ./stop.sh --cleanup    - Stop and delete all data"
echo "   ./status.sh            - Check status and resource usage"
echo "   ./client.sh <PORT>     - Connect to specific version"
echo "   Example: ./client.sh ${PORT} (for version ${version})"
echo ""
echo "✅ ClickHouse is ready! (No get_mempolicy errors with seccomp profile)"
STARTSH

# Create stop.sh script
echo "📝 Creating stop script..."
cat > stop.sh << 'STOPSH'
#!/bin/bash

echo "🛑 Stopping ClickHouse Multi-Version..."
echo "======================================="

# Check for cleanup flag
CLEANUP=false
if [ "$1" = "--cleanup" ] || [ "$1" = "-c" ]; then
    CLEANUP=true
    echo ""
    echo "⚠️  Cleanup mode enabled - will delete all data!"
    echo ""
fi

# Load configured versions
if [ -f .env ]; then
    source .env
    IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
else
    VERSIONS=()
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
    echo "▶️  Stopping containers directly..."
    for version in "${VERSIONS[@]}"; do
        CONTAINER_NAME="clickhouse-${version//./-}"
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
    done
fi

# Check status
echo ""
echo "📊 Container status:"
STILL_RUNNING=false
for version in "${VERSIONS[@]}"; do
    CONTAINER_NAME="clickhouse-${version//./-}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "   ⚠️  ${CONTAINER_NAME} is still running."
        STILL_RUNNING=true
    else
        echo "   ✓ ${CONTAINER_NAME} stopped"
    fi
done

if [ "$STILL_RUNNING" = true ]; then
    echo ""
    echo "⚠️  Some containers are still running."
    echo "   Force stop: docker-compose kill"
else
    echo ""
    echo "✅ All ClickHouse containers stopped successfully."
fi

# Additional cleanup if requested
if [ "$CLEANUP" = true ]; then
    echo ""
    echo "🗑️  Removing Docker volumes..."
    for version in "${VERSIONS[@]}"; do
        docker volume rm clickhouse-oss_clickhouse_data_${version//./_} 2>/dev/null && echo "   ✓ Removed data volume for ${version}" || true
        docker volume rm clickhouse-oss_clickhouse_logs_${version//./_} 2>/dev/null && echo "   ✓ Removed logs volume for ${version}" || true
    done

    echo ""
    echo "🧹 Cleaning up network..."
    docker network rm clickhouse-network 2>/dev/null && echo "   ✓ Removed clickhouse-network" || true

    echo ""
    echo "🗑️  Removing Docker images..."
    for version in "${VERSIONS[@]}"; do
        docker rmi clickhouse/clickhouse-server:${version} 2>/dev/null && echo "   ✓ Removed image ${version}" || true
    done

    echo ""
    echo "✅ Complete cleanup finished!"
fi

echo ""
if [ "$CLEANUP" = true ]; then
    echo "🔧 To setup again: ./set.sh <VERSION1> <VERSION2> ..."
else
    echo "🔧 To restart: ./start.sh"
    echo "🧹 To stop with cleanup: ./stop.sh --cleanup"
fi
STOPSH

# Create status.sh script
echo "📝 Creating status check script..."
cat > status.sh << 'STATUSSH'
#!/bin/bash

echo "📊 ClickHouse Multi-Version Status"
echo "===================================="

# Function to convert version to port number
version_to_port() {
    local version=$1
    if [ "$version" = "latest" ]; then
        echo "9999"
    else
        # Split version by dot and pad the minor version to 2 digits
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        printf "%02d%02d" "$major" "$minor"
    fi
}

# Load configured versions
if [ -f .env ]; then
    source .env
    IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
else
    echo "❌ .env file not found. Please run ./set.sh first."
    exit 1
fi

echo ""
echo "📦 Configured versions: ${VERSIONS[*]}"
echo ""

# Container status
echo "🐳 Container Status:"
ANY_RUNNING=false
for version in "${VERSIONS[@]}"; do
    CONTAINER_NAME="clickhouse-${version//./-}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        STATUS=$(docker ps --format '{{.Status}}' --filter "name=^${CONTAINER_NAME}$")
        echo "   ✅ ${CONTAINER_NAME}: ${STATUS}"
        ANY_RUNNING=true
    else
        echo "   ❌ ${CONTAINER_NAME}: Not running"
    fi
done

if [ "$ANY_RUNNING" = false ]; then
    echo ""
    echo "❌ No ClickHouse containers are running."
    echo "   To start: ./start.sh"
    echo ""
    exit 1
fi

echo ""

# Service health check for each version
echo "💓 Service Status:"
for version in "${VERSIONS[@]}"; do
    PORT=$(version_to_port "$version")
    CONTAINER_NAME="clickhouse-${version//./-}"

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo ""
        echo "   Version ${version} (port ${PORT}):"

        if curl -s http://localhost:${PORT}/ping > /dev/null 2>&1; then
            echo "      ✅ HTTP Interface: OK (port ${PORT})"

            # Version information
            VERSION_INFO=$(curl -s http://localhost:${PORT}/ 2>/dev/null | grep -o 'ClickHouse server version [0-9.]*' | head -1)
            if [ -n "$VERSION_INFO" ]; then
                echo "      ✅ ${VERSION_INFO}"
            fi
        else
            echo "      ❌ HTTP Interface: Connection failed (port ${PORT})"
        fi

        # TCP port check
        TCP_PORT="${PORT}1"
        if nc -z localhost ${TCP_PORT} 2>/dev/null; then
            echo "      ✅ TCP Interface: OK (port ${TCP_PORT})"
        else
            echo "      ❌ TCP Interface: Connection failed (port ${TCP_PORT})"
        fi
    fi
done

echo ""

# Resource usage
echo "💾 Resource Usage:"
for version in "${VERSIONS[@]}"; do
    CONTAINER_NAME="clickhouse-${version//./-}"
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" ${CONTAINER_NAME} 2>/dev/null
    fi
done

echo ""

# Volume information
echo "💿 Data Volumes:"
docker volume ls | grep clickhouse || echo "No volumes found."

echo ""
echo "🔧 Management Commands:"
echo "   ./start.sh          - Start all ClickHouse versions"
echo "   ./stop.sh           - Stop all versions"
echo "   ./client.sh <PORT>  - Connect to specific version"
echo "   docker-compose logs -f  - View real-time logs"
echo ""
echo "📍 Connection URLs:"
for version in "${VERSIONS[@]}"; do
    PORT=$(version_to_port "$version")
    echo "   Version ${version}: http://localhost:${PORT}/play"
done
STATUSSH

# Create client.sh script
echo "📝 Creating client connection script..."
cat > client.sh << 'CLIENTSH'
#!/bin/bash

echo "🔌 ClickHouse Client Connection"
echo "================================"

# Function to convert version to port number
version_to_port() {
    local version=$1
    if [ "$version" = "latest" ]; then
        echo "9999"
    else
        # Split version by dot and pad the minor version to 2 digits
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        printf "%02d%02d" "$major" "$minor"
    fi
}

# Function to convert port to version
port_to_version() {
    local port=$1
    # Load configured versions
    if [ -f .env ]; then
        source .env
        IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
        for version in "${VERSIONS[@]}"; do
            if [ "$(version_to_port "$version")" = "$port" ]; then
                echo "$version"
                return
            fi
        done
    fi
    echo ""
}

# Check if port parameter is provided
if [ $# -eq 0 ]; then
    echo "❌ Error: Port number required"
    echo ""
    echo "Usage: ./client.sh <PORT>"
    echo ""
    echo "Available versions and ports:"
    if [ -f .env ]; then
        source .env
        IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
        for version in "${VERSIONS[@]}"; do
            PORT=$(version_to_port "$version")
            echo "   - Version ${version}: port ${PORT}"
        done
    fi
    exit 1
fi

PORT=$1
VERSION=$(port_to_version "$PORT")

if [ -z "$VERSION" ]; then
    echo "❌ Error: Port ${PORT} is not configured"
    echo ""
    echo "Available versions and ports:"
    if [ -f .env ]; then
        source .env
        IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
        for version in "${VERSIONS[@]}"; do
            VPORT=$(version_to_port "$version")
            echo "   - Version ${version}: port ${VPORT}"
        done
    fi
    exit 1
fi

CONTAINER_NAME="clickhouse-${VERSION//./-}"

# Check container status
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ ClickHouse version ${VERSION} (port ${PORT}) is not running."
    echo "   To start: ./start.sh"
    exit 1
fi

# Check service status
if ! curl -s http://localhost:${PORT}/ping > /dev/null 2>&1; then
    echo "❌ ClickHouse version ${VERSION} service is not responding."
    echo "   Check status: ./status.sh"
    exit 1
fi

echo "✅ Connecting to version ${VERSION} on port ${PORT}..."
echo "   To exit: type 'exit' or press Ctrl+D"
echo ""

# Connect to client
docker exec -it ${CONTAINER_NAME} clickhouse-client
CLIENTSH

# Create cleanup.sh script (for complete data deletion)
echo "📝 Creating cleanup script..."
cat > cleanup.sh << 'CLEANUPSH'
#!/bin/bash

echo "🧹 ClickHouse Multi-Version Complete Cleanup"
echo "============================================="
echo ""
echo "⚠️  Warning: This will delete all ClickHouse data!"
echo "   - All databases from all versions"
echo "   - All tables from all versions"
echo "   - All logs"
echo ""

# Load configured versions
if [ -f .env ]; then
    source .env
    IFS=' ' read -ra VERSIONS <<< "$CLICKHOUSE_VERSIONS"
    echo "Configured versions: ${VERSIONS[*]}"
    echo ""
else
    VERSIONS=()
fi

read -p "Are you sure you want to delete all data? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "❌ Cleanup cancelled."
    exit 1
fi

echo "🛑 Stopping and removing containers..."
docker-compose down -v

echo ""
echo "🗑️  Removing Docker volumes..."
for version in "${VERSIONS[@]}"; do
    docker volume rm clickhouse-oss_clickhouse_data_${version//./_} 2>/dev/null && echo "   ✓ Removed data volume for ${version}" || true
    docker volume rm clickhouse-oss_clickhouse_logs_${version//./_} 2>/dev/null && echo "   ✓ Removed logs volume for ${version}" || true
done

echo ""
echo "🧹 Cleaning up network..."
docker network rm clickhouse-network 2>/dev/null && echo "   ✓ Removed clickhouse-network" || true

echo ""
echo "🗑️  Removing Docker images..."
for version in "${VERSIONS[@]}"; do
    docker rmi clickhouse/clickhouse-server:${version} 2>/dev/null && echo "   ✓ Removed image ${version}" || true
done

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "🔄 To setup again: ./set.sh <VERSION1> <VERSION2> ..."
CLEANUPSH

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

# Download Docker images
echo "📥 Downloading ClickHouse images..."
for version in "${CLICKHOUSE_VERSIONS[@]}"; do
    echo "   Pulling version ${version}..."
    # Remove old images to ensure we get the actual latest version
    docker rmi clickhouse/clickhouse-server:${version} 2>/dev/null || true
    docker pull clickhouse/clickhouse-server:${version}
done

echo ""
echo "✅ ClickHouse OSS multi-version environment setup complete!"
echo ""
echo "📋 What was configured:"
echo "   ✓ Seccomp profile (fixes NUMA syscall errors)"
echo "   ✓ Docker Compose with versions: ${CLICKHOUSE_VERSIONS[*]}"
echo "   ✓ Named volumes for data persistence"
echo "   ✓ Management scripts (start/stop/status/client/cleanup)"
echo ""
echo "📍 Version to Port mapping:"
for version in "${CLICKHOUSE_VERSIONS[@]}"; do
    PORT=$(version_to_port "$version")
    echo "   - Version ${version}: HTTP=${PORT}, TCP=${PORT}1"
done
echo ""
echo "🎯 Next steps:"
echo "   1. Start all ClickHouse versions: cd $BASE_DIR && ./start.sh"
echo "   2. Connect to specific version: cd $BASE_DIR && ./client.sh <PORT>"
echo "      Example: ./client.sh 2410 (for version 24.10)"
echo ""
echo "🔧 Useful commands:"
echo "   ./status.sh          - Check system status"
echo "   ./stop.sh            - Stop all versions (preserve data)"
echo "   ./stop.sh --cleanup  - Stop and delete all data"
echo ""
echo "📖 For more details, see README.md"
