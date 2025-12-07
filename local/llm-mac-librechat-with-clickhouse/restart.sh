#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Restarting LibreChat services..."
echo ""

./stop.sh
sleep 3
./start.sh
