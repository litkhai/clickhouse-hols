#!/usr/bin/env python3
"""scale.py - diff and refresh cost at 1M and 10M records x 25 fields on a ClickHouse Cloud service.

    ./scale.py [--records 1000000 10000000] [--runs 2] [--lean] [--tag -run2] [--env FILE]

The env file (default ~/.config/khai-harness/secrets/clickhouse-seoul.env) holds CH_HOST, CH_USER and
CH_PASSWORD; the password reaches the client through the environment (CLICKHOUSE_PASSWORD) and is never printed. The client is
`clickhouse client` when it is on PATH, otherwise the clickhouse/clickhouse-server image through Docker.

For each size: two snapshots (the base and the next one, 00-setup.sql's generator) are loaded into
snapdiff.raw, then every probe below runs `--runs` times with its own query_id. Duration, read rows and
peak memory come from system.query_log on all replicas, with the replica that ran each query. The usable
memory of every replica is recorded per size, because ClickHouse Cloud autoscaling can change it during a run.
Output: results/scale-<version><tag>.json, rewritten after each step. Applies 00-setup.sql itself; drops
nothing (99-cleanup.sql does).
"""
import argparse, json, os, shutil, subprocess, sys, time, uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
S1, S2 = "2026-11-17 09:00:00", "2026-11-17 10:00:00"
F = ", ".join(f"f{i:02d}" for i in range(1, 26))
CF = ", ".join(f"c.f{i:02d}" for i in range(1, 26))
PF = ", ".join(f"p.f{i:02d}" for i in range(1, 26))
INS = f"INSERT INTO {{t}} (snapshot_id, record_key, {F}, event_timestamp)"
TUPLE_HASH = f"cityHash64(tuple({F}))"
IMG = "clickhouse/clickhouse-server:26.10.3.7"
# the replica's pod suffix (e.g. 5vh6h9e-0), never the full hostname
REPLICA = "replace(hostName(), substring(hostName(), 1, position(hostName(), '-server-') + 7), '')"


def replicas():
    """Each replica's usable memory and max_threads right now (Cloud autoscaling can change them during a run)."""
    out = ch(f"""SELECT {REPLICA}, formatReadableSize(getServerSetting('max_server_memory_usage')), getSetting('max_threads'), uptime()
                 FROM clusterAllReplicas(default, system.one) ORDER BY 1""", retry=True)
    return [l.split("\t") for l in out.splitlines()]


def client_cmd():
    if shutil.which("clickhouse"):
        return ["clickhouse", "client"]
    return ["docker", "run", "--rm", "-i", "-e", "CH_HOST", "-e", "CH_USER", "-e", "CH_PASSWORD", IMG, "clickhouse-client"]


def ch(sql, query_id=None, settings=None, fmt="TSV", retry=False):
    """Run SQL; retry=True retries a read-only call when a replica is being replaced (connection refused)."""
    for attempt in range(6 if retry else 1):
        try:
            return _ch(sql, query_id, settings, fmt)
        except RuntimeError as e:
            if attempt == 5 or not retry or not any(c in str(e) for c in ("Code: 210", "Code: 279", "Code: 209", "Connection refused")):
                raise
            time.sleep(20)


def _ch(sql, query_id=None, settings=None, fmt="TSV"):
    cmd = client_cmd()
    host_args = ["--host", os.environ["CH_HOST"], "--user", os.environ["CH_USER"], "--secure",
                 "--receive_timeout", "3600", "--send_timeout", "3600", "--format", fmt]
    env = dict(os.environ, CLICKHOUSE_PASSWORD=os.environ["CH_PASSWORD"])
    if cmd[0] == "docker":   # the password reaches the container through -e, then the shell
        cmd = cmd[:-1] + ["bash", "-c", 'exec clickhouse-client --password "$CH_PASSWORD" "$@"', "_"]
    # the local client reads CLICKHOUSE_PASSWORD from the environment, so the password never appears in ps
    if query_id:
        host_args += ["--query_id", query_id]
    for k, v in (settings or {}).items():
        host_args += [f"--{k}", str(v)]
    r = subprocess.run(cmd + host_args + ["-n"], input=sql, text=True, capture_output=True, env=env)
    err = "\n".join(l for l in r.stderr.splitlines() if "azure_validate_etag" not in l)
    if r.returncode != 0:
        raise RuntimeError(err.replace(os.environ["CH_HOST"], "<service>")[:800])
    return r.stdout


