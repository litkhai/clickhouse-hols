"""Render excerpts of results/*.txt as terminal-style PNGs in images/ (for the README and the article).

Host only: python3 (standard library) and Google Chrome (headless screenshot). Run after ./run.sh.
The excerpts are cut from the result files by markers, so the images always show the latest run.
"""
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile

LAB = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(LAB, "results")
IMG = os.path.join(LAB, "images")
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
WIDTH = 1500
MAX_COLS = 190


def cut(name, start, end=None, nth=1, keep=None):
    """Lines of results/<name> from the nth line matching `start` up to (not incl.) the next `end`."""
    lines = open(os.path.join(RES, name)).read().splitlines()
    hits = [i for i, x in enumerate(lines) if re.search(start, x)]
    if len(hits) < nth:
        sys.exit(f"{name}: marker {start!r} (#{nth}) not found")
    i = hits[nth - 1]
    j = next((k for k in range(i + 1, len(lines)) if end and re.search(end, lines[k])), len(lines))
    out = lines[i:j]
    if keep:
        out = [x for x in out if re.search(keep, x)]
    return out


def ch_file():
    files = sorted(f for f in os.listdir(RES) if f.startswith("clickhouse-26.10"))
    return files[-1]


CAPTURES = [
    ("01-v1-delete-copy-on-write", "v1: DELETE rewrites data files; merge-on-read is refused",
     lambda: cut("spark-steps.txt", r"^-- step 5", r"^-- step 6", 1)),
    ("02-v2-position-delete-file", "v2: DELETE writes position delete files (data file, row position)",
     lambda: cut("inspect-t_v2.txt", r"^manifest list", r"^parquet schema", 1,
                 keep=r"'content': 1|-deletes\.parquet|position delete rows")),
    ("03-v3-deletion-vector", "v3: DELETE writes one deletion vector per data file, in a Puffin file",
     lambda: cut("inspect-t_v3.txt", r"^manifest list", r"^parquet schema", 1,
                 keep=r"'content': 1|\.puffin|deletion vector|puffin footer")),
    ("04-v3-row-lineage", "v3: row lineage after UPDATE id 3 (_row_id kept, sequence number moves)",
     lambda: cut("spark-steps.txt", r"row lineage", r"table contents", 3)),
    ("05-metadata-v1-v3", "metadata.json of a v1 and a v3 table",
     lambda: cut("inspect-t_v1.txt", r"^metadata files", r"^  snapshots") + [""]
     + cut("inspect-t_v3.txt", r"^metadata files", r"^manifest list")),
    ("06-upgrade-v2-to-v3", "v2 -> v3: the first DELETE after the upgrade merges the old position delete into a deletion vector",
     lambda: cut("spark-steps.txt", r"^-- first write after the upgrade", r"^  table contents")),
    ("07-variant", "v3 variant: refused on v1/v2; stored as two binary columns in Parquet",
     lambda: [x for x in open(os.path.join(RES, "spark-steps.txt")).read().splitlines() if "VARIANT" in x or "variant is not supported" in x]
     + [""] + cut("inspect-t_v3_variant.txt", r"^parquet schema")),
    ("08-clickhouse-26.10", "ClickHouse 26.10 reading the same tables",
     lambda: [x for x in cut(ch_file(), r"^# ClickHouse") if not x.lstrip().startswith("query:")]),
]


def page(title, lines):
    body = "\n".join(html.escape(x if len(x) <= MAX_COLS else x[:MAX_COLS - 1] + "…") for x in lines)
    return f"""<!doctype html><meta charset="utf-8"><style>
html,body{{margin:0;background:#0f1115}}
.t{{font:600 15px/1.4 -apple-system,Helvetica,sans-serif;color:#e8e8e8;padding:14px 20px 0}}
pre{{margin:0;padding:10px 20px 18px;font:13px/1.45 Menlo,Monaco,monospace;color:#d6deeb;white-space:pre}}
</style><div class="t">{html.escape(title)}</div><pre>{body}</pre>"""


def main():
    if not os.path.exists(CHROME):
        sys.exit(f"Chrome not found at {CHROME} (set CHROME)")
    os.makedirs(IMG, exist_ok=True)
    tmp = tempfile.mkdtemp()
    try:
        for name, title, get in CAPTURES:
            lines = get()
            src = os.path.join(tmp, name + ".html")
            open(src, "w").write(page(title, lines))
            height = 60 + 19 * len(lines)
            out = os.path.join(IMG, name + ".png")
            for attempt in range(3):  # headless Chrome fails now and then (exit 2); a retry is enough
                r = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                                    f"--user-data-dir={os.path.join(tmp, 'profile')}",
                                    f"--window-size={WIDTH},{height}", f"--screenshot={out}", "file://" + src],
                                   capture_output=True)
                if r.returncode == 0:
                    break
            else:
                sys.exit(f"Chrome failed on {name}: {r.stderr.decode()[-300:]}")
            print(f"images/{name}.png  ({len(lines)} lines)")
    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
