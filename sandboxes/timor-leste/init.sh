#!/usr/bin/env bash
# One-command setup for the Timor-Leste X-Road sandbox.
# Follows the official xrd-dev-stack bootstrap shape: Central Server and trust
# first, then Security Server keys/certificates/registration, then clients/ACLs,
# then an end-to-end verification. All provisioning uses supported REST APIs and
# xrdsst; no direct database writes.

set -euo pipefail

log() { printf '\n\033[1;32m[setup]\033[0m %s\n' "$*"; }
progress_line() {
    local elapsed=$1 total=$2 label=$3 width=24 filled empty
    [ "$elapsed" -gt "$total" ] && elapsed=$total
    filled=$(( elapsed * width / total ))
    empty=$(( width - filled ))
    printf '\r  [%s%s] %ss/%ss %s' \
        "$(printf '%*s' "$filled" '' | tr ' ' '#')" \
        "$(printf '%*s' "$empty" '' | tr ' ' '.')" \
        "$elapsed" "$total" "$label"
}
progress_done() {
    local label=$1 width=24
    printf '\r  [%s] done %s\n' "$(printf '%*s' "$width" '' | tr ' ' '#')" "$label"
}
wait_for_global_conf() {
    local label=$1 elapsed=0 interval=5 expected=60
    log "$label"
    while ! docker compose exec -T cs sh -lc 'cat /var/log/xroad/.global_conf_gen_status 2>/dev/null' | grep -q '"success":true'; do
        sleep "$interval"
        elapsed=$((elapsed + interval))
        progress_line "$elapsed" "$expected" "global configuration"
    done
    progress_done "global configuration"
}
wait_for_ss_admin() {
    local ss=$1 elapsed=0 interval=5 expected=120
    while ! docker compose exec -T "$ss" sh -lc 'curl -ksSf -o /dev/null https://localhost:4000/' 2>/dev/null; do
        sleep "$interval"
        elapsed=$((elapsed + interval))
        progress_line "$elapsed" "$expected" "$ss admin API"
    done
    progress_done "$ss admin API"
}

log "1. Checking prerequisites and starting Docker ecosystem..."
tools/scripts/install.sh

log "2. Creating API Key for Central Server provisioning (session login)..."
# This Central Server image rejects HTTP basic auth on /api/v1, so authenticate the same way the
# admin UI does: GET / for the XSRF-TOKEN cookie, POST /login, then create the key on that session.
CS_URL="https://localhost:4000"
J="$(mktemp)"
curl -ksS -c "$J" -o /dev/null "${CS_URL}/"
XSRF=$(awk '$6=="XSRF-TOKEN"{print $7}' "$J")
curl -ksS -b "$J" -c "$J" -H "X-XSRF-TOKEN: ${XSRF}" -o /dev/null \
    --data-urlencode "username=xrd" --data-urlencode "password=secret" "${CS_URL}/login"
XSRF=$(awk '$6=="XSRF-TOKEN"{print $7}' "$J")
CS_API_KEY=$(curl -ksS -b "$J" -H "X-XSRF-TOKEN: ${XSRF}" -H "Content-Type: application/json" \
    -X POST "${CS_URL}/api/v1/api-keys" \
    -d '["XROAD_SYSTEM_ADMINISTRATOR","XROAD_SECURITY_OFFICER","XROAD_REGISTRATION_OFFICER","XROAD_MANAGEMENT_SERVICE"]' | \
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("key", ""))')
rm -f "$J"
[ -n "$CS_API_KEY" ] || { echo "Failed to create CS API key"; exit 1; }
export CS_API_KEY

log "3. Provisioning Central Server (Instance, Tokens, Members)..."
tools/scripts/provision-cs.sh

log "4. Reconciling Trust Services (Test CA & TSA) to the current Test CA..."
AUTH="Authorization: X-Road-ApiKey token=$CS_API_KEY"
# The CA/TSA add returns 400 until the Central Server has generated its global configuration at
# least once (instance initialised + signing keys settled). Wait for the first success.
wait_for_global_conf "  waiting for the first global configuration generation (CA add 400s before it)..."
docker compose exec -T testca cat /home/ca/CA/certs/ca.cert.pem > tools/ca.pem
docker compose exec -T testca cat /home/ca/CA/certs/tsa.cert.pem > tools/tsa.pem

