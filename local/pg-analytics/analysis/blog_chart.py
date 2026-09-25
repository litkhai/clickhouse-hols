"""Per-query warm p50 for the blog post: A, B', C and C with join swap.

    python analysis/blog_chart.py [sf]      -> results/charts/query_latency_sf<N>.png
"""
import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

LAB = Path(__file__).resolve().parent.parent
QUERIES = ["q06", "c1", "q01", "c2", "q03", "q05", "q18", "c5", "c6"]
NAMES = {"q06": "Q6", "c1": "C1", "q01": "Q1", "c2": "C2", "q03": "Q3", "q05": "Q5",
         "q18": "Q18", "c5": "C5", "c6": "C6"}
TIER = {"q06": "L1", "c1": "L1", "q01": "L1", "c2": "L2", "q03": "L3", "q05": "L3",
        "q18": "L4", "c5": "L5", "c6": "L5"}
SERIES = [  # (path, resource_mode, label, color, hatch)
    ("A", "per-node", "A pg_lake", "#2a78d6", None),
    ("B2", "per-node", "B′ pg_duckdb main", "#eda100", None),
    ("C", "per-node", "C pg_clickhouse", "#1baf7a", None),
    ("C", "join-swap", "C + join swap", "#1baf7a", "////"),
]
INK, MUTED, GRID = "#1f2328", "#59636e", "#e3e6ea"


def main(sf):
    lat = defaultdict(list)
    for r in csv.DictReader(open(LAB / "results" / f"sf{sf}" / "bench.csv")):
        if r["run_type"] == "warm" and r["status"] == "ok" and r["dim_scenario"] == "D1":
            lat[(r["path"], r["resource_mode"], r["query_id"])].append(float(r["latency_ms"]))
    fig, ax = plt.subplots(figsize=(10, 4.6), dpi=150)
    width = 0.2
    for i, (path, mode, label, color, hatch) in enumerate(SERIES):
        xs, ys = [], []
        for j, q in enumerate(QUERIES):
            v = lat.get((path, mode, q))
            if v:
                xs.append(j + (i - 1.5) * width)
                ys.append(statistics.median(v) / 1000)
        ax.bar(xs, ys, width * 0.9, label=label, color="white" if hatch else color,
               edgecolor=color, hatch=hatch, linewidth=1.2 if hatch else 0)
    ax.set_yscale("log")
    ax.set_xticks(range(len(QUERIES)))
    ax.set_xticklabels([f"{NAMES[q]}\n{TIER[q]}" for q in QUERIES], color=INK, fontsize=9)
    ax.set_ylabel("warm p50 (s, log scale)", color=MUTED, fontsize=9)
    ax.set_title(f"TPC-H SF{sf} on pg_lake's Iceberg — warm latency per query", loc="left",
                 color=INK, fontsize=11)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.spines["left"].set_color(GRID)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=MUTED, labelsize=8)
    ax.legend(frameon=False, fontsize=8, ncol=4, loc="upper left")
    fig.tight_layout()
    out = LAB / "results" / "charts" / f"query_latency_sf{sf}.png"
    fig.savefig(out)
    print(f"wrote {out.relative_to(LAB)}")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 10)
