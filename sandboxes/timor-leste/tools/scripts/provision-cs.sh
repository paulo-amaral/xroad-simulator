#!/usr/bin/env bash
# Auto-provision the Central Server for the Timor-Leste sandbox, no UI clicks.
# Uses only the Central Server management REST API. No direct database writes.
# Idempotent: anything that already exists returns 409 and is treated as OK.
#
# Covers: instance init, signing-token login, internal+external signing keys, member class GOV,
# the 5 members, their subsystems, and the management service provider.
# Still handled by companion scripts: Test CA + TSA, and the Security Server certificate dance.
set -uo pipefail

CS_URL="${CS_URL:-https://localhost:4000}"
COMPOSE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/docker-compose.yml"
INSTANCE="${XROAD_INSTANCE:-TL-TEST}"
CS_ADDRESS="${CS_ADDRESS:-cs}"
PIN="${TOKEN_PIN:-Sandbox_2026}"
TOKEN_ID="${TOKEN_ID:-0}"

# member code : member name
MEMBERS=(
  "01:Government of Timor-Leste"
  "MJ:Ministry of Justice"
  "SERVE:SERVE I.P."
  "MTC:Ministry of Transport and Communications"
  "OSS:Balkaun Uniku"
)
# member code | subsystem code | professional display name
SUBSYSTEMS=(
  "01|MANAGEMENT|X-Road Management Services"
  "MJ|JUSTICE|Civil Registry Services"
  "SERVE|REGISTRY|SERVE I.P. Business Registry (eKYB)"
  "MTC|DNTT|Land Transport and Driver Licensing Services"
  "OSS|PORTAL|One-Stop-Shop Citizen Services Portal"
)
# The management-services PATCH wants the plain subsystem id WITHOUT the "SUBSYSTEM:" prefix
# (the API rejects the prefixed form with invalid_service_provider_id, then stores/returns it prefixed).
MGMT_PROVIDER="${INSTANCE}:GOV:01:MANAGEMENT"

log()  { printf '\033[1;34m[provision-cs]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[provision-cs]\033[0m %s\n' "$*" >&2; }

dc() { docker compose -f "$COMPOSE" "$@"; }

# Create a management API key through the same session login used by the admin UI and print the token.
create_api_key() {
  local admin="${XROAD_ADMIN:-xrd:secret}" user pass jar xsrf
  user="${admin%%:*}"
  pass="${admin#*:}"
  jar="$(mktemp)"
  curl -ksS -c "${jar}" -o /dev/null "${CS_URL}/" || true
  xsrf="$(awk '$6=="XSRF-TOKEN"{print $7}' "${jar}" | tail -1)"
  curl -ksS -b "${jar}" -c "${jar}" -H "X-XSRF-TOKEN: ${xsrf}" -o /dev/null \
    --data-urlencode "username=${user}" --data-urlencode "password=${pass}" "${CS_URL}/login" || true
  xsrf="$(awk '$6=="XSRF-TOKEN"{print $7}' "${jar}" | tail -1)"
  curl -ksS -b "${jar}" -H "X-XSRF-TOKEN: ${xsrf}" -H "Content-Type: application/json" \
    -X POST "${CS_URL}/api/v1/api-keys" \
    -d '["XROAD_SYSTEM_ADMINISTRATOR","XROAD_SECURITY_OFFICER","XROAD_REGISTRATION_OFFICER","XROAD_MANAGEMENT_SERVICE"]' |
    python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("key", ""))
except Exception:
    print("")'
  rm -f "${jar}"
}

# api METHOD PATH [BODY] -> echoes HTTP status; treats 2xx and 409 as success
api() {
  local m="$1" p="$2" body="${3:-}" code
  if [ -n "$body" ]; then
    code=$(curl -ksS -o /dev/null -w '%{http_code}' -H "$AUTH" -H "Content-Type: application/json" -X "$m" "${CS_URL}${p}" -d "$body")
  else
    code=$(curl -ksS -o /dev/null -w '%{http_code}' -H "$AUTH" -X "$m" "${CS_URL}${p}")
  fi
  printf %s "$code"
}
ok() { case "$1" in 2*|409) return 0;; *) return 1;; esac; }

dc ps cs >/dev/null 2>&1 || { warn "Central Server container not running"; exit 1; }

if [ -n "${CS_API_KEY:-}" ]; then
  log "using existing management API key from CS_API_KEY"
  KEY="${CS_API_KEY}"