# Reconcile, do not blindly append. The Test CA regenerates its key whenever the testca-home volume
# is wiped, but the Central Server persists its trust list, so repeated runs used to accumulate
# several "Test CA" entries with the same subject DN and different keys. The Security Server matches
# CA and TSA by issuer DN, so a stale duplicate silently breaks OCSP and timestamp verification.
# Fingerprint the live Test CA / TSA, drop anything that does not match, and keep exactly one current.
# Compare by certificate generation time (not_before), which is unique per Test CA regeneration. The
# certification-services API does not expose a certificate hash (only timestamping does), but both
# expose not_before, so this is the one field we can read back from the CS for every trust service.
cert_notbefore() { openssl x509 -in "$1" -noout -startdate 2>/dev/null | sed 's/notBefore=//' | python3 -c 'import sys,datetime as d
try: print(int(d.datetime.strptime(sys.stdin.read().strip(),"%b %d %H:%M:%S %Y %Z").replace(tzinfo=d.timezone.utc).timestamp()))
except Exception: print("")'; }
svc_notbefore() { curl -ksS -H "$AUTH" "${CS_URL}/api/v1/$1/$2" | python3 -c 'import sys,json,datetime as d
o=json.load(sys.stdin); nb=o.get("not_before") or o.get("certificate",{}).get("not_before")
try: print(int(d.datetime.strptime(nb,"%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=d.timezone.utc).timestamp()))
except Exception: print("")'; }
list_ids() { curl -ksS -H "$AUTH" "${CS_URL}/api/v1/$1" | python3 -c 'import json,sys;[print(x["id"]) for x in json.load(sys.stdin)]'; }
CA_NB="$(cert_notbefore tools/ca.pem)"; TSA_NB="$(cert_notbefore tools/tsa.pem)"
# Fail-safe: never delete trust services if we cannot read the live Test CA/TSA timestamps.
[ -n "$CA_NB" ] && [ -n "$TSA_NB" ] || { echo "  ERROR: cannot read live Test CA/TSA timestamps; aborting trust reconcile"; exit 1; }

# Drop stale certification services, keep the one matching the current Test CA.
CA_ID=""
for id in $(list_ids certification-services); do
    sb="$(svc_notbefore certification-services "$id")"
    if [ "$sb" = "$CA_NB" ]; then CA_ID="$id";
    elif [ -n "$sb" ]; then echo "  removing stale Test CA id=$id"; curl -ksS -o /dev/null -H "$AUTH" -X DELETE "${CS_URL}/api/v1/certification-services/${id}"; fi
done
if [ -z "$CA_ID" ]; then
    for i in $(seq 1 30); do
        HTTP_CODE=$(curl -ksS -o /tmp/ca-resp.json -w "%{http_code}" -H "$AUTH" \
            -F "certificate=@tools/ca.pem;type=application/octet-stream" \
            -F "certificate_profile_info=ee.ria.xroad.common.certificateprofile.impl.FiVRKCertificateProfileInfoProvider" \
            -F "tls_auth=false" -X POST "${CS_URL}/api/v1/certification-services")
        case "$HTTP_CODE" in 201) break;; esac
        sleep 6
    done
    [ "$HTTP_CODE" = "201" ] || { echo "  ERROR: Test CA add failed (HTTP $HTTP_CODE): $(cat /tmp/ca-resp.json 2>/dev/null)"; exit 1; }
    CA_ID=$(python3 -c 'import json;print(json.load(open("/tmp/ca-resp.json"))["id"])')
fi
echo "  Test CA reconciled (id=$CA_ID)"

# Ensure the OCSP responder exists on the current CA, exactly once.
if [ -z "$(curl -ksS -H "$AUTH" "${CS_URL}/api/v1/certification-services/${CA_ID}/ocsp-responders" | python3 -c 'import json,sys;print("y" if json.load(sys.stdin) else "")')" ]; then
    curl -ksS -o /dev/null -H "$AUTH" -F "url=http://testca:8888" -X POST "${CS_URL}/api/v1/certification-services/${CA_ID}/ocsp-responders"
    echo "  OCSP responder added"
fi

# Same reconciliation for timestamping services. The TSA must carry its certificate, or message
# timestamping fails and every management request returns 500.
TSA_OK=""
for id in $(list_ids timestamping-services); do
    sb="$(svc_notbefore timestamping-services "$id")"
    if [ "$sb" = "$TSA_NB" ]; then TSA_OK="$id";
    elif [ -n "$sb" ]; then echo "  removing stale TSA id=$id"; curl -ksS -o /dev/null -H "$AUTH" -X DELETE "${CS_URL}/api/v1/timestamping-services/${id}"; fi
done
if [ -z "$TSA_OK" ]; then
    for i in $(seq 1 30); do
        HTTP_CODE=$(curl -ksS -o /tmp/tsa-resp.json -w "%{http_code}" -H "$AUTH" \
            -F "certificate=@tools/tsa.pem" -F "url=http://testca:8899" -X POST "${CS_URL}/api/v1/timestamping-services")
        case "$HTTP_CODE" in 201) break;; esac
        sleep 6
    done
    [ "$HTTP_CODE" = "201" ] || { echo "  ERROR: TSA add failed (HTTP $HTTP_CODE): $(cat /tmp/tsa-resp.json 2>/dev/null)"; exit 1; }
fi
echo "  Test TSA reconciled"

rm -f tools/ca.pem tools/tsa.pem

wait_for_global_conf "5. Waiting for Global Configuration to generate..."

log "6. Downloading Configuration Anchor..."
tools/scripts/generate-anchor.sh

log "7. Preparing Security Servers with xrdsst (anchor, token, TSA, clients, CSRs)..."
log "  waiting for the Security Server admin APIs (emulated boot is slow)..."
for ss in ss-mj ss-serve ss-mtc ss-oss; do
  wait_for_ss_admin "$ss"
done
if [ ! -f .env ]; then
  cp ../../.env.example .env
fi
source .venv/bin/activate
tools/scripts/generate-ss-api-keys.sh
set -a; source .env; set +a
xrdsst -c xroad/config/xrdsst-config.yaml init
xrdsst -c xroad/config/xrdsst-config.yaml token login
xrdsst -c xroad/config/xrdsst-config.yaml timestamp init
xrdsst -c xroad/config/xrdsst-config.yaml client add
xrdsst -c xroad/config/xrdsst-config.yaml token init-keys
tools/scripts/provision-ss.sh

log "7b. Approving registrations, management provider, routable addresses and ACLs..."
set -a; source .env; set +a
tools/scripts/provision-mgmt.sh

log "8. Running Declarative E2E Tests via Hurl..."
tools/e2e-test.sh

log "✅ Initialization complete! The One-Stop-Shop portal is ready at http://localhost:8000"
