#!/usr/bin/env bash
# Sign an X-Road CSR with the sandbox Test CA (replaces a real CA in test/dev only).
# Usage: ./sign-csr.sh <csr-file> <output-cert-file> [auth|sign|auto]
# The Test CA exposes the sign endpoint on port 8888 (mapped to localhost by docker-compose).
set -euo pipefail

CSR="${1:?usage: sign-csr.sh <csr-file> <output-cert-file> [auth|sign|auto]}"
OUT="${2:?usage: sign-csr.sh <csr-file> <output-cert-file> [auth|sign|auto]}"
TYPE="${3:-auto}"
CA_URL="${CA_URL:-http://localhost:8888/testca/sign}"

case "${TYPE}" in
  auth|sign|auto) ;;
  *) echo "type must be auth, sign, or auto" >&2; exit 2 ;;
esac

# The Test CA signs both authentication and signing CSRs from this endpoint.
curl -fsS -F "certreq=@${CSR}" -F "type=${TYPE}" "${CA_URL}" -o "${OUT}"
echo "Signed certificate written to ${OUT}"
