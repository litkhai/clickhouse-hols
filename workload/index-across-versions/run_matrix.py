#!/usr/bin/env python3
"""run_matrix.py - run the lab's NN-*.sql files on several ClickHouse versions and tabulate.

Generic: nothing here knows what the SQL is about. Python 3 stdlib + Docker CLI only.

    ./run_matrix.py                         every version in versions.txt
    ./run_matrix.py --versions 26.10,26.8   only these (prefix of a line in versions.txt)
    ./run_matrix.py --only 05               only a file name prefix or a probe id prefix
                                            (00-* always runs; results merge into the JSON)
    ./run_matrix.py --keep                  leave the last container running
    ./run_matrix.py --report-only           rebuild RESULTS.md from results/*.json

SQL file conventions
  * Files: NN-*.sql in the lab directory, then errors/NN-*.sql (same rules; tools/hol does not
    glob subdirectories, so errors/ may hold probes that fail on the newest version too).
  * Statements end with `;` at the end of a line. Do not end a line with `;` inside a string literal.
  * `-- settings: a, b, c` (any line of the file) lists settings to look up in system.settings (then system.merge_tree_settings).
  * A statement directly preceded by `-- probe: <id> [repeat=N] [show] [value] [events]` is a probe;
    every other statement is setup. `show` prints the newest version's result rows in RESULTS.md,
    `value` makes the table cell the first result row and the time (for probes whose number is the point),
    `events` prints the ProfileEvents of that probe for every version.
  * Each statement runs in its own clickhouse-client call, so do not use a bare `SET`;
    put settings in the statement's SETTINGS clause.
"""
import argparse, datetime, json, pathlib, re, statistics, subprocess, sys, time

LAB = pathlib.Path(__file__).resolve().parent
ROOT = LAB.parent.parent
SECCOMP = ROOT / "local" / "oss-docker" / "seccomp-profile.json"
RESULTS = LAB / "results"
# container name prefix from the lab directory name (join-across-versions -> jav-), so two labs never touch each other's containers
PREFIX = "".join(w[0] for w in LAB.name.split("-")) + "-"
TIMEOUT = 300
EVENTS = "(?i)external|spill|join|patch|mutat"
LOG_COLS = ["query_duration_ms", "memory_usage", "read_rows", "read_bytes", "written_rows",
            "written_bytes", "result_rows", "exception_code",
            "used_join_algorithms", "used_join_kinds", "used_number_of_joins"]


def sh(*cmd, stdin=None, timeout=None):
    return subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=timeout)


# ---------------------------------------------------------------- parsing
def parse(path):
    """-> (settings names, items). item = dict(kind setup|probe, id, repeat, flags, sql)."""
    settings, items, cur, pending = [], [], [], None
    n = 0
    for line in path.read_text().splitlines():
        s = line.strip()
        if not cur:
            if not s:
                continue
            if s.startswith("--"):
                m = re.match(r"--\s*settings:\s*(.*)", s)
                if m:
                    settings += [x.strip() for x in m.group(1).split(",") if x.strip()]
                m = re.match(r"--\s*probe:\s*(\S+)(.*)", s)
                if m:
                    rest = m.group(2).split()
                    rep = [int(x[7:]) for x in rest if x.startswith("repeat=")]
                    pending = dict(id=m.group(1), repeat=rep[0] if rep else 1,
                                   flags=[x for x in rest if not x.startswith("repeat=")])
                continue
        cur.append(line)
        if s.endswith(";") and not s.startswith("--"):
            n += 1
            sql = "\n".join(cur)
            if pending:
                items.append(dict(kind="probe", sql=sql, **pending))
            else:
                items.append(dict(kind="setup", id="%s-setup%02d" % (path.stem[:2], n), repeat=1, flags=[], sql=sql))
            cur, pending = [], None
    if cur and any(c.strip() for c in cur):
        sys.exit("%s: last statement has no terminating ';' at line end" % path.name)
    return settings, items