def log_row(query_id, like=None):
    """query_log row of one query (QueryFinish or an exception), from any replica; waits for the flush."""
    where = f"query_id = '{query_id}'" if query_id else f"query LIKE '{like}'"
    ch("SYSTEM FLUSH LOGS ON CLUSTER default", retry=True)
    for _ in range(40):
        out = ch(f"""SELECT query_duration_ms, read_rows, read_bytes, memory_usage, written_rows, type, exception_code,
                   {REPLICA} AS replica
            FROM clusterAllReplicas(default, system.query_log)
            WHERE event_date = today() AND {where} AND type != 'QueryStart'
            ORDER BY event_time_microseconds DESC LIMIT 1""", fmt="JSONEachRow", retry=True)
        if out.strip():
            return json.loads(out.splitlines()[0])
        time.sleep(3)
    raise RuntimeError(f"no query_log row for {query_id or like}")


def diff_sql(h="row_hash", dedupe=True, table="snapdiff.raw"):
    lb = " LIMIT 1 BY record_key" if dedupe else ""
    return f"""SELECT * FROM (
    SELECT 'n' AS k, if(p.in_prev = 0, 'new', 'changed') AS change_type, c.record_key, {CF}
    FROM (SELECT record_key, {h} AS h, {F} FROM {table} WHERE snapshot_id = '{S2}'{lb}) AS c
    LEFT JOIN (SELECT record_key, {h} AS prev_h, 1 AS in_prev FROM {table} WHERE snapshot_id = '{S1}'{lb}) AS p USING (record_key)
    WHERE p.in_prev = 0 OR c.h != p.prev_h
    UNION ALL
    SELECT 'd', 'deleted', p.record_key, {PF}
    FROM (SELECT record_key, {F} FROM {table} WHERE snapshot_id = '{S1}'{lb}) AS p
    LEFT ANTI JOIN (SELECT DISTINCT record_key FROM {table} WHERE snapshot_id = '{S2}') AS c USING (record_key)
) FORMAT Null"""


GROUPBY_SQL = f"""SELECT change_type, count() FROM (
    SELECT record_key,
           multiIf(countIf(snapshot_id = '{S1}') = 0, 'new', countIf(snapshot_id = '{S2}') = 0, 'deleted',
                   anyIf(row_hash, snapshot_id = '{S2}') != anyIf(row_hash, snapshot_id = '{S1}'), 'changed', 'same') AS change_type
    FROM snapdiff.raw WHERE snapshot_id IN ('{S1}', '{S2}') GROUP BY record_key)
WHERE change_type != 'same' GROUP BY change_type FORMAT Null"""


def probe(results, size, name, sql, runs, settings=None):
    rows = []
    for i in range(runs):
        qid = f"snapdiff-{size}-{name}-{i}-{uuid.uuid4().hex[:8]}"
        try:
            ch(sql, query_id=qid, settings=settings)
        except RuntimeError as e:
            code = next((l for l in str(e).splitlines() if "Code:" in l), str(e).splitlines()[0])
            print(f"  {name}: error {code[:160]}", flush=True)
        try:
            r = log_row(qid)
        except RuntimeError as e:   # the query never reached query_log (its replica went away)
            rows.append({"error": str(e)[:200]})
            print(f"  {name} run {i + 1}: no query_log row", flush=True)
            continue
        rows.append(r)
        print(f"  {name} run {i + 1}: {int(r['query_duration_ms']) / 1000:.2f} s, read {int(r['read_rows']):,} rows, "
              f"peak {int(r['memory_usage']) / 2**20:,.0f} MiB, exception {r['exception_code']}, replica {r['replica']}", flush=True)
    results.append({"records": size, "probe": name, "settings": settings or {}, "runs": rows})


