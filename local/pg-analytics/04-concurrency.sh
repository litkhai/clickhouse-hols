#!/usr/bin/env bash
# Phase 3: closed-loop clients 1/4/8/16 on Q6 and Q3.
source "$(dirname "$0")/_lib.sh"
SF=${1:?usage: $0 <sf> [concurrency.py args]}; shift
runner runner/concurrency.py --sf "$SF" "$@"
