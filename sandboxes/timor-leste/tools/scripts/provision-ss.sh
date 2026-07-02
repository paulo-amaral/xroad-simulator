#!/usr/bin/env bash
# Sign + import each Security Server's authentication and signing certificates with the Test CA,
# then register the auth cert WITH the routable hostname address (which also avoids the 127.0.0.1
# loopback problem — the address is set at registration, not by a separate addressChange).
#
# xrdsst generates the keys and CSRs; this completes the cert dance that xrdsst's static-file
# config cannot do in a clean run (fresh keys never match the pre-signed files). Idempotent: a key
# that already has a certificate is skipped. Requires SS_*_API_KEY in the env. Test/dev only.
set -uo pipefail
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CA_SIGN="${CA_SIGN:-http://localhost:8888/testca/sign}"
log(){ printf '\033[1;34m[ss-certs]\033[0m %s\n' "$*"; }

# Print "<key_id> <csr_id>" for the first key of a usage that has a CSR and no certificate yet.
pending(){ python3 -c "
import sys,json
raw=sys.stdin.read()
d=json.loads(raw) if raw.strip() else {}
for k in d.get('keys',[]):
    if k.get('usage')=='$1' and not k.get('certificates') and k.get('certificate_signing_requests'):
        print(k['id'], k['certificate_signing_requests'][0]['id']); break"; }
# Print the hash of an AUTHENTICATION cert that is not yet REGISTERED.
auth_hash(){ python3 -c "
import sys,json
raw=sys.stdin.read()
d=json.loads(raw) if raw.strip() else {}
print(next((c['certificate_details']['hash'] for k in d.get('keys',[]) if k.get('usage')=='AUTHENTICATION'
            for c in k.get('certificates',[]) if c.get('status')!='REGISTERED'), ''))"; }

# port : api-key-var : hostname
for entry in "1000:SS_MJ_API_KEY:ss-mj" "2000:SS_SERVE_API_KEY:ss-serve" "3000:SS_MTC_API_KEY:ss-mtc" "5000:SS_OSS_API_KEY:ss-oss"; do
  p="${entry%%:*}"; rest="${entry#*:}"; kn="${rest%%:*}"; host="${rest#*:}"; key="$(eval echo \$$kn)"
  H="Authorization: X-Road-ApiKey token=$key"; B="https://127.0.0.1:$p/api/v1"
  log "$host: signing auth + sign certificates"
  for usage in AUTHENTICATION SIGNING; do
    [ "$usage" = AUTHENTICATION ] && t=auth || t=sign
    set -- $(curl -sk -m10 -H "$H" "$B/tokens/0" | pending "$usage")
    kid="${1:-}"; cid="${2:-}"
    [ -z "$kid" ] && { echo "  $usage: certificate present, skip"; continue; }
    curl -sk -m10 -H "$H" "$B/keys/$kid/csrs/$cid?csr_format=DER" -o "$TMP/$host-$t.csr"
    curl -fsS -F "certreq=@$TMP/$host-$t.csr" -F "type=$t" "$CA_SIGN" -o "$TMP/$host-$t.crt"
    echo "  $usage import -> $(curl -sk -m12 -o /dev/null -w '%{http_code}' -H "$H" -H 'Content-Type: application/octet-stream' --data-binary @"$TMP/$host-$t.crt" -X POST "$B/token-certificates")"
  done
  # Activate the signing cert before registering the auth cert: the registration request is signed
  # by the member's signing key, and the Central Server rejects it until that cert is active. Needs a
  # good OCSP response, so retry while the Test CA + responder propagate into this server's global conf.
  shash="$(curl -sk -m10 -H "$H" "$B/tokens/0" | python3 -c '
import sys,json
raw=sys.stdin.read()
d=json.loads(raw) if raw.strip() else {}
print(next((c["certificate_details"]["hash"] for k in d.get("keys",[]) if k.get("usage")=="SIGNING"
            for c in k.get("certificates",[]) if not c.get("active")), ""))')"
  if [ -n "$shash" ]; then
    for _ in $(seq 1 18); do
      sc=$(curl -sk -m12 -o /dev/null -w '%{http_code}' -H "$H" -X PUT "$B/token-certificates/$shash/activate")
      case "$sc" in 204|409) break;; esac
      sleep 5
    done
    echo "  sign cert activate -> $sc"
  fi
  hash="$(curl -sk -m10 -H "$H" "$B/tokens/0" | auth_hash)"
  if [ -n "$hash" ]; then
    echo "  register auth cert (address=$host) -> $(curl -sk -m12 -o /dev/null -w '%{http_code}' -H "$H" -H 'Content-Type: application/json' -X PUT "$B/token-certificates/$hash/register" -d "{\"address\":\"$host\"}")"
  else
    echo "  auth cert already registered"
  fi
done
log "done. Approve the auth-cert requests at the Central Server, then register the subsystems."
