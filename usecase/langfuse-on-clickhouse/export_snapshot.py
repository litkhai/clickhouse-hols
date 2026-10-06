#!/usr/bin/env python3
"""Export Langfuse's ClickHouse database `default` to one replayable SQL file (00-data.sql).

Reads a running Langfuse stack's ClickHouse through `docker exec ... clickhouse-client`
(Python 3 standard library only) and writes, in this order:

  1. a header comment (versions, seed commands, row counts, every deviation from Langfuse's DDL)
  2. DROP ... IF EXISTS for every object, views and materialized views first
  3. every table's DDL, verbatim from SHOW CREATE TABLE (changed only if a plain single-node
     server cannot create it; each change is listed in the header)
  4. the raw rows (no FINAL), as INSERT ... VALUES chunks of at most 1000 rows, ordered by the
     table's sorting key
  5. views and materialized views, after all data, so an MV does not insert again during the load

Usage (the stack from langfuse-hols `_base/bin/up.sh v4` must be running):

    python3 export_snapshot.py --source-commit <langfuse-hols commit>
"""
import argparse
import datetime
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT_REL = "usecase/langfuse-on-clickhouse/export_snapshot.py"
CHUNK_ROWS = 1000

# What was run against the stack before the export (langfuse-hols, offline, ANTHROPIC_API_KEY empty).
SEED_COMMANDS = [
    "labs/v4/langfuse-ee:   python 02-generate-traces.py 40",
    "labs/v4/langfuse-eval: python 01-seed-traces.py 20",
    "labs/v4/langfuse-eval: python 02-prompt-management.py",
    "labs/v4/langfuse-eval: python 03-datasets.py",
    "labs/v4/langfuse-eval: python 04-experiments.py",
    "labs/v4/langfuse-eval: python 05-llm-as-a-judge.py",
    "labs/v4/langfuse-eval: python 06-annotation-queue.py",
]


class Ch:
    """clickhouse-client inside the Langfuse ClickHouse container."""

    def __init__(self, container, user, password):
        self.base = ["docker", "exec", "-i", container, "clickhouse-client",
                     "-u", user, "--password", password]

    def query(self, sql):
        r = subprocess.run(self.base + ["--query", sql], capture_output=True)
        if r.returncode:
            sys.exit("clickhouse-client failed (%d) on: %s\n%s"
                     % (r.returncode, sql[:300], r.stderr.decode(errors="replace")[-2000:]))
        return r.stdout.decode("utf-8")

    def rows(self, sql):
        return [json.loads(line) for line in
                self.query(sql + " FORMAT JSONEachRow").splitlines() if line]

    def scalar(self, sql):
        return self.query(sql).rstrip("\n")


def adapt_ddl(ddl):
    """Make DDL creatable on a plain single-node server. Returns (ddl, [what was changed])."""
    notes = []
    pattern = re.compile(r"Replicated(\w*MergeTree)\(\s*'[^']*'\s*,\s*'[^']*'\s*(?:,\s*([^)]*))?\)")
    new = pattern.sub(lambda m: m.group(1) + ("(%s)" % m.group(2).strip() if m.group(2) else ""), ddl)
    if new != ddl:
        notes.append("Replicated engine replaced by its plain MergeTree-family engine")
    stripped = re.sub(r",?\s*storage_policy\s*=\s*'[^']*'", "", new)
    if stripped != new:
        notes.append("storage_policy setting removed")
    return stripped, notes


