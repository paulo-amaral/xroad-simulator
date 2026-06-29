#!/usr/bin/env bash
# Best-effort automation of Central Server initialization via the management REST API.
# Idempotent and tolerant: each step reports its status and continues; fall back to the UI
# (README Step 2) for anything that fails. This also generates and ACTIVATES the internal and
# external configuration signing keys, which fixes:
#   "Global configuration generation failing ... Signing of external configuration failed - active key missing"
#
# Endpoints/fields follow the CS OpenAPI (initialization, tokens/{id}/login, configuration-sources
# /{type}/signing-keys, signing-keys/{id}/activate). Override anything via env vars.
set -uo pipefail

CS_URL="${CS_URL:-https://localhost:4000}"
XROAD_ADMIN="${XROAD_ADMIN:-xrd:secret}"
INSTANCE="${XROAD_INSTANCE:-TL-TEST}"
CS_ADDRESS="${CS_ADDRESS:-cs}"
TOKEN_PIN="${TOKEN_PIN:-123456xrd!}"
TOKEN_ID="${TOKEN_ID:-0}"
ROLES='["XROAD_SYSTEM_ADMINISTRATOR","XROAD_REGISTRATION_OFFICER","XROAD_SECURITY_OFFICER"]'

log()  { printf '\033[1;34m[init-cs]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[init-cs]\033[0m %s\n' "$*" >&2; }

jget() { python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('$1',''))" 2>/dev/null; }

# api METHOD PATH [JSON_BODY] -> prints "HTTPSTATUS\nBODY"
api() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -ksS -X "$method" "${CS_URL}/api/v1${path}" \
      -H "Authorization: X-Road-ApiKey token=${API_KEY}" \
      -H "Content-Type: application/json" -d "$body" -w $'\n%{http_code}'
  else
    curl -ksS -X "$method" "${CS_URL}/api/v1${path}" \
      -H "Authorization: X-Road-ApiKey token=${API_KEY}" -w $'\n%{http_code}'
  fi
}

# 1. API key (basic auth)
log "creating a management API key"
resp="$(curl -ksS -u "${XROAD_ADMIN}" -H "Content-Type: application/json" \
          -X POST "${CS_URL}/api/v1/api-keys" -d "${ROLES}" 2>/dev/null)"
API_KEY="$(printf '%s' "${resp}" | jget key)"
[ -n "${API_KEY}" ] || { warn "could not create API key (is the CS up?). Aborting."; exit 1; }

# 2. Initialize (tolerant: may already be initialized)
log "initializing instance ${INSTANCE}"
out="$(api POST /initialization "{\"software_token_pin\":\"${TOKEN_PIN}\",\"instance_identifier\":\"${INSTANCE}\",\"central_server_address\":\"${CS_ADDRESS}\"}")"
code="$(printf '%s' "$out" | tail -1)"
case "$code" in 200|201|204) log "initialized";; 409) log "already initialized (ok)";; *) warn "initialization returned HTTP ${code} (continuing)";; esac

# 3. Log in to the signing token
log "logging in to token ${TOKEN_ID}"
out="$(api PUT "/tokens/${TOKEN_ID}/login" "{\"password\":\"${TOKEN_PIN}\"}")"
code="$(printf '%s' "$out" | tail -1)"
case "$code" in 200|204) log "token logged in";; 409) log "token already logged in (ok)";; *) warn "token login returned HTTP ${code} (continuing)";; esac

# 4. Generate + activate signing keys for both configuration sources (fixes the error)
for src in INTERNAL EXTERNAL; do
  log "generating ${src} configuration signing key"
  out="$(api POST "/configuration-sources/${src}/signing-keys" "{\"key_label\":\"${src}-key\",\"token_id\":\"${TOKEN_ID}\"}")"
  code="$(printf '%s' "$out" | tail -1)"
  body="$(printf '%s' "$out" | sed '$d')"
  key_id="$(printf '%s' "$body" | jget id)"
  if [ -z "$key_id" ]; then
    warn "${src}: could not read new key id (HTTP ${code}); generate/activate it in the UI"
    continue
  fi
  log "activating ${src} key ${key_id}"
  out="$(api PUT "/signing-keys/${key_id}/activate")"
  code="$(printf '%s' "$out" | tail -1)"
  case "$code" in 200|204) log "${src} key active";; *) warn "${src} activate returned HTTP ${code} (activate it in the UI)";; esac
done

log "done. If global-config generation was failing, it should recover within a minute."
log "next: tools/scripts/generate-anchor.sh   (downloads the anchor)"
