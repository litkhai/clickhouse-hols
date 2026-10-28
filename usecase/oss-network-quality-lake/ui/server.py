#!/usr/bin/env python3
"""OSS network-quality lake — local demo server (Python stdlib only).

    python3 ui/server.py                 serve the explainer at / and the demo at /demo
    python3 ui/server.py --snapshot      write site/data/snapshot.json from ClickHouse
    python3 ui/server.py --record 6      press the live feed 6 times, write site/data/replay.json

Fixed endpoints only, no free SQL:
    GET  /api/layers      row count, size and a sample row per layer
    GET  /api/q/<1-4>     the NOC query on bronze, silver, gold or serving
    GET  /api/map         the 20 cells and a density background, as H3 boundaries
    GET  /api/usecases    analysis, dashboard series, alerts, an HTTP-streaming sample
    POST /api/tick        live feed: one more minute of traces into bronze

Reads use the read-only user oss_reader (CH_READ_USER, CH_READ_PASSWORD); only /api/tick writes
(CH_WRITE_USER). ClickHouse: CH_URL (default http://localhost:18123). Listen: PORT (default 8765).
api/index.py serves the same GET endpoints from a Vercel function, read-only, with FEED=auto.
"""
import argparse, json, os, pathlib, platform, statistics, subprocess, sys, threading, time
import urllib.parse, urllib.request
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

LAB = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(LAB / "site"))

CH_URL = os.environ.get("CH_URL", "http://localhost:18123")
READ_USER = os.environ.get("CH_READ_USER", "oss_reader")
READ_PASSWORD = os.environ.get("CH_READ_PASSWORD", "")
# "button": the local live demo sends each minute; "auto": the lake feeds itself (cloud/feed.sql)
FEED = os.environ.get("FEED", "button")
WRITE_USER = os.environ.get("CH_WRITE_USER", "default")
WRITE_PASSWORD = os.environ.get("CH_WRITE_PASSWORD", "")

LAYERS = [
    # key, table, NOC view
    ("bronze", "ue_trace_raw", "noc_from_bronze"),
    ("silver", "ue_trace", "noc_from_silver"),
    ("gold", "cell_kpi_1m", "noc_from_gold"),
    ("serving", "cell_rank_now", "noc_from_serving"),
]
WINDOW = "bucket >= t - INTERVAL 1 HOUR AND bucket < t"
ANCHOR = "(SELECT max(anchor_ts) FROM oss_lake.params)"
# event_ts is DateTime64(3): compare it with a DateTime64 bound (03-queries.sql explains why)
ANCHOR64 = "toDateTime64(%s, 3)" % ANCHOR


def ch(sql, user=READ_USER, password=None, fmt="JSON", settings=None):
    """Run one statement over HTTP; return (parsed JSON or None, summary dict).
    Credentials travel in headers, never in the URL."""
    params = {"default_format": fmt}
    params.update(settings or {})
    password = READ_PASSWORD if password is None else password
    req = urllib.request.Request(CH_URL + "/?" + urllib.parse.urlencode(params),
                                 data=sql.encode(), method="POST",
                                 headers={"X-ClickHouse-User": user, "X-ClickHouse-Key": password})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            body = r.read()
            summary = json.loads(r.headers.get("X-ClickHouse-Summary") or "{}")
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode(errors="replace").strip()[:400]) from None
    return (json.loads(body) if body.strip() and fmt == "JSON" else None), summary


def rows(sql, **kw):
    return ch(sql, **kw)[0]["data"]


def write(sql):
    return ch(sql, user=WRITE_USER, password=WRITE_PASSWORD, fmt="TSV")


# ---------------------------------------------------------------- reads

def counts():
    """Row count and bytes on disk per layer, plus the anchor."""
    sizes = {r["table"]: r for r in rows(
        "SELECT table, sum(rows) AS rows, sum(bytes_on_disk) AS bytes FROM system.parts "
        "WHERE database = 'oss_lake' AND active GROUP BY table")}
    out = []
    for key, table, _ in LAYERS:
        n = rows("SELECT count() AS n FROM oss_lake.%s" % table)[0]["n"]
        out.append({"key": key, "table": table, "rows": int(n),
                    "bytes": int(sizes.get(table, {}).get("bytes", 0))})
    anchor = rows("SELECT toString(max(anchor_ts)) AS t FROM oss_lake.params")[0]["t"]
    return {"anchor_ts": anchor, "layers": out, "feed": FEED}


