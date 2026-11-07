#!/usr/bin/env python3
"""headroom.py - how many superseded rows a ReplacingMergeTree carries under continuous upserts,
depending on the CPUs the server has and on min_age_to_force_merge_seconds.

Python 3 stdlib + Docker CLI only. One fresh container per configuration.

    ./headroom.py                         every configuration, newest tag in versions.txt
    ./headroom.py --tag 26.8.36.3         another build
    ./headroom.py --configs 1-off,4-off   only these (<cpus>-<off|force>)
    ./headroom.py --batch 200000          four times the rows per INSERT (same interval)
    ./headroom.py --keys 60000000 --batch 200000 --ingest 120 --idle 240 --payload 4
                                          a table large enough that one merge takes minutes
    ./headroom.py --report-only           rebuild HEADROOM.md from results/headroom-*.json

Workload: KEYS keys loaded once (version 0), then every INTERVAL seconds an INSERT of BATCH rows with
random keys from the same key space and a higher version, for INGEST seconds; then IDLE seconds with no
inserts. Every second: active parts, total rows, running merges. Every key exists, so
superseded rows = total rows - KEYS, read from system.parts (no FINAL, no scan).
At the end of ingest and of idle: the time of SELECT count() FROM t FINAL, then OPTIMIZE TABLE t FINAL.
"""
import argparse, datetime, json, pathlib, subprocess, sys, threading, time

LAB = pathlib.Path(__file__).resolve().parent
ROOT = LAB.parent.parent
SECCOMP = ROOT / "local" / "oss-docker" / "seccomp-profile.json"
RESULTS = LAB / "results"
KEYS, BATCH, INTERVAL, INGEST, IDLE = 2_000_000, 50_000, 0.25, 60, 60
FORCE_AGE = 20
CONFIGS = ["1-off", "1-force", "4-off", "4-force"]


def sh(*cmd, stdin=None, timeout=600):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=timeout)


def others():
    """name -> CPU% of every running container that is not ours, at this moment (docker stats --no-stream)."""
    out = {}
    for l in sh("docker", "stats", "--no-stream", "--format", "{{.Name}} {{.CPUPerc}}").stdout.splitlines():
        n, _, c = l.partition(" ")
        if n and not n.startswith("rmtmv-"):
            try:
                out[n] = float(c.strip().rstrip("%"))
            except ValueError:
                pass
    return out


def newest_tag():
    tags = [l.strip() for l in (LAB / "versions.txt").read_text().splitlines() if l.strip() and not l.startswith("#")]
    return tags[-1]


class Server:
    def __init__(self, tag, cpus):
        self.tag, self.cpus = tag, cpus
        self.name = "rmtmv-headroom-%s" % cpus

    def start(self):
        sh("docker", "rm", "-f", "-v", self.name)
        args = ["docker", "run", "-d", "--name", self.name, "--cpus", str(self.cpus),
                "--ulimit", "nofile=262144:262144",
                "-e", "CLICKHOUSE_PASSWORD=", "-e", "CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1"]
        if SECCOMP.exists():
            args += ["--security-opt", "seccomp=%s" % SECCOMP]
        r = sh(*args, "clickhouse/clickhouse-server:" + self.tag)
        if r.returncode:
            sys.exit("could not start: " + r.stderr)
        for _ in range(90):
            if sh("docker", "exec", self.name, "clickhouse-client", "-q", "SELECT 1").returncode == 0:
                return
            time.sleep(1)
        sys.exit("server did not start")

    def stop(self):
        sh("docker", "rm", "-f", "-v", self.name)

    def q(self, sql, timeout=600):
        t = time.time()
        r = sh("docker", "exec", "-i", self.name, "clickhouse-client", "-n", "--format", "TSV", stdin=sql, timeout=timeout)
        if r.returncode:
            raise RuntimeError(r.stderr.strip()[:300])
        return r.stdout.strip(), time.time() - t


