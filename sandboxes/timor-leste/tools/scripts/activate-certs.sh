#!/usr/bin/env bash
# Activate every REGISTERED-but-inactive certificate on all Security Servers. X-Road imports
# certificates inactive; they must be active for traffic. Activation needs a good OCSP response (so
# the Test CA + OCSP responder must already be in the global configuration) and, for authentication
# certificates, that the Central Server has approved the registration so the cert reaches REGISTERED.
# Idempotent and bounded: an already-active cert is skipped; the loop gives up after a timeout.
# Requires SS_*_API_KEY in the environment. Test/dev only.
set -uo pipefail
log(){ printf '\033[1;34m[ss-activate]\033[0m %s\n' "$*"; }

# port : api-key env var
ENTRIES="1000:SS_MJ_API_KEY 2000:SS_SERVE_API_KEY 3000:SS_MTC_API_KEY 5000:SS_OSS_API_KEY"
deadline=$(( $(date +%s) + 600 ))   # up to 10 min for OCSP fetch + auth-cert REGISTERED propagation

while :; do
  pending=0
  for e in $ENTRIES; do
    p="${e%%:*}"; kn="${e#*:}"; key="$(eval echo \$$kn)"
    H="Authorization: X-Road-ApiKey token=$key"; B="https://127.0.0.1:$p/api/v1"
    state="$(curl -sk -m10 -H "$H" "$B/tokens/0" 2>/dev/null)" || { pending=1; continue; }
    while read -r st act hash; do
      [ "$act" = "True" ] && continue
      pending=1
      [ "$st" = "REGISTERED" ] && curl -sk -m12 -o /dev/null -H "$H" -X PUT "$B/token-certificates/$hash/activate"
    done <<EOF
$(printf '%s' "$state" | python3 -c '
import sys,json
raw=sys.stdin.read()
d=json.loads(raw) if raw.strip() else {}
for k in d.get("keys",[]):
    for c in k.get("certificates",[]):
        print(c.get("status"), c.get("active"), c["certificate_details"]["hash"])')
EOF
  done
  [ "$pending" = "0" ] && { log "all certificates active"; break; }
  [ "$(date +%s)" -ge "$deadline" ] && { log "WARNING: some certificates still inactive after timeout"; break; }
  sleep 10
done
