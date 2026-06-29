#!/usr/bin/env bash
# Generate an SBOM (CycloneDX) and run a CVE scan locally, mirroring the CI gate.
# Requires syft and grype (https://github.com/anchore). Fails on High/Critical findings.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"   # repo root
OUT="${SBOM_OUT:-${ROOT}/sbom.cyclonedx.json}"

command -v syft  >/dev/null || { echo "syft not installed: https://github.com/anchore/syft"; exit 1; }
command -v grype >/dev/null || { echo "grype not installed: https://github.com/anchore/grype"; exit 1; }

echo "[sbom] generating CycloneDX SBOM for ${ROOT}"
syft "dir:${ROOT}" -o cyclonedx-json="${OUT}"
echo "[sbom] SBOM written to ${OUT}"

echo "[sbom] CVE scan (fail on High/Critical)"
grype "sbom:${OUT}" --fail-on high
echo "[sbom] no High/Critical vulnerabilities"
