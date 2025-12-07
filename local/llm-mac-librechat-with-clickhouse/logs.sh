#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if docker compose or docker-compose
if docker compose version &> /dev/null; then
    docker compose logs -f "$@"
else
    docker-compose logs -f "$@"
fi
