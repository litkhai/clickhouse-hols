#!/usr/bin/env python3
"""Drive mcp-clickhouse over stdio as user ai_reader, with no AI in the loop.

Checks (each prints PASS/FAIL against an expectation):
  1. tools the server exposes; list_tables on fileidx shows the view, not the base table
  2. SELECT on the view succeeds (positive control)
  3. SELECT on the base table, INSERT, DROP, CREATE fail (negative controls)
  4. an unbounded SELECT hits max_result_rows
  5. timeout: with CLICKHOUSE_MCP_QUERY_TIMEOUT=3 a ~12 s query returns an error after ~3 s;
     system.query_log then shows whether the server-side query was cancelled or ran on
  6. concurrency: three ~3 s queries sent at once; wall time vs one query
Reads connection values from work/.lab.env (written by run.sh).
"""
import asyncio, json, os, subprocess, sys, time
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

HERE = Path(__file__).resolve().parent
ENV = dict(l.split("=", 1) for l in (HERE / "work/.lab.env").read_text().split() if "=" in l)
SLOW = "SELECT count() FROM fileidx.files AS a CROSS JOIN fileidx.files AS b WHERE cityHash64(a.path, b.path) % 3 = 0"
MEDIUM = "SELECT count() FROM fileidx.files AS a CROSS JOIN fileidx.files AS b WHERE a.size > b.size"
fails = 0


def server(**extra):
    env = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"],
           "CLICKHOUSE_HOST": ENV["CH_HOST"], "CLICKHOUSE_PORT": ENV["CH_PORT"],
           "CLICKHOUSE_USER": "ai_reader", "CLICKHOUSE_PASSWORD": ENV["AI_PW"],
           "CLICKHOUSE_SECURE": "false", **extra}
    return StdioServerParameters(command="uvx", args=["--python", "3.12", f"mcp-clickhouse=={ENV['MCP_VERSION']}"], env=env)


def text(res):
    return " ".join(getattr(c, "text", "") for c in res.content).strip()


def is_error(res):
    return bool(getattr(res, "isError", getattr(res, "is_error", False)))


def check(label, ok, detail):
    global fails
    fails += 0 if ok else 1
    print(f"{'PASS' if ok else 'FAIL'}  {label}\n      {detail[:300]}")


def admin(q):
    return subprocess.run(["docker", "exec", "fileidx-ch", "clickhouse-client", "--password", ENV["ADMIN_PW"], "-q", q],
                          capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout.strip()


async def call(s, sql):
    t = time.time()
    r = await s.call_tool("run_query", {"query": sql})
    return r, round(time.time() - t, 1)


async def main():
    async with stdio_client(server(), errlog=open(os.devnull, "w")) as (rd, wr):
        async with ClientSession(rd, wr) as s:
            await s.initialize()
            tools = sorted(t.name for t in (await s.list_tools()).tools)
            check("tools exposed", tools == ["list_databases", "list_tables", "run_query"], str(tools))
            r = await s.call_tool("list_tables", {"database": "fileidx"})
            names = [t.get("name") for t in json.loads(text(r)).get("tables", [])] if not is_error(r) else []
            check("list_tables fileidx shows only what ai_reader may read", names == ["files"], f"names={names} raw={text(r)[:120]}")

            r, _ = await call(s, "SELECT count() AS files, formatReadableSize(sum(size)) AS total FROM fileidx.files")
            check("SELECT on the view", not is_error(r), text(r))
            for label, sql in [("SELECT on the base table", "SELECT count() FROM fileidx.file_index"),
                               ("INSERT", "INSERT INTO fileidx.file_index (root, path, name, ext, size, mtime, is_dir, depth, scan_id) VALUES ('x','x','x','',0,now(),0,0,0)"),
                               ("DROP TABLE", "DROP TABLE fileidx.file_index"),
                               ("CREATE TABLE", "CREATE TABLE default.t (x UInt8) ENGINE = Memory"),
                               ("unbounded SELECT of every path", "SELECT root, path FROM fileidx.files")]:
                r, _ = await call(s, sql)
                check(f"{label} fails", is_error(r), text(r))
            print("      base table still there: rows =", admin("SELECT count() FROM fileidx.file_index"))

            # 6. concurrency, on this server (default CLICKHOUSE_MCP_MAX_WORKERS)
            _, one = await call(s, MEDIUM)
            t = time.time()
            await asyncio.gather(*(call(s, MEDIUM) for _ in range(3)))
            three = round(time.time() - t, 1)
            check("three concurrent calls finish faster than three sequential ones", three < 3 * one * 0.8,
                  f"one call {one} s, three at once {three} s")

    # 5. timeout
    async with stdio_client(server(CLICKHOUSE_MCP_QUERY_TIMEOUT="3"), errlog=open(os.devnull, "w")) as (rd, wr):
        async with ClientSession(rd, wr) as s:
            await s.initialize()
            r, took = await call(s, SLOW + " /* timeout-probe */")
            check("MCP returns an error at its 3 s timeout", is_error(r) and took < 8, f"{took} s: {text(r)}")
            time.sleep(15)
            admin("SYSTEM FLUSH LOGS")
            row = admin("SELECT type, query_duration_ms, exception_code, substring(exception, 1, 80) FROM system.query_log "
                        "WHERE user = 'ai_reader' AND query LIKE '%timeout-probe%' AND type != 'QueryStart' AND query NOT LIKE '%system.query_log%' "
                        "ORDER BY event_time_microseconds DESC LIMIT 1")
            kill = admin("SELECT type, exception_code, substring(exception, 1, 80) FROM system.query_log WHERE user = 'ai_reader' "
                         "AND query LIKE 'KILL QUERY%' ORDER BY event_time_microseconds DESC LIMIT 1")
            check("server-side query was cancelled, not left running (query_log)", "QUERY_WAS_CANCELLED" in row or " 394\t" in row,
                  f"query: {row} | KILL QUERY: {kill or 'not in query_log'}")
    # positive control for the timeout: same query with the default 30 s timeout completes
    async with stdio_client(server(), errlog=open(os.devnull, "w")) as (rd, wr):
        async with ClientSession(rd, wr) as s:
            await s.initialize()
            r, took = await call(s, SLOW)
            check("the same query completes under the default 30 s timeout", not is_error(r), f"{took} s: {text(r)[:120]}")
    print(f"\n{fails} failed")
    sys.exit(1 if fails else 0)


asyncio.run(main())
