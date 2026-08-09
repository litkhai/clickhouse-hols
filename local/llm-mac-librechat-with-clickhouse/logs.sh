#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"
CONFIG_FILE="config.env"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if docker compose or docker-compose
if docker compose version &> /dev/null; then
    docker compose --env-file "$CONFIG_FILE" logs -f "$@"
else
    docker-compose --env-file "$CONFIG_FILE" logs -f "$@"
fi
