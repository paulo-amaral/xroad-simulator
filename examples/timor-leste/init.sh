#!/usr/bin/env bash
# One-command setup for the Timor-Leste X-Road sandbox.
# Follows the official xrd-dev-stack bootstrap shape: Central Server and trust
# first, then Security Server keys/certificates/registration, then clients/ACLs,
# then an end-to-end verification. All provisioning uses supported REST APIs and
# xrdsst; no direct database writes.

set -euo pipefail

log() { printf '\n\033[1;32m[setup]\033[0m %s\n' "$*"; }

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

log "4. Provisioning Trust Services (Test CA & TSA)..."
AUTH="Authorization: X-Road-ApiKey token=$CS_API_KEY"
# The CA/TSA add returns 400 until the Central Server has generated its global configuration at
# least once (instance initialised + signing keys settled). Wait for the first success.
log "  waiting for the first global configuration generation (CA add 400s before it)..."
until docker compose exec -T cs sh -lc 'cat /var/log/xroad/.global_conf_gen_status 2>/dev/null' | grep -q '"success":true'; do sleep 5; done
docker compose exec -T testca cat /home/ca/CA/certs/ca.cert.pem > tools/ca.pem
docker compose exec -T testca cat /home/ca/CA/certs/tsa.cert.pem > tools/tsa.pem

# Add the CA as a certification service on the Central Server (CS path is /certification-services,
# not /certificate-authorities which is the Security Server path). The profile is the FI *Provider*
# class to match the xrdsst FI profile. The CS backend can 400 right after init even though the UI
# responds, so retry until it accepts (201) or it already exists (409). Fatal if it never does —
# the Security Servers cannot validate certificates without the CA.
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -ksS -o /tmp/ca-resp.json -w "%{http_code}" -H "$AUTH" \
        -F "certificate=@tools/ca.pem;type=application/octet-stream" \
        -F "certificate_profile_info=ee.ria.xroad.common.certificateprofile.impl.FiVRKCertificateProfileInfoProvider" \
        -F "tls_auth=false" \
        -X POST "${CS_URL}/api/v1/certification-services")
    case "$HTTP_CODE" in 201|409) break;; esac
    sleep 6
done
case "$HTTP_CODE" in 201|409) echo "  Test CA configured (HTTP $HTTP_CODE)";; *) echo "  ERROR: Test CA add failed (HTTP $HTTP_CODE): $(cat /tmp/ca-resp.json 2>/dev/null)"; exit 1;; esac

# Find the CA id and add the OCSP responder (multipart, not JSON).
CA_ID=$(curl -ksS -H "$AUTH" "${CS_URL}/api/v1/certification-services" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(d[0]["id"] if isinstance(d,list) and d else "")')
if [ -n "$CA_ID" ]; then
    HTTP_CODE=$(curl -ksS -o /dev/null -w "%{http_code}" -H "$AUTH" \
        -F "url=http://testca:8888" \
        -X POST "${CS_URL}/api/v1/certification-services/${CA_ID}/ocsp-responders")
    echo "  OCSP Responder configured (HTTP $HTTP_CODE)"
fi

# TSA WITH its certificate. Without the cert, timestamping fails and every addressChange/registration
# management request returns 500. Same transient-400 retry as the CA. Fatal if it never succeeds.
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -ksS -o /tmp/tsa-resp.json -w "%{http_code}" -H "$AUTH" \
        -F "certificate=@tools/tsa.pem" \
        -F "url=http://testca:8899" \
        -X POST "${CS_URL}/api/v1/timestamping-services")
    case "$HTTP_CODE" in 201|409) break;; esac
    sleep 6
done
case "$HTTP_CODE" in 201|409) echo "  TSA configured (HTTP $HTTP_CODE)";; *) echo "  ERROR: TSA add failed (HTTP $HTTP_CODE): $(cat /tmp/tsa-resp.json 2>/dev/null)"; exit 1;; esac

rm -f tools/ca.pem tools/tsa.pem

log "5. Waiting for Global Configuration to generate..."
until docker compose exec -T cs sh -lc 'cat /var/log/xroad/.global_conf_gen_status 2>/dev/null' | grep -q '"success":true'; do
    sleep 5
done
echo "  Global Configuration generation succeeded."

log "6. Downloading Configuration Anchor..."
tools/scripts/generate-anchor.sh

log "7. Preparing Security Servers with xrdsst (anchor, token, TSA, clients, CSRs)..."
log "  waiting for the Security Server admin APIs (emulated boot is slow)..."
for ss in ss-mj ss-moh ss-mtc ss-oss; do
  until docker compose exec -T "$ss" sh -lc 'curl -ksSf -o /dev/null https://localhost:4000/' 2>/dev/null; do sleep 5; done
  echo "  $ss ready"
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
docker compose --profile test run --rm hurl --insecure --test /tools/e2e.hurl

log "✅ Initialization complete! The One-Stop-Shop portal is ready at http://localhost:8000"
