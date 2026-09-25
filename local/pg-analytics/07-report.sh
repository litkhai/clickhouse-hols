#!/usr/bin/env bash
# Build results/REPORT data tables and charts from every results/sf*/ directory.
source "$(dirname "$0")/_lib.sh"
runner analysis/report.py
