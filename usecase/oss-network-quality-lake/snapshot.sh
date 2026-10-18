#!/usr/bin/env bash
# Write site/data/snapshot.json (layer counts, the story's sample rows, the 20 cells with
# their H3 boundaries, per-layer query time) from a ClickHouse that has run 01-03.
#   CH_URL=http://localhost:18123 ./snapshot.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
python3 ui/server.py --snapshot
python3 site/build.py
