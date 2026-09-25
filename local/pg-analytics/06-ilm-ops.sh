#!/usr/bin/env bash
# Phase 4: erasure deletes, freshness lag, snapshot expiry. Modifies the snapshot: run last.
source "$(dirname "$0")/_lib.sh"
SF=${1:?usage: $0 <sf>}
runner runner/ilm_ops.py deletes "$SF"
runner runner/ilm_ops.py freshness "$SF"
runner runner/ilm_ops.py expiry "$SF"
