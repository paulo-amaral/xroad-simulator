#!/usr/bin/env bash
# Download the internal global-configuration anchor from the Central Server into anchors/.
# The Security Servers and `xrdsst init` need this file. The anchor exists ONLY after the
# Central Server has been initialized (instance TL-TEST, software token) - see README Step 2.
#
# Easy path: this script creates its own management API key through the same session login used by
# the Central Server UI (XROAD_ADMIN, default xrd:secret). Set CS_API_KEY to skip creation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"   # tools/scripts -> example root

CS_URL="${CS_URL:-https://localhost:4000}"
XROAD_ADMIN="${XROAD_ADMIN:-xrd:secret}"
OUT="${ANCHOR_OUT:-${SANDBOX_DIR}/xroad/anchors/TL-TEST-anchor.xml}"
# Endpoint is version-dependent; override with CS_ANCHOR_ENDPOINT if needed (see CS OpenAPI).
ENDPOINT="${CS_ANCHOR_ENDPOINT:-/api/v1/configuration-sources/INTERNAL/anchor/download}"
ROLES='["XROAD_SYSTEM_ADMINISTRATOR","XROAD_REGISTRATION_OFFICER","XROAD_SECURITY_OFFICER"]'

log()  { printf '\033[1;34m[anchor]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[anchor]\033[0m %s\n' "$*" >&2; }

mkdir -p "$(dirname "${OUT}")"

instructions() {
  cat >&2 <<EOF
[anchor] Could not obtain the anchor automatically. The Central Server must be initialized first
  (README Step 2: set instance TL-TEST, add the Test CA + TSA). Then re-run:  scripts/generate-anchor.sh
  Or download it from the UI: ${CS_URL} -> Global Configuration -> Internal Configuration -> Download anchor
  and save it as: ${OUT}
EOF
}

# Obtain an API key: create one with a UI session unless CS_API_KEY is already set.
if [ -z "${CS_API_KEY:-}" ]; then
  log "creating a management API key via UI session (${XROAD_ADMIN%%:*}@${CS_URL})"
  jar="$(mktemp)"
  trap 'rm -f "${jar:-}"' EXIT
  user="${XROAD_ADMIN%%:*}"
  pass="${XROAD_ADMIN#*:}"
  curl -ksS -c "${jar}" -o /dev/null "${CS_URL}/" || true
  xsrf="$(awk '$6=="XSRF-TOKEN"{print $7}' "${jar}" | tail -1)"
  curl -ksS -b "${jar}" -c "${jar}" -H "X-XSRF-TOKEN: ${xsrf}" -o /dev/null \
    --data-urlencode "username=${user}" --data-urlencode "password=${pass}" "${CS_URL}/login" || true
  xsrf="$(awk '$6=="XSRF-TOKEN"{print $7}' "${jar}" | tail -1)"
  resp="$(curl -ksS -b "${jar}" -H "X-XSRF-TOKEN: ${xsrf}" -H "Content-Type: application/json" \
            -X POST "${CS_URL}/api/v1/api-keys" -d "${ROLES}" 2>/dev/null || true)"
  CS_API_KEY="$(printf '%s' "${resp}" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("key", ""))
except Exception:
    print("")')"
  if [ -z "${CS_API_KEY}" ]; then
    warn "API key creation failed (is the Central Server up and initialized?)"
    instructions
    exit 1
  fi
  log "API key created"
fi

log "downloading internal configuration anchor from ${CS_URL}${ENDPOINT}"
if curl -ksSf -H "Authorization: X-Road-ApiKey token=${CS_API_KEY}" \
     "${CS_URL}${ENDPOINT}" -o "${OUT}" \
   && grep -qi "configurationAnchor\|<?xml" "${OUT}" 2>/dev/null; then
  log "anchor saved to ${OUT}"
else
  rm -f "${OUT}"
  warn "download failed or response was not an anchor (is the Central Server initialized?)"
  instructions
  exit 1
fi