TWO_STEP = f"""SELECT r.snapshot_id, k.change_type, r.record_key, {', '.join(f'r.f{i:02d}' for i in range(1, 26))}
FROM (SELECT snapshot_id, record_key, {F} FROM {{t}} WHERE snapshot_id IN ('{S1}', '{S2}')) AS r
INNER JOIN
(
    SELECT record_key,
           multiIf(countIf(snapshot_id = '{S1}') = 0, 'new', countIf(snapshot_id = '{S2}') = 0, 'deleted',
                   anyIf(row_hash, snapshot_id = '{S2}') != anyIf(row_hash, snapshot_id = '{S1}'), 'changed', 'same') AS change_type
    FROM {{t}} WHERE snapshot_id IN ('{S1}', '{S2}')
    GROUP BY record_key
    HAVING change_type != 'same'
) AS k USING (record_key)
WHERE (r.snapshot_id = '{S2}' AND k.change_type IN ('new', 'changed')) OR (r.snapshot_id = '{S1}' AND k.change_type = 'deleted')
LIMIT 1 BY r.record_key
FORMAT Null"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--records", type=int, nargs="+", default=[1_000_000, 10_000_000])
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--lean", action="store_true", help="skip the three JOIN variants (hash at query time, no LIMIT 1 BY, full_sorting_merge)")
    ap.add_argument("--tag", default="", help="suffix for the output file")
    ap.add_argument("--resume", action="store_true",
                    help="keep the loaded snapshots and start at the two-step diff (after a run broke off; use one --records value)")
    ap.add_argument("--env", default=str(Path.home() / ".config/khai-harness/secrets/clickhouse-seoul.env"))
    a = ap.parse_args()
    for line in Path(a.env).read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            os.environ[k.strip().removeprefix("export ").strip()] = v.strip().strip('"').strip("'")
    version = ch("SELECT version()", retry=True).strip()
    meta = {
        "date": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "version": version,
        "replicas_at_start": replicas(),
        "join_algorithm": ch("SELECT getSetting('join_algorithm')", retry=True).strip(),
        "args": vars(a) | {"env": "<env file>"},
    }
    print(meta, flush=True)
    out = HERE / "results" / f"scale-{version}{a.tag}.json"
    out.parent.mkdir(exist_ok=True)
    results = []
    save = lambda: out.write_text(json.dumps({"meta": meta, "results": results}, indent=1) + "\n")
    ch((HERE / "00-setup.sql").read_text())
    guard = (HERE / "04-rmv.sql").read_text()
    rmv = guard[guard.index("CREATE MATERIALIZED VIEW snapdiff.diff_rmv\n"):guard.index("CREATE MATERIALIZED VIEW snapdiff.diff_rmv_naive")]
    for n in a.records:
        print(f"== {n:,} records", flush=True)
        results.append({"records": n, "probe": "replicas", "replicas": replicas()})
        if not a.resume:
          ch("""DROP VIEW IF EXISTS snapdiff.diff_rmv; DROP VIEW IF EXISTS snapdiff.diff_rmv_naive;
              DROP VIEW IF EXISTS snapdiff.mv_detect; DROP VIEW IF EXISTS snapdiff.mv_state;
              DROP TABLE IF EXISTS snapdiff.raw_bykey; DROP TABLE IF EXISTS snapdiff.state; DROP TABLE IF EXISTS snapdiff.changes_mv;
              DROP TABLE IF EXISTS snapdiff.raw_plain;
              TRUNCATE TABLE snapdiff.raw; TRUNCATE TABLE snapdiff.manifest; TRUNCATE TABLE snapdiff.changes;""")
        for v, sid in (() if a.resume else ((0, S1), (1, S2))):
            probe(results, n, f"load snapshot v{v}",
                  f"{INS.format(t='snapdiff.raw')} SELECT * FROM snapdiff.gen(n = {n}, v = {v}, sid = '{sid}')", 1)
        size = ch("""SELECT partition, sum(rows), sum(data_compressed_bytes), sum(data_uncompressed_bytes)
                     FROM system.parts WHERE database = 'snapdiff' AND table = 'raw' AND active GROUP BY partition ORDER BY partition""", retry=True)
        results.append({"records": n, "probe": "raw size", "parts": [l.split("\t") for l in size.splitlines()]})
        print("  raw size:", size.replace("\n", " | "), flush=True)
        truth = ch(f"""SELECT countIf(number >= {n}), countIf(number < {n} AND number % 1000 >= 3 AND (number % 100 = 7 OR number % 100000 = 11)),
                       countIf(number < {n} AND number % 1000 < 3) FROM numbers({n} + intDiv({n}, 200))""").split()
        results.append({"records": n, "probe": "truth", "new_changed_deleted": truth})
        save()

        if not a.resume:
            probe(results, n, "diff JOIN, row_hash column", diff_sql(), a.runs)
        if not a.lean and not a.resume:
            probe(results, n, "diff JOIN, hash at query time", diff_sql(h=TUPLE_HASH), a.runs)
            probe(results, n, "diff JOIN, no LIMIT 1 BY", diff_sql(dedupe=False), a.runs)
            probe(results, n, "diff JOIN, full_sorting_merge (anti join: hash)", diff_sql(), a.runs, settings={"join_algorithm": "full_sorting_merge,hash"})
        if not a.resume:
            probe(results, n, "classify GROUP BY, keys only", GROUPBY_SQL, a.runs)
        probe(results, n, "diff two-step: GROUP BY keys, then JOIN the changed keys", TWO_STEP.format(t="snapdiff.raw"), a.runs)
        probe(results, n, "guard: uniqExact(record_key) of one snapshot",
              f"SELECT uniqExact(record_key) FROM snapdiff.raw WHERE snapshot_id = '{S2}' FORMAT Null", a.runs)
        save()

        # the layout of a plain sink table: ORDER BY record_key, no partition (every read scans both snapshots)
        ch("DROP TABLE IF EXISTS snapdiff.raw_bykey; DROP VIEW IF EXISTS snapdiff.diff_rmv; TRUNCATE TABLE snapdiff.manifest; TRUNCATE TABLE snapdiff.changes;")
        ch(f"""CREATE TABLE snapdiff.raw_bykey AS snapdiff.raw ENGINE = MergeTree PARTITION BY tuple() ORDER BY record_key;
               INSERT INTO snapdiff.raw_bykey (snapshot_id, record_key, {F}, event_timestamp, ingestion_timestamp)
               SELECT snapshot_id, record_key, {F}, event_timestamp, ingestion_timestamp FROM snapdiff.raw;""")
        probe(results, n, "diff two-step, raw ORDER BY record_key without partitions", TWO_STEP.format(t="snapdiff.raw_bykey"), a.runs)
        ch("DROP TABLE snapdiff.raw_bykey")
        save()

        # the refreshable MV (04-rmv.sql): baseline at CREATE, then one refresh that compares, then one with nothing to do
        ch(f"""INSERT INTO snapdiff.manifest (snapshot_id, expected_rows) SELECT '{S1}', {n};
               INSERT INTO snapdiff.manifest (snapshot_id, expected_rows) SELECT '{S2}', {n - 3 * n // 1000 + n // 200};""")
        ch(rmv.strip().rstrip(";") + ";\nSYSTEM WAIT VIEW snapdiff.diff_rmv;")
        for name in ("refresh: compare", "refresh: nothing to do"):
            t0 = ch("SELECT now64(3)").strip()
            ch("SYSTEM REFRESH VIEW snapdiff.diff_rmv; SYSTEM WAIT VIEW snapdiff.diff_rmv;")
            ch("SYSTEM FLUSH LOGS ON CLUSTER default", retry=True)
            for _ in range(40):
                o = ch(f"""SELECT query_duration_ms, read_rows, read_bytes, memory_usage, written_rows, type, exception_code, {REPLICA} AS replica
                    FROM clusterAllReplicas(default, system.query_log)
                    WHERE event_date = today() AND event_time_microseconds >= '{t0}' AND type != 'QueryStart'
                      AND query LIKE 'INSERT INTO snapdiff.changes %' ORDER BY event_time_microseconds DESC LIMIT 1""", fmt="JSONEachRow", retry=True)
                if o.strip():
                    break
                time.sleep(3)
            r = json.loads(o.splitlines()[0])
            results.append({"records": n, "probe": name, "runs": [r]})
            print(f"  {name}: {int(r['query_duration_ms']) / 1000:.2f} s, read {int(r['read_rows']):,}, "
                  f"peak {int(r['memory_usage']) / 2**20:,.0f} MiB, wrote {int(r['written_rows']):,}, exception {r['exception_code']}, replica {r['replica']}", flush=True)
        counts = ch("SELECT change_type, count() FROM snapdiff.changes GROUP BY change_type ORDER BY change_type", retry=True)
        results.append({"records": n, "probe": "changes after refresh", "counts": [l.split("\t") for l in counts.splitlines()]})
        print("  changes:", counts.replace("\n", " | "), flush=True)
        ch("DROP VIEW snapdiff.diff_rmv")
        save()

        # insert-time MVs (05-insert-mv.sql): the next snapshot in 10 inserts; one tenth into a table without MVs for comparison
        mv = (HERE / "05-insert-mv.sql").read_text()
        ch(mv[mv.index("CREATE TABLE snapdiff.state"):mv.index("SELECT name, value FROM system.settings")])
        ch(f"INSERT INTO snapdiff.state SELECT record_key, row_hash, snapshot_id FROM snapdiff.raw WHERE snapshot_id = '{S1}'")
        ch("CREATE TABLE snapdiff.raw_plain AS snapdiff.raw")
        probe(results, n, "insert 1/10 of a snapshot, no MV",
              f"{INS.format(t='snapdiff.raw_plain')} SELECT * FROM snapdiff.gen(n = {n}, v = 1, sid = '{S2}') WHERE cityHash64(record_key) % 10 = 0", 1)
        ch(f"ALTER TABLE snapdiff.raw DROP PARTITION '{S2}'")
        ins = []
        for b in range(10):
            qid = f"snapdiff-{n}-mvinsert-{b}-{uuid.uuid4().hex[:8]}"
            try:
                ch(f"{INS.format(t='snapdiff.raw')} SELECT * FROM snapdiff.gen(n = {n}, v = 1, sid = '{S2}') WHERE cityHash64(record_key) % 10 = {b}", query_id=qid)
            except RuntimeError as e:
                print(f"  insert with MVs {b}: error {next((l for l in str(e).splitlines() if 'Code:' in l), '')[:160]}", flush=True)
            ins.append(log_row(qid))
        d = [int(r["query_duration_ms"]) / 1000 for r in ins]; m = [int(r["memory_usage"]) / 2**20 for r in ins]
        results.append({"records": n, "probe": "insert 1/10 of a snapshot, with the two insert-time MVs", "runs": ins})
        print(f"  insert with MVs: {min(d):.2f}-{max(d):.2f} s per tenth, peak {max(m):,.0f} MiB, exceptions {[r['exception_code'] for r in ins]}", flush=True)
        counts = ch("SELECT change_type, count() FROM snapdiff.changes_mv GROUP BY change_type ORDER BY change_type", retry=True)
        results.append({"records": n, "probe": "changes_mv after insert", "counts": [l.split("\t") for l in counts.splitlines()]})
        print("  changes_mv:", counts.replace("\n", " | "), flush=True)
        ch("DROP VIEW snapdiff.mv_detect; DROP VIEW snapdiff.mv_state; DROP TABLE snapdiff.state; DROP TABLE snapdiff.changes_mv; DROP TABLE snapdiff.raw_plain")
        results.append({"records": n, "probe": "replicas at the end", "replicas": replicas()})
        save()
    print(f"wrote {out.relative_to(HERE)}")


if __name__ == "__main__":
    sys.exit(main())