def err_of(stderr):
    m = re.search(r"Code:\s*(\d+)", stderr)
    code = int(m.group(1)) if m else None
    msg = ""
    for l in stderr.splitlines():
        if "Exception" in l or l.startswith("Code:"):
            msg = l.split("DB::Exception:", 1)[-1].strip()
            break
    return code, (msg or stderr.strip().splitlines()[0] if stderr.strip() else "")[:240]


# ---------------------------------------------------------------- container
class Server:
    def __init__(self, tag):
        self.tag = tag
        self.name = PREFIX + tag.replace(".", "-")

    def start(self):
        sh("docker", "rm", "-f", "-v", self.name)
        args = ["docker", "run", "-d", "--name", self.name, "--ulimit", "nofile=262144:262144",
                "-e", "CLICKHOUSE_PASSWORD=", "-e", "CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1"]
        if SECCOMP.exists():
            args += ["--security-opt", "seccomp=%s" % SECCOMP]
        r = sh(*args, "clickhouse/clickhouse-server:" + self.tag)
        if r.returncode:
            raise RuntimeError("could not start %s: %s" % (self.tag, r.stderr.strip()))
        for _ in range(90):
            if sh("docker", "exec", self.name, "clickhouse-client", "-q", "SELECT 1").returncode == 0:
                return
            time.sleep(1)
        raise RuntimeError("%s did not become ready" % self.name)

    def stop(self):
        sh("docker", "rm", "-f", "-v", self.name)

    def q(self, sql, query_id=None, fmt="TSVWithNames", timeout=TIMEOUT):
        cmd = ["docker", "exec", "-i", self.name, "clickhouse-client", "--format", fmt,
               "--output_format_json_quote_64bit_integers", "0"]
        if query_id:
            cmd += ["--query_id", query_id]
        t = time.time()
        try:
            r = sh(*cmd, stdin=sql, timeout=timeout)
        except subprocess.TimeoutExpired:
            sh("docker", "exec", self.name, "clickhouse-client", "-q",
               "KILL QUERY WHERE query_id = '%s' SYNC" % query_id)
            return dict(rc=-1, out="", err="Timeout after %ds" % timeout, wall=time.time() - t)
        return dict(rc=r.returncode, out=r.stdout, err=r.stderr, wall=time.time() - t)

    def rows(self, sql):
        r = self.q(sql, fmt="JSONEachRow")
        if r["rc"]:
            raise RuntimeError(r["err"])
        return [json.loads(l) for l in r["out"].splitlines() if l.strip()]


def other_cpu(tag_prefix=PREFIX):
    """CPU% of every running container that is not ours, at this moment (docker stats --no-stream)."""
    r = sh("docker", "stats", "--no-stream", "--format", "{{.Name}} {{.CPUPerc}}")
    out = {}
    for l in r.stdout.splitlines():
        n, _, c = l.partition(" ")
        if n and not n.startswith(tag_prefix):
            try:
                out[n] = float(c.strip().rstrip("%"))
            except ValueError:
                pass
    return out


def others(tag_prefix=PREFIX):
    r = sh("docker", "ps", "--format", "{{.Names}}")
    return sorted(n for n in r.stdout.split() if not n.startswith(tag_prefix))