def story():
    """One measurement followed through the layers: it is taken from the cell that
    ranks first by users, in the last minute before the anchor."""
    top = rows("SELECT cell, h3ToString(cell) AS cell_str FROM oss_lake.cell_rank_now "
               "WHERE list = 'users' AND rnk = 1")[0]
    raw = rows(
        "SELECT event_ts, h3_res09, imsi, rsrp, rsrq, sinr, cqi, pci, probe "
        "FROM oss_lake.ue_trace_raw WHERE h3_res09 = '%s' AND rsrp IS NOT NULL "
        "AND event_ts >= %s - INTERVAL 1 MINUTE AND event_ts < %s ORDER BY event_ts LIMIT 1"
        % (top["cell_str"], ANCHOR64, ANCHOR64))[0]
    silver = rows(
        "SELECT event_ts, h3, imsi_hash, rsrp, rsrq, sinr, cqi, region1, region2 "
        "FROM oss_lake.ue_trace WHERE event_ts = toDateTime64('%s', 3) AND h3 = stringToH3('%s') "
        "AND imsi_hash = cityHash64('%s') LIMIT 1" % (raw["event_ts"], raw["h3_res09"], raw["imsi"]))[0]
    gold = rows(
        "SELECT bucket, cell, finalizeAggregation(users_st) AS users_st, "
        "samples_n, rsrp_n, rsrp_sum, poor_n "
        "FROM oss_lake.cell_kpi_1m FINAL WHERE bucket = toStartOfMinute(toDateTime64('%s', 3)) "
        "AND cell = %s" % (raw["event_ts"], silver["h3"]))[0]
    folded = rows(
        "SELECT count() AS n FROM oss_lake.ue_trace WHERE h3 = %s "
        "AND toStartOfMinute(event_ts) = toDateTime('%s')" % (silver["h3"], gold["bucket"]))[0]["n"]
    # The last minute only: with the always-on feed bronze holds one to two days, far past
    # the reader's max_rows_to_read, and a whole-table scan made /api/layers fail.
    drops = rows(
        "SELECT countIf(h3_res09 IS NULL OR imsi IS NULL) AS dropped, "
        "countIf(rsrp IS NULL AND h3_res09 IS NOT NULL AND imsi IS NOT NULL) AS no_rsrp, "
        "count() AS total FROM oss_lake.ue_trace_raw "
        "WHERE event_ts >= %s - INTERVAL 1 MINUTE AND event_ts < %s" % (ANCHOR64, ANCHOR64))[0]
    gold_window = rows(
        "WITH %s AS t SELECT count() AS n FROM oss_lake.cell_kpi_1m WHERE %s" % (ANCHOR, WINDOW))[0]["n"]
    return {"raw": raw, "silver": silver, "gold": gold, "folded_rows": int(folded),
            "dropped": int(drops["dropped"]), "no_rsrp": int(drops["no_rsrp"]),
            "per_minute": int(drops["total"]), "gold_window_rows": int(gold_window),
            "rank1_cell": top["cell_str"]}


def noc(n, repeat=1):
    """The NOC query on layer n (1-4); elapsed and rows read from ClickHouse's own summary."""
    key, table, view = LAYERS[n - 1]
    sql = ("SELECT list, rnk, h3ToString(cell) AS cell, users, samples, avg_rsrp, poor_pct "
           "FROM oss_lake.%s ORDER BY list DESC, rnk" % view)
    runs = []
    for _ in range(repeat):
        data, summary = ch(sql, settings={"use_query_cache": "0"})
        runs.append((int(summary.get("elapsed_ns", 0)), int(summary.get("read_rows", 0))))
    ms = statistics.median(r[0] for r in runs) / 1e6
    return {"layer": key, "view": view, "rows": data["data"], "elapsed_ms": round(ms, 1),
            "read_rows": runs[-1][1], "runs": repeat}


