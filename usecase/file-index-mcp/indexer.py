#!/usr/bin/env python3
"""File metadata -> ClickHouse. Adapted from the skeleton the lab checks (see README).

Environment:
  SCAN_ROOTS     name=path[,name=path...]        required
  EXCLUDE_DIRS   comma-separated directory names  optional
  MODE           full | incremental               default full
  SINCE          unix seconds; incremental only indexes files with mtime > SINCE
  DETECT_DELETES 1 = after a full scan, mark rows this scan did not see as deleted
  BATCH          rows per INSERT                  default 20000
  HASH_MAX_MB    hash files up to this size; 0 = no hashing   default 0
  TEXT_MAX_KB    read the first N KB of .txt/.md into text_excerpt; 0 = none   default 0
  CH_HOST CH_PORT CH_USER CH_PASSWORD CH_SECURE(0/1)

Changes from the skeleton, each checked in the lab:
  - connection is configurable (local HTTP 8123 without TLS; Cloud 8443 with TLS)
  - incremental mode is implemented (the skeleton described it but always scanned everything)
  - delete detection runs here, only after a full scan, with a bound parameter
  - text_excerpt is filled for plain-text files when TEXT_MAX_KB > 0
"""
import hashlib, json, os, sys, time
from pathlib import Path
import clickhouse_connect

SCAN_ROOTS = dict(p.split("=", 1) for p in os.environ["SCAN_ROOTS"].split(","))
EXCLUDE_DIRS = set(filter(None, os.getenv("EXCLUDE_DIRS", "").split(",")))
MODE = os.getenv("MODE", "full")
SINCE = int(os.getenv("SINCE", "0"))
DETECT_DELETES = os.getenv("DETECT_DELETES", "0") == "1"
BATCH = int(os.getenv("BATCH", "20000"))
HASH_MAX_MB = int(os.getenv("HASH_MAX_MB", "0"))
TEXT_MAX_KB = int(os.getenv("TEXT_MAX_KB", "0"))
TEXT_EXT = {"txt", "md"}

COLS = ["root", "path", "name", "ext", "size", "mtime", "is_dir", "depth",
        "owner", "content_hash", "text_excerpt", "scan_id", "is_deleted", "indexed_at"]

secure = os.getenv("CH_SECURE", "0") == "1"
client = clickhouse_connect.get_client(
    host=os.environ["CH_HOST"], port=int(os.getenv("CH_PORT", "8443" if secure else "8123")),
    username=os.environ["CH_USER"], password=os.environ["CH_PASSWORD"], secure=secure)
scan_id = time.time_ns() // 1000          # microseconds: two scans in one second still differ
now = int(time.time())


def file_hash(p: Path, size: int) -> str:
    if not HASH_MAX_MB or size > HASH_MAX_MB * 1024 * 1024:
        return ""
    h = hashlib.blake2b(digest_size=16)
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def excerpt(p: Path, ext: str) -> str:
    if not TEXT_MAX_KB or ext not in TEXT_EXT:
        return ""
    with p.open("rb") as f:
        return f.read(TEXT_MAX_KB * 1024).decode("utf-8", "replace")


def rows_for(root_name: str, root_path: str):
    base = Path(root_path)
    for dirpath, dirnames, filenames in os.walk(base, onerror=lambda e: None):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        d = Path(dirpath)
        for fn in filenames:
            p = d / fn
            try:
                st = p.stat()
            except OSError:
                continue
            if MODE == "incremental" and int(st.st_mtime) <= SINCE:
                continue
            rel = str(p.relative_to(base))
            ext = p.suffix.lower().lstrip(".")
            yield [root_name, rel, fn, ext, st.st_size, int(st.st_mtime), 0, rel.count(os.sep),
                   str(st.st_uid), file_hash(p, st.st_size), excerpt(p, ext), scan_id, 0, now]


t0 = time.time()
buf, n, inserts = [], 0, 0
for name, path in SCAN_ROOTS.items():
    for row in rows_for(name, path):
        buf.append(row)
        if len(buf) >= BATCH:
            client.insert("fileidx.file_index", buf, column_names=COLS); inserts += 1
            n += len(buf); buf.clear()
if buf:
    client.insert("fileidx.file_index", buf, column_names=COLS); inserts += 1
    n += len(buf)

deleted = 0
if DETECT_DELETES:
    if MODE != "full":
        sys.exit("DETECT_DELETES=1 is only valid after MODE=full: an incremental scan does not touch unchanged files")
    before = client.query("SELECT count() FROM fileidx.file_index FINAL WHERE is_deleted = 0 AND scan_id < {s:UInt64}",
                          parameters={"s": scan_id}).result_rows[0][0]
    client.command("""
        INSERT INTO fileidx.file_index
            (root, path, name, ext, size, mtime, is_dir, depth, owner, content_hash, text_excerpt, scan_id, is_deleted, indexed_at)
        SELECT root, path, name, ext, size, mtime, is_dir, depth, owner, content_hash, text_excerpt, {s:UInt64}, 1, now()
        FROM fileidx.file_index FINAL
        WHERE is_deleted = 0 AND scan_id < {s:UInt64}""", parameters={"s": scan_id})
    deleted = before

print(json.dumps({"scan_id": scan_id, "mode": MODE, "rows": n, "inserts": inserts,
                  "marked_deleted": deleted, "seconds": round(time.time() - t0, 2)}))