# ---------------------------------------------------------------- one version
def lookup_settings(srv, names):
    if not names:
        return []
    cols = {r["name"] for r in srv.rows("SELECT name FROM system.columns WHERE database='system' AND table='settings'")}
    sel = ["name", "value"] + [c for c in ("default", "tier") if c in cols]
    lst = ",".join("'%s'" % n for n in names)
    found = {r["name"]: r for r in srv.rows(
        "SELECT %s FROM system.settings WHERE name IN (%s)" % (",".join("`%s`" % c for c in sel), lst))}
    mt_cols = {r["name"] for r in srv.rows("SELECT name FROM system.columns WHERE database='system' AND table='merge_tree_settings'")}
    mt_sel = ["name", "value"] + [c for c in ("default", "tier") if c in mt_cols]
    mt = {r["name"]: r for r in srv.rows(
        "SELECT %s FROM system.merge_tree_settings WHERE name IN (%s)" % (",".join("`%s`" % c for c in mt_sel), lst))} if mt_cols else {}
    out = []
    for n in names:
        r = found.get(n)
        if r:
            out.append(dict(name=n, exists=True, value=r.get("default", r["value"]), tier=r.get("tier")))
        elif n in mt:  # a MergeTree table setting: shown with the tier "table"
            m = mt[n]
            out.append(dict(name=n, exists=True, value=m.get("default", m["value"]),
                            tier="table" + (", " + m["tier"] if m.get("tier") else "")))
        else:
            out.append(dict(name=n, exists=False, value=None, tier=None))
    return out


def run_file(srv, path, only, log_cols):
    settings, items = parse(path)
    key = path.relative_to(LAB).as_posix()
    file_sel = bool(only) and (key.startswith(only) or path.name.startswith(only))
    if only and not path.name.startswith("00") and not file_sel:
        items = [i for i in items if i["kind"] == "setup" or i["id"].startswith(only)]
        if not any(i["kind"] == "probe" for i in items):
            return settings, None
    res = dict(setup=[], probes=[])
    failed = None
    for it in items:
        if it["kind"] == "setup":
            if failed:
                continue
            r = srv.q(it["sql"], query_id="%s-%s" % (it["id"], int(time.time() * 1000)))
            ok = r["rc"] == 0
            code, msg = err_of(r["err"]) if not ok else (None, "")
            res["setup"].append(dict(id=it["id"], ok=ok, code=code, message=msg, wall_s=round(r["wall"], 2),
                                     sql=it["sql"][:300]))
            if not ok:
                failed = code if code is not None else "exit"
                print("   setup %s FAILED: Code %s %s" % (it["id"], code, msg), flush=True)
            continue
        p = dict(id=it["id"], repeat=it["repeat"], flags=it["flags"], sql=it["sql"], runs=[])
        if failed:
            p.update(status="skip", code=failed, message="skip (setup Code %s)" % failed)
            res["probes"].append(p)
            continue
        for k in range(it["repeat"]):
            qid = it["id"] if it["repeat"] == 1 else "%s.%d" % (it["id"], k + 1)
            r = srv.q(it["sql"], query_id=qid)
            run = dict(query_id=qid, wall_s=round(r["wall"], 3), rc=r["rc"])
            if r["rc"]:
                run["code"], run["message"] = err_of(r["err"])
                run["stderr"] = r["err"][:1500]
            else:
                lines = r["out"].splitlines()
                run["stdout"] = r["out"][:100000]
                run["rows"] = lines[:21]
            p["runs"].append(run)
            if r["rc"]:
                break
        res["probes"].append(p)
    # query_log
    srv.q("SYSTEM FLUSH LOGS")
    ids = [r["query_id"] for p in res["probes"] for r in p["runs"]]
    log = {}
    if ids:
        sel = ", ".join(log_cols + ["query_id", "type",
                        "mapFilter((k, v) -> v > 0 AND match(k, '%s'), ProfileEvents) AS events" % EVENTS])
        q = ("SELECT %s FROM system.query_log WHERE type != 'QueryStart' AND query_id IN (%s) "
             "ORDER BY event_time_microseconds" % (sel, ",".join("'%s'" % i for i in ids)))
        for row in srv.rows(q):
            log[row["query_id"]] = row
    for p in res["probes"]:
        for r in p["runs"]:
            r["log"] = log.get(r["query_id"])
        if p.get("status") == "skip":
            continue
        bad = [r for r in p["runs"] if r["rc"]]
        if bad:
            p["status"], p["code"], p["message"] = "error", bad[0].get("code"), bad[0].get("message")
            lg = bad[0].get("log") or {}
            p["memory_usage"] = lg.get("memory_usage")
            p["duration_ms"] = lg.get("query_duration_ms")
            p["events"] = lg.get("events")
            continue
        logs = [r["log"] for r in p["runs"] if r["log"]]
        p["status"] = "ok"
        durs = [l["query_duration_ms"] for l in logs]
        p["durations_ms"] = durs
        p["duration_ms"] = statistics.median(durs) if durs else None
        p["memory_usage"] = max(l["memory_usage"] for l in logs) if logs else None
        if logs:
            last = logs[-1]
            for c in ("read_rows", "read_bytes", "written_rows", "written_bytes", "result_rows",
                      "used_join_algorithms", "used_join_kinds", "used_number_of_joins"):
                if c in last:
                    p[c] = last[c]
            p["events"] = last.get("events")
        p["rows"] = p["runs"][-1].get("rows")
        p["stdout"] = p["runs"][-1].get("stdout")
        if "used_join_algorithms" not in p and re.search(r"\bJOIN\b", p["sql"], re.I) \
                and re.match(r"\s*(--[^\n]*\n\s*)*(SELECT|WITH)\b", p["sql"], re.I):
            # older servers do not log the algorithm: take the join processors from EXPLAIN PIPELINE
            e = srv.q("EXPLAIN PIPELINE " + p["sql"].strip().rstrip(";"), query_id="pipe-" + p["id"])
            if e["rc"] == 0:
                p["pipeline_join"] = sorted(set(re.findall(r"\b\w*Join\w*\b", e["out"])))
            else:
                p["pipeline_join"] = None
    return settings, res


