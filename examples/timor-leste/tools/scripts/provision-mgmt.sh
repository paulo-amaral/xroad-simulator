#!/usr/bin/env bash
# Complete the X-Road bootstrap that neither provision-cs.sh nor xrdsst covers: the management
# services Security Server, the routable addresses, the subsystem registrations + approvals, and
# the service ACLs. Idempotent — safe to re-run. Requires CS_API_KEY and SS_*_API_KEY in the env,
# the anchor downloaded, and xrdsst to have initialised the Security Servers (keys + auth certs).
# Full rationale: docs/PROVISIONING-RUNBOOK.md. Test/dev only.
set -uo pipefail

CS=https://localhost:4000
MGMT_SS=ss-mtc            # operator (MTC / TIC Timor) hosts GOV/01/MANAGEMENT
MGMT_PORT=3000
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
log(){ printf '\033[1;34m[mgmt]\033[0m %s\n' "$*"; }

cs(){  curl -sk -m 20 -H "Authorization: X-Road-ApiKey token=${CS_API_KEY}" "$@"; }
ss(){ local p=$1; shift; curl -sk -m 30 -H "Authorization: X-Road-ApiKey token=$1" "https://127.0.0.1:${p}/api/v1$2" "${@:3}"; }
code(){ curl -sk -m 30 -o /dev/null -w '%{http_code}' "$@"; }

approve_waiting(){
  for id in $(cs "${CS}/api/v1/management-requests?status=WAITING" | python3 -c "import sys,json;[print(r['id']) for r in json.load(sys.stdin).get('items',[])]" 2>/dev/null); do
    cs -o /dev/null -w "  approve #$id -> %{http_code}\n" -X POST "${CS}/api/v1/management-requests/${id}/approval"
  done
}

# ── 1. approve the auth-cert registration requests xrdsst submitted ───────────
log "approving pending auth-cert / client registration requests"
approve_waiting

# ── 2. management services Security Server on ss-mtc ──────────────────────────
log "pre-registering the management provider on ${MGMT_SS}"
cs -o /dev/null -w "  service_provider -> %{http_code}\n" -H "Content-Type: application/json" -X PATCH \
  "${CS}/api/v1/management-services-configuration" -d '{"service_provider_id":"SUBSYSTEM:TL-TEST:GOV:01:MANAGEMENT"}'
cs -o /dev/null -w "  register-provider -> %{http_code}\n" -H "Content-Type: application/json" -X POST \
  "${CS}/api/v1/management-services-configuration/register-provider" -d "{\"security_server_id\":\"TL-TEST:GOV:MTC:${MGMT_SS}\"}"

# add the GOV/01/MANAGEMENT client on ss-mtc (idempotent)
ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/clients" -o /dev/null -w "  add mgmt client -> %{http_code}\n" -H "Content-Type: application/json" -X POST \
  -d '{"client":{"member_class":"GOV","member_code":"01","subsystem_code":"MANAGEMENT","connection_type":"HTTPS_NO_AUTH"},"ignore_warnings":true}'

# GOV/01 signing certificate on ss-mtc (cross-member hosting needs it)
if ! ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/tokens/0" | grep -q 'TL-TEST:GOV:01'; then
  log "issuing a GOV/01 signing certificate on ${MGMT_SS}"
  RESP=$(ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/tokens/0/keys-with-csrs" -H "Content-Type: application/json" -X POST -d '{
    "key_label":"ss-mtc-mgmt01-sign",
    "csr_generate_request":{"key_usage_type":"SIGNING","ca_name":"Test CA","csr_format":"DER","member_id":"TL-TEST:GOV:01",
      "subject_field_values":{"serialNumber":"TL-TEST/ss-mtc/GOV","CN":"01","C":"FI","O":"Government of Timor-Leste","subjectAltName":"ss-mtc"}}}')
  KID=$(echo "$RESP" | python3 -c "import sys,json;d=json.load(sys.stdin);k=d.get('key',d);print(k.get('id',''))")
  CID=$(echo "$RESP" | python3 -c "import sys,json;d=json.load(sys.stdin);k=d.get('key',d);print((k.get('certificate_signing_requests') or [{}])[0].get('id',''))")
  ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/keys/${KID}/csrs/${CID}?csr_format=DER" -o "$TMP/mgmt01.csr"
  curl -fsS -F "certreq=@$TMP/mgmt01.csr" -F "type=sign" "http://localhost:8888/testca/sign" -o "$TMP/mgmt01.crt"   # type=sign, not auto
  ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/token-certificates" -o /dev/null -w "  import sign cert -> %{http_code}\n" \
    -H "Content-Type: application/octet-stream" --data-binary @"$TMP/mgmt01.crt" -X POST
fi

