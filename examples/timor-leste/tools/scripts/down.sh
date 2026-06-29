#!/usr/bin/env bash
# Tear down the Timor-Leste X-Road sandbox.
# Pass --keep-data to stop containers but preserve volumes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$(cd "${SCRIPT_DIR}/../.." && pwd)/docker-compose.yml"

if [ "${1:-}" = "--keep-data" ]; then
  docker compose -f "${COMPOSE_FILE}" down
else
  docker compose -f "${COMPOSE_FILE}" down -v
fi
echo "[down] sandbox stopped"