def run_version(tag, only, keep):
    srv = Server(tag)
    t0 = time.time()
    print("== %s" % tag, flush=True)
    info = sh("docker", "info", "--format", "{{.NCPU}} {{.MemTotal}}").stdout.split()
    machine = dict(ncpu=int(info[0]), mem_bytes=int(info[1]), others=others(), others_cpu=other_cpu())
    try:
        srv.start()
        version = srv.rows("SELECT version() AS v")[0]["v"]
        srv.q("SELECT 1")
        srv.q("SYSTEM FLUSH LOGS")  # creates system.query_log, which does not exist on a fresh server
        cols = {r["name"] for r in srv.rows("SELECT name FROM system.columns WHERE database='system' AND table='query_log'")}
        if "query_duration_ms" not in cols:
            raise RuntimeError("system.query_log has no columns on %s" % tag)
        log_cols = [c for c in LOG_COLS if c in cols]
        out = RESULTS / ("%s.json" % tag)
        data = json.loads(out.read_text()) if only and out.exists() else dict(files={}, settings={})
        data.update(tag=tag, version=version, date=datetime.date.today().isoformat(), machine=machine)
        # top-level files first (the ones tools/hol runs), then errors/ (results that are failures on the newest version)
        for path in sorted(LAB.glob("[0-9][0-9]-*.sql")) + sorted(LAB.glob("errors/[0-9][0-9]-*.sql")):
            key = path.relative_to(LAB).as_posix()
            settings, res = run_file(srv, path, only, log_cols)
            if res is None:
                continue
            data["settings"][key] = lookup_settings(srv, settings)
            data["files"][key] = res
            n = [p.get("status") for p in res["probes"]]
            print("   %s: %d probes, %d ok, %d error, %d skip" % (key, len(n), n.count("ok"),
                  n.count("error"), n.count("skip")), flush=True)
        data["machine"]["others"] = sorted(set(machine["others"]) | set(others()))
        data["elapsed_s"] = round(time.time() - t0)
        RESULTS.mkdir(exist_ok=True)
        out.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
        print("   %s done in %ds" % (version, data["elapsed_s"]), flush=True)
    finally:
        if not keep:
            srv.stop()


