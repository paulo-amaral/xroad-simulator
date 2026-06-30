#!/usr/bin/env bash
# Run the Hurl E2E checks, matching the upstream xrd-dev-stack execution style.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker compose -f "${ROOT}/docker-compose.yml" \
  --profile test run --rm --no-deps hurl \
  --insecure \
  --file-root /tools \
  --test /tools/e2e.hurl \
  --retry 12 \
  --retry-interval 10000