def map_data():
    """The 20 ranked cells and a res-7 density background (samples in the window), per city."""
    cells = rows(
        "SELECT r.list AS list, r.rnk AS rnk, h3ToString(r.cell) AS cell, r.users AS users, "
        "r.avg_rsrp AS avg_rsrp, g.city AS city, "
        "arrayMap(p -> [round(p.1, 5), round(p.2, 5)], h3ToGeoBoundary(r.cell)) AS boundary "
        "FROM oss_lake.cell_rank_now AS r INNER JOIN oss_lake.grid AS g ON g.h3 = r.cell "
        "ORDER BY list DESC, rnk")
    density = rows(
        "WITH %s AS t SELECT g.city AS city, h3ToParent(k.cell, 7) AS p, "
        "sum(k.samples_n) AS samples, "
        "arrayMap(x -> [round(x.1, 5), round(x.2, 5)], h3ToGeoBoundary(p)) AS boundary "
        "FROM oss_lake.cell_kpi_1m AS k INNER JOIN oss_lake.grid AS g ON g.h3 = k.cell "
        "WHERE %s GROUP BY city, p ORDER BY city, p" % (ANCHOR, WINDOW.replace("bucket", "k.bucket")))
    for d in density:
        d.pop("p")
    return {"cells": cells, "density": density}


def usecases():
    """What the lake is used for (04-usecases.sql): analysis, dashboard series, alerts, and the
    first lines of the same alert query streamed over ClickHouse's HTTP interface."""
    alert_sql = ("SELECT area, city, minute, cells, drop_db, rsrp_now "
                 "FROM oss_lake.uc_alert_areas FORMAT JSONEachRow")
    req = urllib.request.Request(CH_URL + "/", data=alert_sql.encode(), method="POST",
                                 headers={"X-ClickHouse-User": READ_USER, "X-ClickHouse-Key": READ_PASSWORD})
    with urllib.request.urlopen(req, timeout=60) as r:
        lines = [l for l in r.read().decode().splitlines() if l][:3]
    return {
        "analysis": rows("SELECT * FROM oss_lake.uc_analysis"),
        "dashboard": rows("SELECT toString(minute) AS minute, city, users, samples, poor_pct "
                          "FROM oss_lake.uc_dashboard"),
        "alerts": rows("SELECT area, city, district, toString(minute) AS minute, cells, drop_db, rsrp_now "
                       "FROM oss_lake.uc_alert_areas LIMIT 5"),
        "alert_cells": rows(
            "SELECT h3ToString(cell) AS id, city, drop_db, "
            "arrayMap(p -> [round(p.1, 5), round(p.2, 5)], h3ToGeoBoundary(cell)) AS boundary "
            "FROM oss_lake.uc_alert_cells"),
        "http": {"query": alert_sql, "lines": lines},
    }


# ---------------------------------------------------------------- the one write

TICK = threading.Lock()


def tick():
    """Send the next minute: generate it into bronze (the MVs carry it to silver and gold),
    move the anchor one minute, refresh the serving layer now instead of on its schedule."""
    with TICK:
        t0 = time.time()
        before = counts()["layers"][0]["rows"]
        write(
            "INSERT INTO oss_lake.ue_trace_raw (event_ts, h3_res09, imsi, rsrp, rsrq, sinr, cqi, pci, probe) "
            "SELECT * FROM oss_lake.synth_traces(start = %s, minutes = 1)" % ANCHOR)
        write("INSERT INTO oss_lake.params SELECT max(anchor_ts) + INTERVAL 1 MINUTE FROM oss_lake.params")
        insert_s = time.time() - t0
        write("SYSTEM REFRESH VIEW oss_lake.cell_rank_rmv")
        write("SYSTEM WAIT VIEW oss_lake.cell_rank_rmv")
        out = counts()
        out.update(inserted=out["layers"][0]["rows"] - before, insert_s=round(insert_s, 2),
                   total_s=round(time.time() - t0, 2))
        return out


# ---------------------------------------------------------------- snapshot

def machine():
    host = platform.system() + " " + platform.machine()
    if platform.system() == "Darwin":
        try:
            host = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True,
                                  text=True).stdout.strip() + " (macOS " + platform.machine() + ")"
        except OSError:
            pass
    vm = rows("SELECT getSetting('max_threads') AS cpus, "
              "formatReadableSize((SELECT value FROM system.asynchronous_metrics "
              "WHERE metric = 'OSMemoryTotal')) AS mem")[0]
    return {"host": host, "cpus": int(vm["cpus"]), "mem": vm["mem"]}