# publish the management WSDL + point the services at the CS + enable + grant access
if ! ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/clients/TL-TEST:GOV:01:MANAGEMENT/service-descriptions" | grep -q managementservices.wsdl; then
  log "publishing the management services (WSDL) on ${MGMT_SS}"
  SD=$(ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/clients/TL-TEST:GOV:01:MANAGEMENT/service-descriptions" -H "Content-Type: application/json" -X POST \
        -d '{"url":"http://cs/managementservices.wsdl","type":"WSDL","ignore_warnings":true}' | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/services/TL-TEST:GOV:01:MANAGEMENT:clientReg" -o /dev/null -w "  set service url -> %{http_code}\n" -H "Content-Type: application/json" -X PATCH \
    -d '{"url":"https://cs:4002/managementservice/manage/","url_all":true,"timeout":60,"timeout_all":true,"ssl_auth":false,"ssl_auth_all":true}'
  [ -n "$SD" ] && ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/service-descriptions/${SD}/enable" -o /dev/null -w "  enable WSDL -> %{http_code}\n" -X PUT
  ss "$MGMT_PORT" "$SS_MTC_API_KEY" "/clients/TL-TEST:GOV:01:MANAGEMENT/service-clients/TL-TEST:security-server-owners/access-rights" -o /dev/null -w "  grant mgmt ACL -> %{http_code}\n" \
    -H "Content-Type: application/json" -X POST -d '{"items":[{"service_code":"clientReg"},{"service_code":"clientDeletion"},{"service_code":"authCertDeletion"},{"service_code":"ownerChange"},{"service_code":"clientRename"},{"service_code":"addressChange"},{"service_code":"clientEnable"},{"service_code":"clientDisable"},{"service_code":"maintenanceModeEnable"},{"service_code":"maintenanceModeDisable"}]}'
fi
approve_waiting
log "waiting for the management provider to reach the global configuration (~60s)"; sleep 60

# ── 3. routable addresses (127.0.0.1 loops back to itself in containers) ───────
log "setting each Security Server's address to its hostname"
for pair in "3000:SS_MTC_API_KEY:ss-mtc" "1000:SS_MJ_API_KEY:ss-mj" "2000:SS_MOH_API_KEY:ss-moh" "5000:SS_OSS_API_KEY:ss-oss"; do
  p=${pair%%:*}; rest=${pair#*:}; kn=${rest%%:*}; addr=${rest#*:}; key=$(eval echo \$$kn)
  ss "$p" "$key" "/system/server-address" -o /dev/null -w "  ${addr} -> %{http_code}\n" -H "Content-Type: application/json" -X PUT -d "{\"address\":\"${addr}\"}"
done
log "waiting for the new addresses to propagate (~60s)"; sleep 60

# ── 4. register the provider/consumer subsystems + approve ────────────────────
log "registering subsystems (retry until the global conf carries the management provider)"
for pair in "3000:SS_MTC_API_KEY:TL-TEST:GOV:MTC:DNTT" "1000:SS_MJ_API_KEY:TL-TEST:GOV:MJ:JUSTICE" "5000:SS_OSS_API_KEY:TL-TEST:GOV:OSS:PORTAL"; do
  p=${pair%%:*}; rest=${pair#*:}; kn=${rest%%:*}; cid=${rest#*:}; key=$(eval echo \$$kn)
  for i in $(seq 1 8); do
    c=$(code -H "Authorization: X-Road-ApiKey token=${key}" -X PUT "https://127.0.0.1:${p}/api/v1/clients/${cid}/register")
    [ "$c" = "204" ] && { echo "  ${cid} -> registered"; break; } || { echo "  ${cid} -> ${c} (retry $i)"; sleep 20; }
  done
done
approve_waiting
log "waiting for the registrations to propagate (~60s)"; sleep 60

# ── 5. service access rights for the One-Stop-Shop consumer ───────────────────
log "granting OSS/PORTAL access to the published services"
ss 1000 "$SS_MJ_API_KEY"  "/clients/TL-TEST:GOV:MJ:JUSTICE/service-clients/TL-TEST:GOV:OSS:PORTAL/access-rights" -o /dev/null -w "  birth-certificate -> %{http_code}\n" \
  -H "Content-Type: application/json" -X POST -d '{"items":[{"service_code":"birth-certificate"}]}'
ss 3000 "$SS_MTC_API_KEY" "/clients/TL-TEST:GOV:MTC:DNTT/service-clients/TL-TEST:GOV:OSS:PORTAL/access-rights" -o /dev/null -w "  driver-license -> %{http_code}\n" \
  -H "Content-Type: application/json" -X POST -d '{"items":[{"service_code":"driver-license"}]}'

log "done. Verify with: python3 tools/showcase.py"