def run_config(tag, cfg, batch, keys=KEYS, ingest=INGEST, idle=IDLE, payload=2):
    cpus, mode = cfg.split("-")
    srv = Server(tag, int(cpus))
    print("== %s, batch %d, on %s" % (cfg, batch, tag), flush=True)
    srv.start()
    try:
        version, _ = srv.q("SELECT version()")
        force = ", min_age_to_force_merge_seconds = %d" % FORCE_AGE if mode == "force" else ""
        srv.q("""CREATE TABLE default.t (k UInt64, ver UInt64, payload String)
                 ENGINE = ReplacingMergeTree(ver) ORDER BY k
                 SETTINGS index_granularity = 8192%s""" % force)
        pay = lambda seed: " || ".join("hex(cityHash64(number, %s, %d))" % (seed, i) for i in range(payload))
        srv.q("INSERT INTO default.t SELECT number, 0, %s FROM numbers(%d) "
              "SETTINGS max_insert_block_size = 1048576, min_insert_block_size_rows = 1048576" % (pay("0"), keys), timeout=3600)
        _, load_optimize_s = srv.q("OPTIMIZE TABLE default.t FINAL", timeout=3600)
        settings, _ = srv.q("SELECT name || '=' || value FROM system.server_settings WHERE name IN "
                            "('background_pool_size', 'background_merges_mutations_concurrency_ratio') ORDER BY name")
        others_start = others()
        samples, inserts, stop = [], [], threading.Event()
        t0 = time.time()

        def inserter():
            seq, nxt = 0, time.time()
            while time.time() - t0 < ingest:
                seq += 1
                sql = ("INSERT INTO default.t SELECT cityHash64(number, %d) %% %d, %d, %s FROM numbers(%d)"
                       % (seq, keys, seq, pay(str(seq + 1)), batch))
                try:
                    _, dt = srv.q(sql)
                    inserts.append(dict(t=round(time.time() - t0, 2), s=round(dt, 3)))
                except RuntimeError as e:
                    inserts.append(dict(t=round(time.time() - t0, 2), error=str(e)))
                nxt += INTERVAL
                time.sleep(max(0, nxt - time.time()))

        def sampler():
            while not stop.is_set():
                try:
                    out, dt = srv.q("SELECT (SELECT count() FROM system.parts WHERE table = 't' AND active), "
                                    "(SELECT sum(rows) FROM system.parts WHERE table = 't' AND active), "
                                    "(SELECT count() FROM system.merges WHERE table = 't')")
                    p, r, m = (int(x) for x in out.split("\t"))
                    samples.append(dict(t=round(time.time() - t0, 1), parts=p, rows=r, superseded=r - keys, merges=m))
                except RuntimeError:
                    pass
                time.sleep(1)

        ti, ts = threading.Thread(target=inserter), threading.Thread(target=sampler)
        ti.start(); ts.start(); ti.join()
        ingest_end = time.time() - t0
        others_mid = others()
        _, final_at_ingest_end = srv.q("SELECT count() FROM default.t FINAL", timeout=3600)
        time.sleep(max(0, ingest_end + idle - (time.time() - t0)))
        stop.set(); ts.join()
        _, final_at_idle_end = srv.q("SELECT count() FROM default.t FINAL", timeout=3600)
        size, _ = srv.q("SELECT sum(data_compressed_bytes) FROM system.parts WHERE table = 't' AND active")
        longest, _ = srv.q("SYSTEM FLUSH LOGS; SELECT max(duration_ms) FROM system.part_log WHERE table = 't' AND event_type = 'MergeParts'")
        _, optimize_s = srv.q("OPTIMIZE TABLE default.t FINAL", timeout=3600)
        written = len([i for i in inserts if "s" in i]) * batch
        data = dict(config=cfg, cpus=int(cpus), force=mode == "force", tag=tag, version=version,
                    date=datetime.date.today().isoformat(), server_settings=settings.splitlines(),
                    keys=keys, batch=batch, interval_s=INTERVAL, ingest_s=ingest, idle_s=idle, payload_hex_chars=16 * payload,
                    compressed_bytes_at_idle_end=int(size or 0), longest_merge_ms=int(longest.split()[-1] or 0),
                    load_optimize_s=round(load_optimize_s, 1),
                    force_age_s=FORCE_AGE if mode == "force" else None,
                    ingest_end_s=round(ingest_end, 1), inserts=inserts, samples=samples,
                    rows_inserted=written, achieved_rows_per_s=round(written / ingest_end),
                    final_count_s_at_ingest_end=round(final_at_ingest_end, 3),
                    final_count_s_at_idle_end=round(final_at_idle_end, 3), optimize_final_s=round(optimize_s, 3),
                    others_cpu_start=others_start, others_cpu_ingest_end=others_mid,
                    docker=dict(ncpu=int(sh("docker", "info", "--format", "{{.NCPU}}").stdout.strip() or 0)))
        RESULTS.mkdir(exist_ok=True)
        name = "headroom-%s-%s-%d" % (tag, cfg, batch) + ("" if keys == KEYS else "-k%d" % keys)
        (RESULTS / (name + ".json")).write_text(json.dumps(data, indent=1) + "\n")
        print("   done: %d rows inserted, %.0f rows/s" % (written, data["achieved_rows_per_s"]), flush=True)
    finally:
        srv.stop()


