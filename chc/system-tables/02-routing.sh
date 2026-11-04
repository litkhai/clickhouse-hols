#!/usr/bin/env bash
# 02 — Ten new connections: which replica does each land on?
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
echo "-- ten connections, one query each: SELECT hostName()"
for _ in $(seq 1 10); do ch --format TSV -q "SELECT hostName()"; done | mask | sort | uniq -c