def order_views(views):
    """views: {name: ddl}. Order so a view comes after any other view it reads from."""
    ordered, pending = [], sorted(views)
    while pending:
        ready = [n for n in pending
                 if not any(re.search(r"\bdefault\.%s\b" % re.escape(o), views[n].split("\nAS ", 1)[-1])
                            for o in pending if o != n)]
        if not ready:
            sys.exit("views depend on each other in a cycle: %s" % pending)
        ordered.append(ready[0])
        pending.remove(ready[0])
    return ordered


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--container", default="langfuse-hols-v4-clickhouse-1")
    ap.add_argument("--user", default="clickhouse")
    ap.add_argument("--password", default="clickhouse")
    ap.add_argument("--source-commit", required=True, help="langfuse-hols commit the stack and seed scripts came from")
    ap.add_argument("--out", default=str(HERE / "00-data.sql"))
    ap.add_argument("--langfuse-container", help="default: the -langfuse-web- sibling of --container")
    ap.add_argument("--date", default=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
                    help="date written in the header (default: today, UTC); fix it for a byte-identical re-run")
    a = ap.parse_args()
    ch = Ch(a.container, a.user, a.password)

    # --- what we are exporting -------------------------------------------------------------
    version = ch.scalar("SELECT version()")
    ch_image = subprocess.run(["docker", "inspect", "-f", "{{.Config.Image}}", a.container],
                              capture_output=True, text=True).stdout.strip()
    lf_container = a.langfuse_container or re.sub(r"-clickhouse-(\d+)$", r"-langfuse-web-\1", a.container)
    r = subprocess.run(["docker", "inspect", "-f", "{{.Config.Image}}", lf_container],
                       capture_output=True, text=True)
    if r.returncode or not r.stdout.strip():
        sys.exit("cannot read the Langfuse image of %s (pass --langfuse-container)" % lf_container)
    lf_image = r.stdout.strip()
    sdk = ch.scalar("SELECT arrayStringConcat(arraySort(groupUniqArray(ingestion_sdk_version)), ', ') "
                    "FROM default.events_full WHERE ingestion_sdk_name = 'python'") or "unknown"

    objs = ch.rows("SELECT name, engine, sorting_key FROM system.tables "
                   "WHERE database = 'default' AND NOT is_temporary ORDER BY name")
    for o in objs:
        if o["name"].startswith(".inner"):
            sys.exit("%s: a materialized view with an inner table is not handled (use TO <table>)" % o["name"])
    kind = lambda o: {"View": "view", "MaterializedView": "mv", "Dictionary": "dict"}.get(o["engine"], "table")
    tables = [o for o in objs if kind(o) == "table"]
    views = {o["name"]: o for o in objs if kind(o) in ("view", "mv", "dict")}

    deviations, ddl = [], {}
    for o in objs:
        text = ch.query("SHOW CREATE TABLE default.`%s` FORMAT TSVRaw" % o["name"]).rstrip("\n")
        if kind(o) == "dict":
            text = ch.query("SHOW CREATE DICTIONARY default.`%s` FORMAT TSVRaw" % o["name"]).rstrip("\n")
        text, notes = adapt_ddl(text)
        deviations += ["default.%s: %s" % (o["name"], n) for n in notes]
        ddl[o["name"]] = text
    dict_names = [n for n, o in views.items() if kind(o) == "dict"]

    counts = {o["name"]: int(ch.scalar("SELECT count() FROM default.`%s`" % o["name"])) for o in tables}

    # --- header ----------------------------------------------------------------------------
    regen = "python3 %s --source-commit %s --date %s" % (SCRIPT_REL, a.source_commit, a.date)
    for flag, val, default in (("--container", a.container, "langfuse-hols-v4-clickhouse-1"),
                               ("--user", a.user, "clickhouse")):
        if val != default:
            regen += " %s %s" % (flag, val)
    if a.password != "clickhouse":
        regen += " --password <password>"
    if a.langfuse_container:
        regen += " --langfuse-container %s" % a.langfuse_container
    out = ["-- GENERATED by export_snapshot.py — do not edit; re-run",
           "--",
           "-- Regenerate:      " + regen,
           "-- Langfuse:        %s (langfuse-web image)" % lf_image,
           "-- ClickHouse:      %s, version() = %s" % (ch_image, version),
           "-- Langfuse SDK:    python %s (ingestion_sdk_version in events_full)" % sdk,
           "-- langfuse-hols:   commit %s (offline / simulated: ANTHROPIC_API_KEY empty, OSS mode, _base/bin/up.sh v4)"
           % a.source_commit,
           "-- Seed commands, in this order:"]
    out += ["--   " + c for c in SEED_COMMANDS]
    out += ["-- Date:            " + a.date,
            "-- Row counts (raw, no FINAL):"]
    out += ["--   default.%-30s %d" % (t["name"], counts[t["name"]]) for t in tables]
    out += ["-- Views and materialized views (no rows of their own): "
            + (", ".join(sorted(n for n in views if n not in dict_names)) or "none"),
            "-- Dictionaries: " + (", ".join(dict_names) + " (created last, like views)" if dict_names
                                   else "none (system.dictionaries is empty)"),
            "-- Deviations from Langfuse's DDL: " + ("none" if not deviations else ""),
            ]
    out += ["--   " + d for d in deviations]
    out += [""]

    # --- drops: views and MVs first --------------------------------------------------------
    order = order_views({n: ddl[n] for n in views})
    out += ["-- 1. Drop (views and materialized views first)"]
    for n in reversed(order):
        out += ["DROP %s IF EXISTS default.`%s` SYNC;" % ("DICTIONARY" if n in dict_names else "VIEW", n)]
    for t in reversed(tables):
        out += ["DROP TABLE IF EXISTS default.`%s` SYNC;" % t["name"]]
    out += [""]

    # --- tables ----------------------------------------------------------------------------
    out += ["-- 2. Tables (SHOW CREATE TABLE, verbatim)"]
    for t in tables:
        out += [ddl[t["name"]] + ";", ""]

    # --- data ------------------------------------------------------------------------------
    out += ["-- 3. Rows (raw, no FINAL; ordered by each table's sorting key)"]
    for t in tables:
        name = t["name"]
        if counts[name] == 0:
            out += ["-- default.%s: 0 rows" % name]
            continue
        cols = [c["name"] for c in ch.rows(
            "SELECT name FROM system.columns WHERE database = 'default' AND table = '%s' "
            "AND default_kind NOT IN ('MATERIALIZED', 'ALIAS') ORDER BY position" % name)]
        collist = ", ".join("`%s`" % c for c in cols)
        order_by = (" ORDER BY " + t["sorting_key"]) if t["sorting_key"] else ""
        out += ["-- default.%s: %d rows" % (name, counts[name])]
        for off in range(0, counts[name], CHUNK_ROWS):
            data = ch.query("SELECT %s FROM default.`%s`%s LIMIT %d OFFSET %d FORMAT Values"
                            % (collist, name, order_by, CHUNK_ROWS, off))
            out += ["INSERT INTO default.`%s` (%s) VALUES %s;" % (name, collist, data.rstrip("\n"))]
        out += [""]

    # --- views, MVs, dictionaries last -----------------------------------------------------
    out += ["-- 4. Views, materialized views, dictionaries (after all data, so an MV does not insert again)"]
    for n in order:
        out += [ddl[n] + ";", ""]

    pathlib.Path(a.out).write_text("\n".join(out), encoding="utf-8")
    print("wrote %s (%d bytes); rows: %s" % (a.out, pathlib.Path(a.out).stat().st_size,
                                             ", ".join("%s=%d" % kv for kv in counts.items())))


if __name__ == "__main__":
    main()
