#!/usr/bin/env bash
# One-Command Setup for Timor-Leste X-Road Sandbox
# This script initializes the entire ecosystem: starts containers, provisions the
# Central Server, sets up Trust Services (CA/TSA), downloads the anchor,
# configures the Security Servers, and runs the E2E declarative tests (Hurl).

set -euo pipefail

log() { printf '\n\033[1;32m[setup]\033[0m %s\n' "$*"; }

log "1. Checking prerequisites and starting Docker ecosystem..."
tools/scripts/install.sh

log "2. Creating API Key for Central Server provisioning..."
CS_URL="https://localhost:4000"
CS_API_KEY=$(curl -ksS -u "xrd:secret" -H "Content-Type: application/json" \
    -X POST "${CS_URL}/api/v1/api-keys" \
    -d '["XROAD_SYSTEM_ADMINISTRATOR","XROAD_SECURITY_OFFICER","XROAD_REGISTRATION_OFFICER","XROAD_MANAGEMENT_SERVICE"]' | \
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("key", ""))')
export CS_API_KEY

log "3. Provisioning Central Server (Instance, Tokens, Members)..."
tools/scripts/provision-cs.sh

log "4. Provisioning Trust Services (Test CA & TSA)..."
AUTH="Authorization: X-Road-ApiKey token=$CS_API_KEY"
docker compose exec -T testca cat /home/ca/CA/certs/ca.cert.pem > tools/ca.cert.pem
docker compose exec -T testca cat /home/ca/CA/certs/tsa.cert.pem > tools/tsa.cert.pem

# Idempotently add CA (ignore 409 Conflict if already exists)
HTTP_CODE=$(curl -ksS -o /dev/null -w "%{http_code}" -H "$AUTH" \
    -F "certificate=@tools/ca.cert.pem" \
    -F "certificate_profile_info=ee.ria.xroad.common.certificateprofile.impl.EjbcaCertificateProfileInfo" \
    -X POST "${CS_URL}/api/v1/certificate-authorities")
if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
    echo "  Test CA configured (HTTP $HTTP_CODE)"
else
    echo "  Warning: Test CA configuration returned HTTP $HTTP_CODE"
fi

# We need the CA ID to add the OCSP responder. Let's find it.
CA_ID=$(curl -ksS -H "$AUTH" "${CS_URL}/api/v1/certificate-authorities" | python3 -c 'import json,sys; res=json.load(sys.stdin); print(res[0]["id"] if res else "")')
if [ -n "$CA_ID" ]; then
    HTTP_CODE=$(curl -ksS -o /dev/null -w "%{http_code}" -H "$AUTH" -H "Content-Type: application/json" \
        -d '{"url":"http://testca:8888"}' \
        -X POST "${CS_URL}/api/v1/certificate-authorities/${CA_ID}/ocsp-responders")
    echo "  OCSP Responder configured (HTTP $HTTP_CODE)"
fi

HTTP_CODE=$(curl -ksS -o /dev/null -w "%{http_code}" -H "$AUTH" \
    -F "certificate=@tools/tsa.cert.pem" \
    -F "url=http://testca:8899" \
    -X POST "${CS_URL}/api/v1/timestamping-services")
if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "409" ]; then
    echo "  TSA configured (HTTP $HTTP_CODE)"
else
    echo "  Warning: TSA configuration returned HTTP $HTTP_CODE"
fi

rm -f tools/ca.cert.pem tools/tsa.cert.pem

log "5. Waiting for Global Configuration to generate..."
until docker compose exec -T cs sh -lc 'cat /var/log/xroad/.global_conf_gen_status 2>/dev/null' | grep -q '"success":true'; do
    sleep 5
done
echo "  Global Configuration generation succeeded."

log "6. Downloading Configuration Anchor..."
tools/scripts/generate-anchor.sh

log "7. Provisioning Security Servers via xrdsst (Declarative Configuration)..."
if [ ! -f .env ]; then
  cp ../../.env.example .env
fi
source .venv/bin/activate
tools/scripts/generate-ss-api-keys.sh
set -a; source .env; set +a
xrdsst -c xroad/config/xrdsst-config.yaml apply

log "8. Running Declarative E2E Tests via Hurl..."
docker compose --profile test run --rm hurl --insecure --test /tools/e2e.hurl

log "✅ Initialization complete! The One-Stop-Shop portal is ready at http://localhost:8000"
