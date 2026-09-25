#!/usr/bin/env bash
# Phase 2 matrix for one scale factor, both resource modes.
#   ./03-bench.sh 10              all paths, per-node, then path C equal-total
#   ./03-bench.sh 10 --queries q06 --iters 2      (extra args go to bench.py)
source "$(dirname "$0")/_lib.sh"
SF=${1:?usage: $0 <sf> [bench.py args]}; shift
runner runner/bench.py --sf "$SF" "$@"
if [ $# -eq 0 ]; then
  runner runner/bench.py --sf "$SF" --paths C --resource-mode equal-total
fi
