#!/usr/bin/env bash
# Bring up the Timor-Leste X-Road sandbox (Central Server, Test CA, three ministry
# Security Servers, mock provider). Test/dev only. Idempotent: safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"   # tools/scripts -> example root
COMPOSE_FILE="${SANDBOX_DIR}/docker-compose.yml"

CS_URL="https://localhost:4000"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600}"   # seconds to wait for the Central Server UI

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[install] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || fail "missing dependency: $1"; }

log "Checking prerequisites"
require docker
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 not available (need 'docker compose')"
docker info >/dev/null 2>&1 || fail "Docker daemon is not running"
require python3
python3 -c "import venv" >/dev/null 2>&1 || fail "python3-venv module is not installed"

log "Setting up Python virtual environment and installing xrdsst"
if [ ! -d "${SANDBOX_DIR}/.venv" ]; then
  python3 -m venv "${SANDBOX_DIR}/.venv"
fi
_PIP="${SANDBOX_DIR}/.venv/bin/pip"
"$_PIP" install --upgrade pip

# Pre-install build-time deps needed by xrdsst's setup.py and its sub-dependencies.
"$_PIP" install cement setuptools requests

# Install xrdsst itself without dependency resolution.
# xrdsst 4.0.0 pins jq~=1.1.1 which fails to compile on Python 3.12+
# (uses longintrepr.h, removed in CPython 3.12). We bypass the broken pin
# and supply a compatible jq manually below.
"$_PIP" install --no-build-isolation --no-deps \
  --extra-index-url https://artifactory.niis.org/artifactory/xroad-extensions-release-pypi/ \
  xrdsst --trusted-host artifactory.niis.org

# Install xrdsst runtime dependencies, replacing jq~=1.1.1 with jq>=1.7.0
# (the first version that supports Python 3.12+).
# cement==3.0.4 (pinned by xrdsst) also uses the removed 'imp' module on Python 3.12+;
# we keep cement 3.0.14 (installed above) which has a compatible API and no imp usage.
"$_PIP" install --no-build-isolation \
  pyyaml "networkx~=2.5" "tabulate~=0.8.7" \
  "confuse~=1.3.0" "certifi>=14.05.14" "six>=1.10" \
  "python-dateutil~=2.8.1" \
  "gitpython~=3.1.11" "docker~=4.1.0" "yq~=2.11.1" \
  "jq>=1.7.0"

_SITE_PACKAGES="$("${SANDBOX_DIR}/.venv/bin/python" -c 'import site; print(site.getsitepackages()[0])')"
mkdir -p "${_SITE_PACKAGES}/config"
ln -sf "${SANDBOX_DIR}/xroad/config/xrdsst-config.yaml" "${_SITE_PACKAGES}/config/xrdsst.yml"
"${SANDBOX_DIR}/.venv/bin/python" - <<'PY'
from pathlib import Path
import site

profile = Path(site.getsitepackages()[0]) / "xrdsst/core/profile/fi_auth_certificate_profile.py"
text = profile.read_text()
old = '"CN": profile_data.security_server_dns\n'
new = '"CN": profile_data.security_server_dns,\n            "subjectAltName": profile_data.security_server_dns\n'
if old in text and "subjectAltName" not in text:
    profile.write_text(text.replace(old, new))

profile = Path(site.getsitepackages()[0]) / "xrdsst/core/profile/fi_sign_certificate_profile.py"
text = profile.read_text()
old = '"CN": profile_data.member_code\n'
new = '"CN": profile_data.member_code,\n            "subjectAltName": profile_data.security_server_dns\n'
if old in text and "subjectAltName" not in text:
    profile.write_text(text.replace(old, new))
PY

log "Pulling images (test/dev only)"
docker compose -f "${COMPOSE_FILE}" pull

# Start the Central Server and Test CA first; give them time to stabilise before
# launching the memory-hungry Security Servers. All 5 Java services competing for
# ~8 GiB on Docker Desktop triggers the OOM killer and keeps the CS in a crash loop.
log "Starting Central Server and Test CA"
docker compose -f "${COMPOSE_FILE}" up -d cs testca

log "Waiting for the Central Server UI (${CS_URL}, up to ${WAIT_TIMEOUT}s)"
deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
until curl -ksSf -o /dev/null "${CS_URL}" 2>/dev/null; do
  [ "$(date +%s)" -lt "${deadline}" ] || fail "Central Server did not become ready in ${WAIT_TIMEOUT}s. Check: docker compose -f ${COMPOSE_FILE} logs cs"
  sleep 5
done

log "Central Server is ready — starting Security Servers and remaining services"
docker compose -f "${COMPOSE_FILE}" up -d

log "Ecosystem is up:"
docker compose -f "${COMPOSE_FILE}" ps

# Best-effort: fetch the global-configuration anchor if the Central Server is already
# initialized and a CS_API_KEY is provided. Otherwise this prints how to obtain it.
log "Attempting to generate the configuration anchor"
"${SCRIPT_DIR}/generate-anchor.sh" || true

cat <<EOF

Access (login xrd / secret):
  Central Server   ${CS_URL}
  ss-mj  (Justica) https://localhost:1000
  ss-moh (Saude)   https://localhost:2000
  ss-mtc (DNTT)    https://localhost:3000
  ss-oss (OSS)     https://localhost:5000
  Test CA          http://localhost:8888/testca/
  eID (OIDC mock)  http://localhost:9080/default/.well-known/openid-configuration
  e-KYC mock       http://localhost:9081/verify
  One-Stop-Shop    http://localhost:8000     <- citizen portal

Next: follow Step 2 onward in the example README, then provision from the example root:
  cd ${SANDBOX_DIR}
  source .venv/bin/activate
  tools/scripts/generate-ss-api-keys.sh
  set -a; source .env; set +a
  xrdsst -c xroad/config/xrdsst-config.yaml apply

Tear down with: ${SCRIPT_DIR}/down.sh
EOF
