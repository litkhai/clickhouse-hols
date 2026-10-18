#!/usr/bin/env python3
"""Load the lab into a ClickHouse Cloud service and start its self-running feed.

    CH_HOST=... CH_USER=... CH_PASSWORD=... python3 cloud/load.py          load 01-05 + cloud/feed.sql
    CH_HOST=... CH_USER=... CH_PASSWORD=... python3 cloud/load.py feed stop|start|status
    CH_HOST=... CH_USER=... CH_PASSWORD=... python3 cloud/load.py harden   reader limits + quota, no params TTL
    CH_HOST=... CH_USER=... CH_PASSWORD=... python3 cloud/load.py drop     remove everything (99-cleanup)

Python stdlib only, over the HTTPS interface (port 8443). The SQL is the lab's own; only what
Cloud needs differs:
  - no `ENGINE = Atomic` (Cloud databases are Shared; refreshable MVs work there),
  - users get passwords: oss_reader (read-only, with time, rows-read and result limits, and an
    hourly quota, so a public page cannot run up the service) and oss_dict (the dictionary's
    own source user, SELECT on the inventory only),
  - the check table is MergeTree, not Memory (two replicas; a Memory table lives on one),
  - every statement reads with select_sequential_consistency = 1 (it sees the previous insert),
  - the inventory dictionary is reloaded on every replica, and the load waits until each holds
    the whole inventory (a replica that loaded it empty would give rows no district).
The two generated passwords are written to $OSS_LAKE_SECRETS (default .env.cloud next to this
lab's README, ignored by git, mode 600); a second load reuses them.
"""
import os, pathlib, re, secrets, sys, time, urllib.error, urllib.parse, urllib.request

LAB = pathlib.Path(__file__).resolve().parent.parent
HOST, USER, PASSWORD = os.environ["CH_HOST"], os.environ["CH_USER"], os.environ["CH_PASSWORD"]
SECRETS = pathlib.Path(os.environ.get("OSS_LAKE_SECRETS", LAB / ".env.cloud"))
READER_SETTINGS = ("readonly = 1, max_execution_time = 20, max_rows_to_read = 30000000, "
                   "read_overflow_mode = 'throw', max_result_rows = 200000, result_overflow_mode = 'throw'")
# Normal traffic is a handful of edge-cache misses a minute; this caps an hour of abuse.
QUOTA = ("CREATE QUOTA OR REPLACE oss_reader_quota FOR INTERVAL 1 hour "
         "MAX queries = 3000, read_rows = 5000000000 TO oss_reader")


def passwords():
    vals = {}
    if SECRETS.exists():
        for line in SECRETS.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                vals[k] = v
    for k in ("OSS_READER_PASSWORD", "OSS_DICT_PASSWORD"):
        vals.setdefault(k, secrets.token_urlsafe(24) + "Aa1")
    SECRETS.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(SECRETS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)  # never readable by others
    with os.fdopen(fd, "w") as f:
        f.write("".join("%s=%s\n" % kv for kv in sorted(vals.items())))
    SECRETS.chmod(0o600)
    return vals


def run(sql, quiet=False):
    params = {"select_sequential_consistency": "1", "send_progress_in_http_headers": "1",
              "http_headers_progress_interval_ms": "5000", "wait_end_of_query": "1"}
    req = urllib.request.Request("https://%s:8443/?%s" % (HOST, urllib.parse.urlencode(params)),
                                 data=sql.encode(), method="POST",
                                 headers={"X-ClickHouse-User": USER, "X-ClickHouse-Key": PASSWORD})
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            out = r.read().decode()
    except urllib.error.HTTPError as e:
        sys.exit("FAILED: %s\n%s" % (sql.strip().splitlines()[0][:120], e.read().decode()[:800]))
    if out.strip() and not quiet:
        print(out.rstrip())
    return out


def statements(text):
    """Split a lab SQL file into statements: drop comment-only lines, split on a closing ';'."""
    text = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("--"))
    for st in re.split(r";[ \t]*(?:--[^\n]*)?\n", text + "\n"):
        if st.strip():
            yield st.strip()