def snapshot(path):
    write("SYSTEM REFRESH VIEW oss_lake.cell_rank_rmv")
    write("SYSTEM WAIT VIEW oss_lake.cell_rank_rmv")
    for n in range(1, 5):          # warm the page cache once before timing
        noc(n)
    snap = {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "clickhouse": rows("SELECT version() AS v")[0]["v"],
        "machine": machine(),
        "timing_note": "median of 5 runs after one warm-up, server-side elapsed, query cache off",
        **counts(),
        "story": story(),
        "queries": [noc(n, repeat=5) for n in range(1, 5)],
        "map": map_data(),
        "usecases": usecases(),
        "lessons": {
            "state_size": rows("SELECT * FROM oss_lake.lesson_state_size"),
            "grain": rows("SELECT * FROM oss_lake.lesson_grain ORDER BY rows DESC"),
            "regions": rows("WITH (SELECT max(anchor_ts) FROM oss_lake.params) AS t "
                            "SELECT region1, region2, sum(samples_n) AS samples, "
                            "round(100 * sum(poor_n) / sum(rsrp_n), 1) AS poor_pct "
                            "FROM oss_lake.region_kpi_1m WHERE bucket >= t - INTERVAL 1 HOUR AND bucket < t "
                            "GROUP BY region1, region2 ORDER BY poor_pct DESC LIMIT 5"),
        },
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(snap, ensure_ascii=False, indent=1) + "\n")
    print("wrote %s" % path.relative_to(LAB))


def record(path, n):
    """Press the live feed n times and keep what the demo would have fetched each time, so a
    static host (no ClickHouse) can replay it. Changes the loaded data: run on a fresh load,
    after --snapshot."""
    def frame(extra=None):
        f = {**counts(), "story": story(), "cells": map_data()["cells"],
             "q": [noc(k) for k in range(1, 5)], "usecases": usecases()}
        f.update(extra or {})
        return f
    write("SYSTEM REFRESH VIEW oss_lake.cell_rank_rmv")
    write("SYSTEM WAIT VIEW oss_lake.cell_rank_rmv")
    frames = [frame()]
    for _ in range(n):
        t = tick()
        frames.append(frame({"inserted": t["inserted"], "total_s": t["total_s"]}))
    rec = {"recorded": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
           "clickhouse": rows("SELECT version() AS v")[0]["v"],
           "density": map_data()["density"], "frames": frames}
    path.write_text(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
    print("wrote %s (%d frames)" % (path.relative_to(LAB), len(frames)))


# ---------------------------------------------------------------- HTTP

class Handler(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="application/json; charset=utf-8"):
        if not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def api(self, fn, *a):
        try:
            self.send(200, fn(*a))
        except Exception as e:  # ClickHouse down or lab not loaded: say so, do not crash
            print("ClickHouse error on %s: %s" % (self.path, e), file=sys.stderr)
            self.send(503, {"error": "unavailable"})

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/layers":
            return self.api(lambda: {**counts(), "story": story()})
        if path.startswith("/api/q/") and path[7:] in ("1", "2", "3", "4"):
            return self.api(noc, int(path[7:]))
        if path == "/api/map":
            return self.api(map_data)
        if path == "/api/usecases":
            return self.api(usecases)
        import build  # site/build.py, only where pages are served (not in the cloud function)
        page = build.page_for(path)
        if page is None:
            return self.send(404, b"not found", "text/plain")
        self.send(200, page.encode(), "text/html; charset=utf-8")

    def do_POST(self):
        if urllib.parse.urlparse(self.path).path == "/api/tick":
            return self.api(tick)
        self.send(404, b"not found", "text/plain")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--snapshot", action="store_true", help="write site/data/snapshot.json and exit")
    ap.add_argument("--record", type=int, metavar="N",
                    help="press the live feed N times, write site/data/replay.json and exit")
    a = ap.parse_args()
    if a.snapshot:
        return snapshot(LAB / "site" / "data" / "snapshot.json")
    if a.record:
        return record(LAB / "site" / "data" / "replay.json", a.record)
    port = int(os.environ.get("PORT", "8765"))
    print("explainer http://localhost:%d/   demo http://localhost:%d/demo   (ClickHouse %s)"
          % (port, port, CH_URL))
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
