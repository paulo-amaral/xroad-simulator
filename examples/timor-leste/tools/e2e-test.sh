#!/usr/bin/env bash
# Real end-to-end X-Road test for officials: a citizen request issued by the
# One-Stop-Shop consumer (TL-TEST/GOV/OSS/PORTAL) is routed through its Security
# Server (ss-oss) to the provider ministries and validated by X-Road.
#
# PASS only when the call actually traversed X-Road: HTTP 200 AND an
# X-Road-Request-Id response header (set by the Security Server, never by the
# mock provider directly). Test/dev sandbox only.
set -uo pipefail

CLIENT="TL-TEST/GOV/OSS/PORTAL"
BASE="https://localhost:5443/r1"   # ss-oss information-system access point (https)
PASS=0; FAIL=0

check() {
  local name="$1" path="$2"
  local hdr body code rid
  hdr="$(mktemp)"; body="$(mktemp)"
  code="$(curl -sk -m 12 -D "$hdr" -o "$body" -w '%{http_code}' \
          -H "X-Road-Client: ${CLIENT}" "${BASE}/${path}")"
  rid="$(grep -i '^x-road-request-id:' "$hdr" | tr -d '\r' | awk '{print $2}')"
  if [ "$code" = "200" ] && [ -n "$rid" ]; then
    printf '  \033[1;32mPASS\033[0m %-18s HTTP 200  X-Road-Request-Id=%s\n' "$name" "$rid"
    PASS=$((PASS+1))
  else
    printf '  \033[1;31mFAIL\033[0m %-18s HTTP %s  request-id=%s\n' "$name" "$code" "${rid:-none}"
    sed 's/^/        /' "$body" | head -3
    FAIL=$((FAIL+1))
  fi
  rm -f "$hdr" "$body"
}

echo "Real X-Road end-to-end test (consumer ${CLIENT} via ss-oss):"
check "driver-license"    "TL-TEST/GOV/MTC/DNTT/driver-license/v1/licenses/TL-12345"
check "birth-certificate" "TL-TEST/GOV/MJ/JUSTICE/birth-certificate/v1/certificates/TL-67890"
echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL PASS (${PASS}/2) - the X-Road path is live."
else
  echo "${FAIL} FAILED - provisioning not complete (consumer/services not registered)."
  exit 1
fi