def for_cloud(st, pw):
    st = st.replace("CREATE DATABASE oss_lake ENGINE = Atomic", "CREATE DATABASE oss_lake")
    st = st.replace("CREATE USER oss_reader IDENTIFIED WITH no_password SETTINGS readonly = 1",
                    "CREATE USER oss_reader IDENTIFIED BY '%s' SETTINGS %s"
                    % (pw["OSS_READER_PASSWORD"], READER_SETTINGS))
    st = st.replace("SOURCE(CLICKHOUSE(DB 'oss_lake' TABLE 'cell_inventory'))",
                    "SOURCE(CLICKHOUSE(DB 'oss_lake' TABLE 'cell_inventory' USER 'oss_dict' PASSWORD '%s'))"
                    % pw["OSS_DICT_PASSWORD"])
    st = st.replace("ENGINE = Memory AS", "ENGINE = MergeTree ORDER BY tuple() AS")
    return st


def load():
    pw = passwords()
    files = ["01-schema.sql", "02-generate.sql", "03-queries.sql", "04-usecases.sql", "05-lessons.sql",
             "cloud/feed.sql"]
    for name in files:
        t0 = time.time()
        for st in statements((LAB / name).read_text()):
            st = for_cloud(st, pw)
            if st.startswith("CREATE DICTIONARY"):
                # the dictionary's own user, before the dictionary that names it
                run("DROP USER IF EXISTS oss_dict")
                run("CREATE USER oss_dict IDENTIFIED BY '%s'" % pw["OSS_DICT_PASSWORD"])
                run("GRANT SELECT ON oss_lake.cell_inventory TO oss_dict")
            if st.startswith("SYSTEM RELOAD DICTIONARY"):
                # every replica keeps its own copy: reload all of them, and wait until each holds
                # the whole inventory before any trace is generated
                run(st + " ON CLUSTER 'default'", quiet=True)
                for _ in range(60):
                    out = run("SELECT min(element_count) = (SELECT count() FROM oss_lake.cell_inventory) "
                              "FROM clusterAllReplicas('default', system.dictionaries) "
                              "WHERE database = 'oss_lake' AND name = 'cell_dict'", quiet=True)
                    if out.strip() == "1":
                        break
                    time.sleep(2)
                else:
                    sys.exit("cell_dict did not load on every replica")
                continue
            run(st)
            if st.startswith("CREATE USER oss_reader"):
                run(QUOTA)
        print("PASS %s (%.0f s)" % (name, time.time() - t0), flush=True)


def harden():
    """Apply the reader limits and quota, and drop the params TTL, on a lake already loaded."""
    run("ALTER USER oss_reader SETTINGS " + READER_SETTINGS)
    run(QUOTA)
    run("ALTER TABLE oss_lake.params REMOVE TTL")
    print(run("SELECT name, keys, durations, apply_to_list FROM system.quotas WHERE name = 'oss_reader_quota' "
              "FORMAT PrettyCompactMonoBlock", quiet=True))


def feed(cmd):
    views = ["oss_lake.feed_rmv", "oss_lake.anchor_rmv"]
    if cmd == "start":
        # after a long pause, skip the gap instead of replaying it: the lake's 'now' restarts one
        # minute ago, so the next refresh generates one minute and the window fills from there
        run("INSERT INTO oss_lake.params SELECT toStartOfMinute(now()) - INTERVAL 1 MINUTE "
            "FROM oss_lake.params HAVING max(anchor_ts) < toStartOfMinute(now()) - INTERVAL 5 MINUTE")
    if cmd in ("stop", "start"):
        for v in views:
            run("SYSTEM %s REPLICATED VIEW %s" % (cmd.upper(), v))
    print(run("SELECT view, status, last_success_time, next_refresh_time, exception FROM system.view_refreshes "
              "WHERE database = 'oss_lake' ORDER BY view FORMAT PrettyCompactMonoBlock", quiet=True))
    print(run("SELECT max(anchor_ts) AS now_in_lake, now() AS wall_clock FROM oss_lake.params "
              "FORMAT PrettyCompactMonoBlock", quiet=True))


def drop():
    for st in statements((LAB / "99-cleanup.sql").read_text()):
        run(st)
    run("DROP USER IF EXISTS oss_dict")
    print("dropped oss_lake, oss_pitfall, oss_reader, oss_dict")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        load()
    elif args[0] == "feed" and len(args) == 2 and args[1] in ("stop", "start", "status"):
        feed(args[1])
    elif args == ["harden"]:
        harden()
    elif args == ["drop"]:
        drop()
    else:
        sys.exit(__doc__)
