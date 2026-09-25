#!/usr/bin/env bash
# Phase 1 + Phase 0 for one scale factor: heap load, monthly tiering into
# Iceberg (Polaris), VACUUM, reader wiring (ClickHouse, pg_clickhouse, pg_duckdb),
# then the integration gate.   usage: ./01-load.sh 10
source "$(dirname "$0")/_lib.sh"
SF=${1:?usage: $0 <sf>}
runner runner/setup.py all "$SF"
runner runner/verify.py "$SF"
