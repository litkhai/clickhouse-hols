#!/usr/bin/env bash
# §5.4: the same Q6 / Q3 straight on pgduck_server and ClickHouse (FDW overhead).
source "$(dirname "$0")/_lib.sh"
runner runner/direct.py "${1:?usage: $0 <sf>}"
