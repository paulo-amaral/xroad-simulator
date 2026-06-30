#!/usr/bin/env bash
# Stop the Timor-Leste X-Road sandbox without deleting persistent state.
# Pass --wipe to remove containers and volumes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$(cd "${SCRIPT_DIR}/../.." && pwd)/docker-compose.yml"

if [ "${1:-}" = "--wipe" ]; then
  docker compose -f "${COMPOSE_FILE}" down -v
else
  docker compose -f "${COMPOSE_FILE}" stop
fi
echo "[down] sandbox stopped"