else
  log "creating a management API key via UI session"
  KEY="$(create_api_key | tr -d '[:space:]')"
  [ -n "$KEY" ] || { warn "failed to create API key via UI session; check Central Server login readiness"; exit 1; }
fi
AUTH="Authorization: X-Road-ApiKey token=$KEY"
log "API key ready (${KEY:0:6}...)"

log "initialize instance ${INSTANCE}"
c=$(api POST /api/v1/initialization "{\"software_token_pin\":\"${PIN}\",\"instance_identifier\":\"${INSTANCE}\",\"central_server_address\":\"${CS_ADDRESS}\"}"); ok "$c" && log "  init ($c)" || warn "  init HTTP $c"

log "log in to signing token ${TOKEN_ID}"
c=$(api PUT "/api/v1/tokens/${TOKEN_ID}/login" "{\"password\":\"${PIN}\"}"); ok "$c" && log "  token login ($c)" || warn "  token login HTTP $c"

# Signing keys: there is no list endpoint (GET returns 405), so guard with the generation status.
# If global conf already generates, both sources already have an active key -> skip (idempotent).
gstatus=$(dc exec -T cs sh -lc 'cat /var/log/xroad/.global_conf_gen_status 2>/dev/null' | tr -d '[:space:]')
if printf '%s' "$gstatus" | grep -q '"success":true'; then
  log "signing keys already active (global conf generates) - skipping"
else
  for src in INTERNAL EXTERNAL; do
    log "generate + activate ${src} signing key"
    resp=$(curl -ksS -H "$AUTH" -H "Content-Type: application/json" -X POST \
      "${CS_URL}/api/v1/configuration-sources/${src}/signing-keys" -d "{\"key_label\":\"${src}-key\",\"token_id\":\"${TOKEN_ID}\"}")
    id=$(printf %s "$resp" | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
    [ -n "$id" ] && { c=$(api PUT "/api/v1/signing-keys/${id}/activate"); ok "$c" && log "  ${src} active" || warn "  activate HTTP $c"; } || warn "  could not read ${src} key id"
  done
fi

log "member class GOV"
c=$(api POST /api/v1/member-classes '{"code":"GOV","description":"Government"}'); ok "$c" && log "  GOV ($c)" || warn "  member-class HTTP $c"

for m in "${MEMBERS[@]}"; do
  code="${m%%:*}"; name="${m#*:}"
  c=$(api POST /api/v1/members "{\"member_id\":{\"member_class\":\"GOV\",\"member_code\":\"${code}\"},\"member_name\":\"${name}\"}")
  ok "$c" && log "  member GOV/${code} ($c)" || warn "  member GOV/${code} HTTP $c"
done

for s in "${SUBSYSTEMS[@]}"; do
  code="${s%%|*}"; rest="${s#*|}"; sub="${rest%%|*}"; name="${rest#*|}"
  body="{\"subsystem_id\":{\"member_class\":\"GOV\",\"member_code\":\"${code}\",\"subsystem_code\":\"${sub}\"},\"subsystem_name\":\"${name}\"}"
  c=$(api POST /api/v1/subsystems "$body")
  ok "$c" && log "  subsystem GOV/${code}/${sub} ($c)" || warn "  subsystem GOV/${code}/${sub} HTTP $c"
  c=$(api PATCH "/api/v1/subsystems/${INSTANCE}:GOV:${code}:${sub}" "{\"subsystem_name\":\"${name}\"}")
  ok "$c" && log "  subsystem name GOV/${code}/${sub} ($c)" || warn "  subsystem name GOV/${code}/${sub} HTTP $c"
done

log "management service provider -> ${MGMT_PROVIDER}"
# Fatal if this fails: without the provider set, the global configuration never generates
# (managementService element incomplete) and init.sh hangs forever at "waiting for global conf".
c=$(api PATCH /api/v1/management-services-configuration "{\"service_provider_id\":\"${MGMT_PROVIDER}\"}")
ok "$c" && log "  set ($c)" || { warn "management service provider not set (HTTP $c) — global conf cannot generate"; exit 1; }

log "done. Verify generation:"
log "  docker compose exec -T cs sh -lc 'cat /var/log/xroad/.global_conf_gen_status'   # expect success:true"
log "Still to do: add Test CA + TSA (Trust Services), then provision the Security Servers with xrdsst (README Step 3)."