# ---------------------------------------------------------------- report
def mib(b):
    if b is None:
        return "?"
    return "%d MiB" % round(b / 1048576) if b >= 1048576 else "%d KiB" % round(b / 1024)


def cell(p):
    if p is None:
        return "-"
    if p["status"] == "skip":
        return "skip"
    if p["status"] == "error":
        return "✗ Code %s" % p["code"]
    if "value" in p.get("flags", []):
        # `value` probes: the number is the point; show the first result row instead of time and memory
        lines = (p.get("stdout") or "").splitlines()
        return "= %s · %.2f s" % (lines[1].replace("\t", " / ") if len(lines) > 1 else "(no row)", (p["duration_ms"] or 0) / 1000)
    algo = "+".join(sorted({a.upper() for a in p.get("used_join_algorithms") or []}))
    t = "%.2f s" % ((p["duration_ms"] or 0) / 1000)
    if len(p.get("durations_ms") or []) > 1:  # repeated probe: median (min)
        t += " (min %.2f)" % (min(p["durations_ms"]) / 1000)
    s = "✓ %s · %s" % (t, mib(p["memory_usage"]))
    return s + (" · " + algo if algo else "")


def rows_cell(p):
    if p is None or p["status"] != "ok":
        return "-"
    return "{:,}".format(p.get("read_rows", 0))


