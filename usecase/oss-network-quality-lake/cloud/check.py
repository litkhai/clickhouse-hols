#!/usr/bin/env python3
"""Check the live site from outside: pages, every demo endpoint, the feed, read headroom.

    python3 cloud/check.py [https://oss-lake.clickhouse.kr]

No credentials: it reads what any viewer reads (about a dozen requests, well inside the reader's
hourly quota). Prints one line per check and exits 1 when any fails, so a scheduled run can
report it. What it catches:
  - a page that is not served (every locale, explainer and demo),
  - an endpoint answering 503 "unavailable": the demo then quietly falls back to its recording
    (2026-10-28: /api/layers had done so for days, its quality counts scanning all of bronze),
  - a feed that stopped: the lake's "now" more than FRESH minutes behind the wall clock,
  - a NOC query reading more than WARN of the reader's max_rows_to_read, before it fails.
"""
import datetime, json, sys, urllib.error, urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "https://oss-lake.clickhouse.kr").rstrip("/")
PAGES = ["/", "/demo/"] + ["/%s/%s" % (loc, p) for loc in ("ko", "ja", "zh", "es") for p in ("", "demo/")]
API = ["/api/layers", "/api/map", "/api/usecases"] + ["/api/q/%d" % n for n in (1, 2, 3, 4)]
FRESH = 5                 # minutes; the anchor trails by up to 2, the edge cache adds up to 1
MAX_ROWS = 30000000       # the reader's max_rows_to_read (cloud/load.py READER_SETTINGS)
WARN = 0.75

failed = []


def get(path):
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "oss-lake-check"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except OSError as e:
        return None, str(e).encode()


def report(ok, what):
    print("%s  %s" % ("OK  " if ok else "FAIL", what))
    if not ok:
        failed.append(what)


for path in PAGES:
    code, _ = get(path)
    report(code == 200, "page %s: %s" % (path, code))

answers = {}
for path in API:
    code, body = get(path)
    try:
        data = json.loads(body)
    except ValueError:
        data = {}
    ok = code == 200 and isinstance(data, dict) and "error" not in data
    report(ok, "api %s: %s%s" % (path, code, "" if ok else " " + body[:80].decode(errors="replace")))
    if ok:
        answers[path] = data

layers = answers.get("/api/layers")
if layers:
    anchor = datetime.datetime.strptime(layers["anchor_ts"], "%Y-%m-%d %H:%M:%S")
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    behind = (now - anchor).total_seconds() / 60
    report(behind <= FRESH, "feed: lake's now %s UTC, %.1f min behind (limit %d)"
           % (layers["anchor_ts"], behind, FRESH))
for n in (1, 2, 3, 4):
    q = answers.get("/api/q/%d" % n)
    if q:
        report(len(q["rows"]) == 20 and q["read_rows"] <= WARN * MAX_ROWS,
               "noc %s: %d rows, %s rows read (%.0f%% of the reader's limit), %s ms"
               % (q["layer"], len(q["rows"]), "{:,}".format(q["read_rows"]),
                  100.0 * q["read_rows"] / MAX_ROWS, q["elapsed_ms"]))

print("%d failed" % len(failed) if failed else "all passed")
sys.exit(1 if failed else 0)
