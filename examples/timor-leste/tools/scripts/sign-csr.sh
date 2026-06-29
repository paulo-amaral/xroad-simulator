#!/usr/bin/env bash
# Sign an X-Road CSR with the sandbox Test CA (replaces a real CA in test/dev only).
# Usage: ./sign-csr.sh <csr-file> <output-cert-file>
# The Test CA exposes the sign endpoint on port 8888 (mapped to localhost by docker-compose).
set -euo pipefail

CSR="${1:?usage: sign-csr.sh <csr-file> <output-cert-file>}"
OUT="${2:?usage: sign-csr.sh <csr-file> <output-cert-file>}"
CA_URL="${CA_URL:-http://localhost:8888/testca/sign}"

# The Test CA signs both authentication and signing CSRs from this endpoint.
curl -fsS -F "certreq=@${CSR}" "${CA_URL}" -o "${OUT}"
echo "Signed certificate written to ${OUT}"