def report(tags):
    docs = []
    for t in tags:
        f = RESULTS / ("%s.json" % t)
        if f.exists():
            docs.append(json.loads(f.read_text()))
    if not docs:
        sys.exit("no results/*.json")
    newest = docs[-1]
    latest = max(docs, key=lambda d: d["date"])
    m = latest["machine"]
    L = ["# Results", "",
         "Generated by `run_matrix.py --report-only` from `results/*.json`. Every cell is from a run; `-` = not run.", "",
         "Machine: %d CPUs, %.1f GiB Docker VM memory (`docker info`), run date %s, other running containers at that moment: %s."
         % (m["ncpu"], m["mem_bytes"] / 2**30, latest["date"], ", ".join("`%s`" % o for o in m["others"]) or "none"), "",
         "Builds: " + ", ".join("`%s`" % d["version"] for d in docs), ""]
    names = sorted({n for d in docs for n in d["machine"].get("others_cpu", {})})
    if names:
        L += ["CPU% (`docker stats --no-stream`) of the other running containers when each version's run started (12 CPUs = 1200%):", "",
              "| container | " + " | ".join(d["tag"] for d in docs) + " |", "|---|" + "---|" * len(docs)]
        for n in names:
            L.append("| `%s` | %s |" % (n, " | ".join(("%.1f%%" % d["machine"]["others_cpu"][n]) if n in d["machine"].get("others_cpu", {}) else "-" for d in docs)))
        L.append("| total | %s |" % " | ".join("%.0f%%" % sum(d["machine"].get("others_cpu", {}).values()) for d in docs))
        L.append("")
    files = sorted({f for d in docs for f in d["files"]})
    L += ["## Settings per version", "",
          "Value is the default from `system.settings` on a fresh server; `no` = the setting does not exist; tier in brackets when the column exists.", ""]
    names = []
    for d in docs:
        for f, lst in d["settings"].items():
            for s in lst:
                if s["name"] not in names:
                    names.append(s["name"])
    L += ["| setting | " + " | ".join(d["tag"] for d in docs) + " |", "|---|" + "---|" * len(docs)]
    for n in names:
        row = []
        for d in docs:
            hit = next((s for lst in d["settings"].values() for s in lst if s["name"] == n), None)
            row.append("-" if hit is None else "no" if not hit["exists"] else
                       "`%s`%s" % (hit["value"], " [%s]" % hit["tier"] if hit.get("tier") else ""))
        L.append("| `%s` | %s |" % (n, " | ".join(row)))
    L.append("")
    for f in files:
        probes = []
        for d in docs:
            for p in d["files"].get(f, {}).get("probes", []):
                if p["id"] not in probes:
                    probes.append(p["id"])
        get = lambda d, i: next((p for p in d["files"].get(f, {}).get("probes", []) if p["id"] == i), None)
        if not probes:
            continue
        L += ["## %s" % f, ""] + (["Not run by `tools/hol`: probes in `errors/` are expected to fail on some versions, possibly the newest.", ""] if f.startswith("errors/") else []) + [ "Cell = time (median of repeats, `(min …)` = fastest repeat) · peak memory · join algorithm (query_log used_join_algorithms where logged, else the Join processors of EXPLAIN PIPELINE); `= x · t` is the first result row of a `value` probe and its time.", "",
              "| probe | " + " | ".join(d["tag"] for d in docs) + " |", "|---|" + "---|" * len(docs)]
        for i in probes:
            L.append("| `%s` | %s |" % (i, " | ".join(cell(get(d, i)) for d in docs)))
        L += ["", "Rows read:", "", "| probe | " + " | ".join(d["tag"] for d in docs) + " |", "|---|" + "---|" * len(docs)]
        for i in probes:
            L.append("| `%s` | %s |" % (i, " | ".join(rows_cell(get(d, i)) for d in docs)))
        L.append("")
        msgs = [(i, d["tag"], get(d, i)["message"]) for i in probes for d in docs
                if get(d, i) and get(d, i)["status"] == "error"]
        if msgs:
            L += ["Errors:", ""] + ["- `%s` on %s: %s" % (i, t, (mm or "").replace("|", "\\|")) for i, t, mm in msgs] + [""]
        for i in probes:
            p = get(newest, i)
            if p and "show" in p.get("flags", []):
                L += ["`%s` on %s:" % (i, newest["tag"]), "", "```"] + \
                     [l[:200] for l in ((p.get("stdout") or p.get("message") or "").splitlines()[:60])] + ["```", ""]
            if p and "events" in p.get("flags", []):
                L += ["ProfileEvents of `%s` (non-zero, filtered):" % i, ""]
                for d in docs:
                    q = get(d, i)
                    L.append("- %s: %s" % (d["tag"], json.dumps(q.get("events")) if q and q.get("events") else "none"))
                L.append("")
    if any("pipeline_join" in p for d in docs for r in d["files"].values() for p in r["probes"]):
        L += ["## Join processors from EXPLAIN PIPELINE", "",
              "`query_log.used_join_algorithms` is empty on servers that do not log it (cells above then show no algorithm). "
              "For those, each probe's `EXPLAIN PIPELINE` was searched for processor names containing `Join`; "
              "probes with the same set are grouped. This shows the join processors in the pipeline, not the algorithm name.", ""]
        for d in docs:
            groups = {}
            for f, res in d["files"].items():
                for p in res["probes"]:
                    if "pipeline_join" in p:
                        groups.setdefault(", ".join(p["pipeline_join"] or ["(none)"]), []).append(p["id"])
            if groups:
                L.append("- `%s`:" % d["tag"])
                for k, v in groups.items():
                    L.append("  - `%s`: %s" % (k, ", ".join(v)))
    L.append("")
    (LAB / "RESULTS.md").write_text("\n".join(L) + "\n")
    print("wrote RESULTS.md (%d versions)" % len(docs))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--versions")
    ap.add_argument("--only")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--report-only", action="store_true")
    a = ap.parse_args()
    pins = [l.strip() for l in (LAB / "versions.txt").read_text().splitlines() if l.strip() and not l.startswith("#")]
    sel = pins
    if a.versions:
        want = [w.strip() for w in a.versions.split(",")]
        sel = [p for p in pins if any(p == w or p.startswith(w + ".") for w in want)]
        if not sel:
            sys.exit("no version in versions.txt matches %s" % a.versions)
    if not a.report_only:
        RESULTS.mkdir(exist_ok=True)
        for t in sel:
            run_version(t, a.only, a.keep)
    report(pins)


if __name__ == "__main__":
    main()
