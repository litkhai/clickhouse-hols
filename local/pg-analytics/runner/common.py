"""Shared plumbing for every phase: connections, container control, counters.

Runs inside the `runner` container (docker compose run --rm runner ...), which
reaches the engines by service name and the Docker API through the socket.
"""
import datetime as dt
import decimal
import hashlib
import json
import os
import pathlib
import re
import subprocess
import threading
import time

import docker
import psycopg
import requests

LAB = pathlib.Path(__file__).resolve().parents[1]
STATE = json.loads((LAB / ".state" / "polaris.json").read_text()) \
    if (LAB / ".state" / "polaris.json").exists() else None
DB = os.environ.get("ILM_DB", "ilm")

C_PG_MAIN, C_PG_DUCK, C_CH = "pga-pg-main", "pga-pg-duck", "pga-clickhouse"
C_PG_DUCK_MAIN = "pga-pg-duck-main"
ENGINES = [C_PG_MAIN, C_PG_DUCK, C_PG_DUCK_MAIN, C_CH]

# which containers a path needs up; everything else in ENGINES is stopped
# B2 = B' (pg_duckdb main build), measured as a reference next to released B
PATH_CONTAINERS = {"A": [C_PG_MAIN], "B": [C_PG_DUCK], "B2": [C_PG_DUCK_MAIN], "C": [C_PG_MAIN, C_CH]}
# the container that executes the lake scan for each path
PATH_ENGINE = {"A": C_PG_MAIN, "B": C_PG_DUCK, "B2": C_PG_DUCK_MAIN, "C": C_CH}

dk = docker.from_env()


# ---------------------------------------------------------------- connections
PG_HOST = {C_PG_MAIN: "pg-main", C_PG_DUCK: "pg-duck", C_PG_DUCK_MAIN: "pg-duck-main"}


def pg_dsn(container):
    host = PG_HOST[container]
    return f"host={host} port=5432 user=postgres dbname={DB} connect_timeout=10"


def connect(path, autocommit=True):
    """A Postgres session for a path. Every path is queried through Postgres."""
    c = psycopg.connect(pg_dsn({"B": C_PG_DUCK, "B2": C_PG_DUCK_MAIN}.get(path, C_PG_MAIN)),
                        autocommit=autocommit)
    return c


def psql(container, sql=None, file=None, db=None, variables=None, check=True):
    """Run psql from the runner (for multi-statement init scripts)."""
    host = PG_HOST[container]
    cmd = ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-h", host, "-U", "postgres", "-d", db or DB]
    for k, v in (variables or {}).items():
        cmd += ["-v", f"{k}={v}"]
    cmd += ["-f", str(file)] if file else ["-c", sql]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"psql failed ({file or sql[:80]}):\n{r.stdout}\n{r.stderr}")
    return r.stdout + r.stderr


def ch(sql, fmt="TSV", settings=None):
    params = {"default_format": fmt}
    params.update(settings or {})
    r = requests.post("http://clickhouse:8123/", params=params, data=sql.encode(), timeout=900)
    if r.status_code != 200:
        raise RuntimeError(f"ClickHouse: {r.text[:2000]}")
    return r.text


def polaris_metadata_location(table, namespace="tpch"):
    """Current metadata.json of a table, asked from Polaris (the source of truth
    for catalog = 'rest' tables; pg_lake does not keep it locally)."""
    r = STATE["reader"]
    tok = requests.post(STATE["oauth_uri"], data={
        "grant_type": "client_credentials", "client_id": r["client_id"],
        "client_secret": r["client_secret"], "scope": "PRINCIPAL_ROLE:ALL"}).json()["access_token"]
    j = requests.get(f"{STATE['rest_uri']}/v1/{STATE['catalog']}/namespaces/{namespace}/tables/{table}",
                     headers={"Authorization": f"Bearer {tok}"}).json()
    return j["metadata-location"]


# ---------------------------------------------------------------- containers
def container(name):
    return dk.containers.get(name)


def wait_ready(name, timeout=180):
    t0 = time.time()
    while time.time() - t0 < timeout:
        c = container(name)
        c.reload()
        h = c.attrs["State"].get("Health", {}).get("Status")
        if c.status == "running" and h in (None, "healthy"):
            if name == C_CH:
                try:
                    ch("SELECT 1")
                    return
                except Exception:
                    pass
            else:
                try:
                    psycopg.connect(pg_dsn(name).replace(f"dbname={DB}", "dbname=postgres")).close()
                    if name == C_PG_MAIN and container(name).exec_run(
                            "psql -h /var/lib/pgduck/socket -p 5332 -Atqc 'SELECT 1'").exit_code != 0:
                        raise RuntimeError("pgduck_server not up yet")
                    return
                except Exception:
                    pass
        time.sleep(1)
    raise TimeoutError(f"{name} not ready after {timeout}s")


