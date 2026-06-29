#!/usr/bin/env bash
# Create Security Server management API keys and persist them to examples/timor-leste/.env.
# Uses the supported UI session flow: POST /login, then POST /api/v1/api-keys.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${SANDBOX_DIR}/docker-compose.yml"
ENV_FILE="${ENV_FILE:-${SANDBOX_DIR}/.env}"
XROAD_ADMIN="${XRDSST_ADMIN:-${XROAD_ADMIN:-xrd:secret}}"
ADMIN_USER="${XROAD_ADMIN%%:*}"
ADMIN_PASSWORD="${XROAD_ADMIN#*:}"
ROLES='["XROAD_SYSTEM_ADMINISTRATOR","XROAD_SERVICE_ADMINISTRATOR","XROAD_SECURITY_OFFICER","XROAD_REGISTRATION_OFFICER"]'

log()  { printf '\033[1;34m[ss-keys]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ss-keys] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

set_env() {
  local name="$1" value="$2"
  touch "${ENV_FILE}"
  if grep -q "^${name}=" "${ENV_FILE}"; then
    sed -i.bak "s|^${name}=.*|${name}=${value}|" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${name}" "${value}" >> "${ENV_FILE}"
  fi
}

create_key() {
  local name="$1" var="$2"
  log "creating API key for ${name}"
  local resp key
  resp="$(docker compose -f "${COMPOSE_FILE}" exec -T "${name}" sh -lc "
    set -e
    rm -f /tmp/xroad-api-cookie
    curl -ksS -c /tmp/xroad-api-cookie https://localhost:4000/ >/dev/null
    curl -ksS -b /tmp/xroad-api-cookie -c /tmp/xroad-api-cookie \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      -X POST https://localhost:4000/login \
      --data-urlencode 'username=${ADMIN_USER}' \
      --data-urlencode 'password=${ADMIN_PASSWORD}' >/dev/null
    xsrf=\$(awk '/XSRF-TOKEN/ {print \$7}' /tmp/xroad-api-cookie | tail -1)
    curl -ksS -b /tmp/xroad-api-cookie \
      -H \"X-XSRF-TOKEN: \${xsrf}\" \
      -H 'Content-Type: application/json' \
      -X POST https://localhost:4000/api/v1/api-keys \
      -d '${ROLES}'
  ")"
  key="$(printf '%s' "${resp}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key", ""))')"
  [ -n "${key}" ] || fail "no key returned for ${name}: ${resp}"
  set_env "${var}" "${key}"
}

[ -f "${ENV_FILE}" ] || cp "${SANDBOX_DIR}/../../.env.example" "${ENV_FILE}"

create_key ss-mj SS_MJ_API_KEY
create_key ss-moh SS_MOH_API_KEY
create_key ss-mtc SS_MTC_API_KEY
create_key ss-oss SS_OSS_API_KEY

rm -f "${ENV_FILE}.bak"
log "updated ${ENV_FILE}"
