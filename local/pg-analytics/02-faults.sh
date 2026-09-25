#!/usr/bin/env bash
# Phase 1 fault injection: kill pg-main / stop Polaris during tiering commits.
source "$(dirname "$0")/_lib.sh"
runner runner/faults.py "${1:?usage: $0 <sf>}"