def set_active(path):
    """Stop engines the path does not use (8 GB VM: paused containers keep
    their memory, so the bench stops rather than pauses them)."""
    need = PATH_CONTAINERS[path]
    for n in ENGINES:
        c = container(n)
        if n in need and c.status != "running":
            c.start()
        elif n not in need and c.status == "running":
            c.stop(timeout=30)
    for n in need:
        wait_ready(n)


def drop_os_caches():
    """Drop the Docker VM's page cache from a privileged throwaway container."""
    dk.containers.run("alpine:3.20", "sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'",
                      privileged=True, remove=True)


def make_cold(path):
    """Restart the path's engines with empty engine caches, then drop the page cache."""
    if C_PG_MAIN in PATH_CONTAINERS[path]:
        container(C_PG_MAIN).exec_run("sh -c 'rm -rf /var/lib/pgduck/cache/*'")
    if path == "C":
        try:
            ch("SYSTEM DROP FILESYSTEM CACHE")
            ch("SYSTEM DROP ICEBERG METADATA CACHE")
            ch("SYSTEM DROP PARQUET METADATA CACHE")
        except Exception:
            pass
    for n in PATH_CONTAINERS[path]:
        container(n).restart(timeout=60)
    drop_os_caches()
    for n in PATH_CONTAINERS[path]:
        wait_ready(n)


def set_cpus(name, cpus):
    container(name).update(nano_cpus=int(cpus * 1e9))


# ---------------------------------------------------------------- counters
def cgroup_cpu_s(name):
    """Cumulative CPU seconds the container's cgroup has used."""
    s = container(name).stats(stream=False, one_shot=True)
    return s["cpu_stats"]["cpu_usage"]["total_usage"] / 1e9


def pgduck_cpu_s():
    """utime+stime of pgduck_server inside pg-main (clock ticks -> s).
    Lets path A's DuckDB work be split from the Postgres backends'."""
    out = container(C_PG_MAIN).exec_run(
        "sh -c 'for p in $(pgrep -x pgduck_server); do cat /proc/$p/stat; done'").output.decode()
    total = 0
    for line in out.splitlines():
        f = line.rsplit(")", 1)[1].split()
        total += int(f[11]) + int(f[12])  # fields 14/15 overall: utime, stime
    return total / 100.0


def minio_counters():
    """Cumulative bytes sent and S3 requests served by MinIO.
    Uses the v3 API metrics: the v2 cluster endpoint is refreshed every
    ~10 s, which silently books one query's reads on the next one."""
    txt = requests.get("http://minio:9000/minio/metrics/v3/api/requests", timeout=10).text
    sent = reqs = 0.0
    for line in txt.splitlines():
        if line.startswith("minio_api_requests_traffic_sent_bytes"):
            sent += float(line.rsplit(" ", 1)[1])
        elif line.startswith("minio_api_requests_total"):
            reqs += float(line.rsplit(" ", 1)[1])
    return sent, reqs


class MemSampler(threading.Thread):
    """Peak working-set memory (usage minus page cache) per container, ~2 Hz."""

    def __init__(self, names):
        super().__init__(daemon=True)
        self.names, self.peak, self._halt = names, {n: 0.0 for n in names}, threading.Event()

    def run(self):
        while not self._halt.is_set():
            for n in self.names:
                try:
                    m = container(n).stats(stream=False, one_shot=True)["memory_stats"]
                    ws = m["usage"] - m.get("stats", {}).get("inactive_file", 0)
                    self.peak[n] = max(self.peak[n], ws / 2**20)
                except Exception:
                    pass
            self._halt.wait(0.5)

    def stop(self):
        self._halt.set()
        self.join(timeout=5)
        return self.peak