def at(samples, t):
    best = None
    for s in samples:
        if s["t"] <= t:
            best = s
    return best


def report():
    docs = sorted((json.loads(p.read_text()) for p in RESULTS.glob("headroom-*.json")),
                  key=lambda d: (d["version"], d["keys"], d["batch"], d["cpus"], d["force"]))
    if not docs:
        sys.exit("no results/headroom-*.json")
    d0 = docs[0]
    L = ["# Merge headroom", "",
         "Generated by `headroom.py --report-only` from `results/headroom-*.json`.", "",
         "Workload: `keys` keys loaded once and merged to one part, then an INSERT of `batch` random-key rows every %s s for `ingest` s, "
         "then `idle` s with no inserts. Superseded rows = active rows - keys (`system.parts`). Docker VM: %d CPUs; the server "
         "container is limited with `--cpus`. `force` = table setting `min_age_to_force_merge_seconds = %d`. "
         "`longest merge` = the longest MergeParts in `system.part_log` during the run."
         % (d0["interval_s"], d0["docker"]["ncpu"], FORCE_AGE), ""]
    L += ["| build | keys | config | batch | ingest / idle | run date | rows/s target / achieved | superseded at 30 s | max superseded | max parts | at ingest end | +30 s idle | end of idle (parts) | longest merge | `count() FINAL` at ingest end | `OPTIMIZE FINAL` |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for d in docs:
        sm, e = d["samples"], d["ingest_end_s"]
        f = lambda s: "{:,}".format(s["superseded"]) if s else "-"
        last = sm[-1] if sm else None
        L.append("| %s | %s | %s | %s | %d / %d s | %s | %s / %s | %s | %s | %d | %s | %s | %s (%d) | %s | %.2f s | %.2f s |" % (
            d["version"], "{:,}".format(d["keys"]), d["config"], "{:,}".format(d["batch"]), d["ingest_s"], d["idle_s"], d["date"], "{:,}".format(int(d["batch"] / d["interval_s"])),
            "{:,}".format(d["achieved_rows_per_s"]), f(at(sm, 30)),
            "{:,}".format(max(s["superseded"] for s in sm)), max(s["parts"] for s in sm),
            f(at(sm, e)), f(at(sm, e + 30)), f(last), last["parts"] if last else 0,
            ("%.1f s" % (d["longest_merge_ms"] / 1000)) if "longest_merge_ms" in d else "-",
            d["final_count_s_at_ingest_end"], d["optimize_final_s"]))
    L += ["", "Server settings: " + ", ".join("`%s`" % s for s in d0["server_settings"]), "",
          "Other running containers, CPU% (`docker stats --no-stream`, 100% = one CPU) at the start of ingest / at the end of ingest:", ""]
    for d in docs:
        a, b = d.get("others_cpu_start", {}), d.get("others_cpu_ingest_end", {})
        names = sorted(set(a) | set(b))
        L.append("- %s %s batch %s: %s" % (d["version"], d["config"], "{:,}".format(d["batch"]), ", ".join("`%s` %s / %s" % (n, a.get(n, "-"), b.get(n, "-")) for n in names) or "none"))
    L.append("")
    (LAB / "HEADROOM.md").write_text("\n".join(L) + "\n")
    print("wrote HEADROOM.md")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag")
    ap.add_argument("--configs", default=",".join(CONFIGS))
    ap.add_argument("--batch", type=int, default=BATCH)
    ap.add_argument("--keys", type=int, default=KEYS)
    ap.add_argument("--ingest", type=int, default=INGEST)
    ap.add_argument("--idle", type=int, default=IDLE)
    ap.add_argument("--payload", type=int, default=2, help="16-character hex chunks per row")
    ap.add_argument("--report-only", action="store_true")
    a = ap.parse_args()
    if not a.report_only:
        tag = a.tag or newest_tag()
        for c in a.configs.split(","):
            run_config(tag, c, a.batch, a.keys, a.ingest, a.idle, a.payload)
    report()
