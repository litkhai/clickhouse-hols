#!/usr/bin/env python3
"""race.py - a partition rebuild (design D) while the MV keeps writing into the same partition.

Python 3 stdlib + Docker CLI only. One fresh container (rmtmv-race), removed at the end.

    ./race.py                   newest tag in versions.txt
    ./race.py --tag 26.8.36.3   another build
    ./race.py --report-only     rebuild RACE.md from results/race-*.json

Setup: orders (ReplacingMergeTree(ver)), a per-day SummingMergeTree target partitioned by day, fed by an MV.
A writer inserts WRITE_ROWS new orders (new keys, amount 1) every WRITE_EVERY s for WRITE_S s:
half for the active day, and, in the first half of the run only, late corrections for the closed day.
Meanwhile a rebuilder runs REBUILDS times, alternating between the two days:
    INSERT INTO stage SELECT … FROM orders FINAL WHERE day = d
    ALTER TABLE target REPLACE PARTITION d FROM stage
After the writer stops: target vs source FINAL per day, for the two days. Then one more rebuild of each day
with no writer running (the control), and the same comparison again.
"""
import argparse, datetime, json, pathlib, subprocess, sys, threading, time

LAB = pathlib.Path(__file__).resolve().parent
ROOT = LAB.parent.parent
SECCOMP = ROOT / "local" / "oss-docker" / "seccomp-profile.json"
RESULTS = LAB / "results"
NAME = "rmtmv-race"
WRITE_ROWS, WRITE_EVERY, WRITE_S, REBUILDS = 2000, 0.05, 60, 40
ACTIVE, CLOSED = "2026-11-02", "2026-11-01"


def sh(*cmd, stdin=None, timeout=600):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=timeout)


def q(sql):
    t = time.time()
    r = sh("docker", "exec", "-i", NAME, "clickhouse-client", "-n", "--format", "TSV", stdin=sql)
    if r.returncode:
        raise RuntimeError(r.stderr.strip()[:300])
    return r.stdout.strip(), time.time() - t


def newest_tag():
    return [l.strip() for l in (LAB / "versions.txt").read_text().splitlines() if l.strip() and not l.startswith("#")][-1]


def start(tag):
    sh("docker", "rm", "-f", "-v", NAME)
    args = ["docker", "run", "-d", "--name", NAME, "--ulimit", "nofile=262144:262144",
            "-e", "CLICKHOUSE_PASSWORD=", "-e", "CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1"]
    if SECCOMP.exists():
        args += ["--security-opt", "seccomp=%s" % SECCOMP]
    if sh(*args, "clickhouse/clickhouse-server:" + tag).returncode:
        sys.exit("could not start")
    for _ in range(90):
        if sh("docker", "exec", NAME, "clickhouse-client", "-q", "SELECT 1").returncode == 0:
            return
        time.sleep(1)
    sys.exit("server did not start")


SETUP = """
DROP DATABASE IF EXISTS rmt_mv;
CREATE DATABASE rmt_mv;
CREATE TABLE rmt_mv.orders (order_id UInt64, day Date, amount UInt64, ver UInt64)
ENGINE = ReplacingMergeTree(ver) ORDER BY order_id;
CREATE TABLE rmt_mv.daily_part (day Date, orders UInt64, amount UInt64)
ENGINE = SummingMergeTree PARTITION BY day ORDER BY day;
CREATE MATERIALIZED VIEW rmt_mv.daily_part_mv TO rmt_mv.daily_part AS
SELECT day, count() AS orders, sum(amount) AS amount FROM rmt_mv.orders GROUP BY day;
CREATE TABLE rmt_mv.stage AS rmt_mv.daily_part;
INSERT INTO rmt_mv.orders SELECT number, if(number %% 2 = 0, toDate('%s'), toDate('%s')), 1, 1 FROM numbers(100000);
""" % (CLOSED, ACTIVE)


def compare():
    out, _ = q("""SELECT d, src_orders, src_amount, tgt_orders, tgt_amount FROM
        (SELECT day AS d, count() AS src_orders, sum(amount) AS src_amount FROM rmt_mv.orders FINAL GROUP BY day) AS s
        LEFT JOIN (SELECT day AS d, sum(orders) AS tgt_orders, sum(amount) AS tgt_amount FROM rmt_mv.daily_part GROUP BY day) AS t USING d
        ORDER BY d""")
    rows = {}
    for l in out.splitlines():
        d, so, sa, to, ta = l.split("\t")
        rows[d] = dict(source_orders=int(so), source_amount=int(sa), target_orders=int(to), target_amount=int(ta),
                       diff_amount=int(ta) - int(sa))
    return rows


def rebuild(day):
    t = time.time()
    q("INSERT INTO rmt_mv.stage SELECT day, count(), sum(amount) FROM rmt_mv.orders FINAL WHERE day = '%s' GROUP BY day" % day)
    q("ALTER TABLE rmt_mv.daily_part REPLACE PARTITION '%s' FROM rmt_mv.stage" % day)
    q("TRUNCATE TABLE rmt_mv.stage")
    return round(time.time() - t, 3)