class Probe:
    """Everything measured around one query execution."""

    def __init__(self, path):
        self.path = path
        self.names = PATH_CONTAINERS[path]

    def __enter__(self):
        self.cpu0 = {n: cgroup_cpu_s(n) for n in self.names}
        self.duck0 = pgduck_cpu_s() if C_PG_MAIN in self.names else 0.0
        self.s30 = minio_counters()
        self.mem = MemSampler(self.names)
        self.mem.start()
        self.t0 = time.perf_counter()
        return self

    def __exit__(self, *exc):
        self.latency_ms = (time.perf_counter() - self.t0) * 1000
        peak = self.mem.stop()
        cpu = {n: cgroup_cpu_s(n) - self.cpu0[n] for n in self.names}
        duck = (pgduck_cpu_s() - self.duck0) if C_PG_MAIN in self.names else 0.0
        s3 = minio_counters()
        eng = PATH_ENGINE[self.path]
        self.m = {
            "pg_main_cpu_s": round(cpu.get(C_PG_MAIN, 0.0), 3) if C_PG_MAIN in cpu else "",
            "pg_main_pgduck_cpu_s": round(duck, 3) if C_PG_MAIN in cpu else "",
            "pg_main_peak_mem_mb": round(peak.get(C_PG_MAIN, 0.0)) if C_PG_MAIN in peak else "",
            "engine_cpu_s": round(cpu[eng], 3),
            "engine_peak_mem_mb": round(peak[eng]),
            "s3_bytes_read": int(s3[0] - self.s30[0]),
            "s3_requests": int(s3[1] - self.s30[1]),
        }
        return False


# ---------------------------------------------------------------- results
def _norm(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return str(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, (float, decimal.Decimal)):
        f = float(v)
        if f == int(f) and abs(f) < 1e15:
            return str(int(f))
        return f"{f:.10g}"
    if isinstance(v, dt.datetime):
        return v.date().isoformat() if v.time() == dt.time(0) else v.isoformat()
    if isinstance(v, dt.date):
        return v.isoformat()
    return str(v).rstrip()


def result_hash(rows):
    """Order-independent digest of a result, tolerant of numeric type and
    float summation-order differences at the 10th significant digit."""
    lines = sorted("|".join(_norm(v) for v in r) for r in rows)
    return hashlib.md5("\n".join(lines).encode()).hexdigest()


def classify_pushdown(path, plan):
    """full / partial / none from EXPLAIN (VERBOSE) text."""
    if path == "A":
        if "Query Pushdown" in plan:
            return "full"
        if "Foreign Scan" in plan or "Custom Scan" in plan:
            return "partial"
        return "none"
    if path in ("B", "B2"):
        top = next((l for l in plan.splitlines() if l.strip()), "")
        if "DuckDBScan" in top:
            return "full"
        return "partial" if "DuckDB" in plan else "none"
    # path C: the Remote SQL must carry the aggregation or join to count as pushed
    remote = " ".join(re.findall(r"Remote SQL: (.*)", plan))
    if not remote:
        return "none"
    top = plan.splitlines()[0]
    if top.lstrip().startswith("Foreign Scan") and re.search(r"GROUP BY|JOIN|count\(|sum\(", remote, re.I):
        return "full"
    return "partial"


def versions():
    """Engine versions, recorded with every result row."""
    v = {}
    if container(C_PG_MAIN).status == "running":  # stopped while B/B2 run
        with connect("A") as c:
            v["postgres"] = c.execute("SHOW server_version").fetchone()[0]
            for n, ver in c.execute("SELECT extname, extversion FROM pg_extension "
                                    "WHERE extname IN ('pg_lake', 'pg_clickhouse')"):
                v[n] = ver
        out = container(C_PG_MAIN).exec_run(
            "psql -h /var/lib/pgduck/socket -p 5332 -Atc 'SELECT version()'").output.decode().strip()
        v["pg_lake_duckdb"] = out
    try:
        c = container(C_PG_DUCK)
        if c.status == "running":
            with connect("B") as b:
                v["pg_duckdb"] = b.execute("SELECT extversion FROM pg_extension "
                                           "WHERE extname = 'pg_duckdb'").fetchone()[0]
                v["pg_duckdb_duckdb"] = b.execute(
                    "SELECT * FROM duckdb.query('SELECT version() AS v')").fetchone()[0]
    except Exception:
        pass
    try:
        if container(C_PG_DUCK_MAIN).status == "running":
            with connect("B2") as b:
                v["pg_duckdb_main"] = b.execute("SELECT extversion FROM pg_extension "
                                                "WHERE extname = 'pg_duckdb'").fetchone()[0]
                v["pg_duckdb_main_duckdb"] = b.execute(
                    "SELECT * FROM duckdb.query('SELECT version() AS v')").fetchone()[0]
    except Exception:
        pass
    try:
        v["clickhouse"] = ch("SELECT version()").strip()
    except Exception:
        pass
    return v