def run(tag):
    start(tag)
    try:
        version, _ = q("SELECT version()")
        q(SETUP)
        before = compare()
        stop, writes, rebuilds = threading.Event(), [], []
        t0 = time.time()

        def writer():
            seq, nxt = 0, time.time()
            while time.time() - t0 < WRITE_S:
                seq += 1
                late = time.time() - t0 < WRITE_S / 2
                # new active-day orders; in the first half also late corrections (amount 1 -> 3) of closed-day orders
                sql = ("INSERT INTO rmt_mv.orders SELECT 1000000 + %d * %d + number, toDate('%s'), 1, 1 FROM numbers(%d)"
                       % (seq, WRITE_ROWS, ACTIVE, WRITE_ROWS // 2))
                q(sql)
                if late:
                    # closed-day keys are the even numbers below 100000
                    q("INSERT INTO rmt_mv.orders SELECT ((%d * 997 + number) %% 50000) * 2, toDate('%s'), 3, 1 + %d FROM numbers(%d)"
                      % (seq, CLOSED, seq, WRITE_ROWS // 2))
                writes.append(dict(t=round(time.time() - t0, 2), late=late))
                nxt += WRITE_EVERY
                time.sleep(max(0, nxt - time.time()))

        def rebuilder():
            for i in range(REBUILDS):
                if stop.is_set():
                    break
                day = ACTIVE if i % 2 == 0 else CLOSED
                rebuilds.append(dict(t=round(time.time() - t0, 2), day=day, s=rebuild(day)))
                time.sleep(WRITE_S / REBUILDS)

        tw = threading.Thread(target=writer); tr = threading.Thread(target=rebuilder)
        tw.start(); tr.start(); tw.join(); stop.set(); tr.join()
        time.sleep(2)
        after_race = compare()
        control = [dict(day=d, s=rebuild(d)) for d in (CLOSED, ACTIVE)]
        after_control = compare()
        data = dict(tag=tag, version=version, date=datetime.date.today().isoformat(),
                    write_rows=WRITE_ROWS, write_every_s=WRITE_EVERY, write_s=WRITE_S, rebuilds_planned=REBUILDS,
                    writes=len(writes), rebuild_runs=rebuilds, before=before, after_race=after_race,
                    control_rebuilds=control, after_control=after_control)
        RESULTS.mkdir(exist_ok=True)
        (RESULTS / ("race-%s.json" % tag)).write_text(json.dumps(data, indent=1) + "\n")
        print("   %s: %d writes, %d rebuilds" % (version, len(writes), len(rebuilds)), flush=True)
    finally:
        sh("docker", "rm", "-f", "-v", NAME)


def report():
    docs = sorted((json.loads(p.read_text()) for p in RESULTS.glob("race-*.json")),
                  key=lambda d: [int(x) for x in d["version"].split(".")])
    if not docs:
        sys.exit("no results/race-*.json")
    d0 = docs[0]
    L = ["# Partition rebuild racing the MV", "", "Generated by `race.py --report-only` from `results/race-*.json`.", "",
         "A writer inserts %s new active-day orders every %s s (a target; `writes` = how many it managed) for %d s (amount 1 each), and during the first half also %s late "
         "corrections of closed-day orders (amount 1 → 3, higher version). A rebuilder alternates `INSERT INTO stage SELECT … FROM orders "
         "FINAL WHERE day = d` + `REPLACE PARTITION d FROM stage` between the two days, %d times planned. Then the writer stops; then "
         "one rebuild of each day with no writer (control). `diff` = target amount − source `FINAL` amount."
         % ("{:,}".format(d0["write_rows"] // 2), d0["write_every_s"], d0["write_s"], "{:,}".format(d0["write_rows"] // 2), d0["rebuilds_planned"]), "",
         "| build | run date | writes | rebuilds | day | source `FINAL` orders · amount | target after the race | diff | after control rebuild | diff |",
         "|---|---|---|---|---|---|---|---|---|---|"]
    for d in docs:
        for day, name in ((CLOSED, "closed " + CLOSED), (ACTIVE, "active " + ACTIVE)):
            a, c = d["after_race"][day], d["after_control"][day]
            L.append("| %s | %s | %d | %d | %s | %s · %s | %s · %s | %s | %s · %s | %s |" % (
                d["version"], d["date"], d["writes"], len(d["rebuild_runs"]), name,
                "{:,}".format(a["source_orders"]), "{:,}".format(a["source_amount"]),
                "{:,}".format(a["target_orders"]), "{:,}".format(a["target_amount"]), "{:+,}".format(a["diff_amount"]),
                "{:,}".format(c["target_orders"]), "{:,}".format(c["target_amount"]), "{:+,}".format(c["diff_amount"])))
    L.append("")
    for d in docs:
        rs = [r["s"] for r in d["rebuild_runs"]]
        L.append("- %s: rebuild time median %.2f s, max %.2f s" % (d["version"], sorted(rs)[len(rs) // 2], max(rs)))
    (LAB / "RACE.md").write_text("\n".join(L) + "\n")
    print("wrote RACE.md")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag")
    ap.add_argument("--report-only", action="store_true")
    a = ap.parse_args()
    if not a.report_only:
        run(a.tag or newest_tag())
    report()
