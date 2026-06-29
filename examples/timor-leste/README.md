# Timor-Leste X-Road Sandbox

This sandbox simulates ministries joined to a single X-Road instance, exchanging data via APIs under a single PKI trust fabric. The **One-Stop-Shop portal** serves as the citizen entry point (e-KYC / eID).

| Ministry / portal | Member | Subsystem | Role |
|---|---|---|---|
| Ministry of Justice | `TL-TEST/GOV/MJ` | `JUSTICE` | provider of `birth-certificate`, consumer |
| Ministry of Health | `TL-TEST/GOV/MOH` | `HEALTH` | consumer |
| Transportes e Comunicacoes (DNTT) | `TL-TEST/GOV/MTC` | `DNTT` | provider of `driver-license` |
| One-Stop-Shop (one-stop-shop) | `TL-TEST/GOV/OSS` | `PORTAL` | consumer on behalf of citizens |

> **Test/dev only.** Every image, credential, PIN, and the Test CA here is for the sandbox and must never be used in production or against real citizen data.

---

## Journey 1: For Administrators (Network Operators)

Administrators (e.g., TIC Timor) are responsible for bringing up the infrastructure, configuring the Central Server, and setting up the Security Servers for the agencies.

### Automated One-Command Setup

The entire ecosystem (starting containers, configuring the Central Server, adding Trust Services, downloading anchors, and provisioning Security Servers) is fully automated. You only need one command to initialize everything:

```bash
cd examples/timor-leste
sh init.sh
```

*This orchestrates everything natively and securely via APIs. It uses the `xrdsst` toolkit for the Security Servers and declarative Hurl tests to verify that E2E traffic flows successfully through X-Road at the end.*

UIs Available:
- **Central Server:** `https://localhost:4000` (login `xrd` / `secret`)
- **Test CA:** `http://localhost:8888/testca/`
- **One-Stop-Shop portal:** `http://localhost:8000` · **eID:** `:9080` · **e-KYC:** `:9081`
- Security Servers admin panels (login `xrd` / `secret`):
  - ss-mj (Justice): `https://localhost:1000`
  - ss-moh (Health): `https://localhost:2000`
  - ss-mtc (DNTT): `https://localhost:3000`
  - ss-oss (Portal): `https://localhost:5000`

---

## Journey 2: For Implementers (Developers & Agencies)

Implementers are the developers building APIs (e.g., Ministry of Justice) or consuming APIs (e.g., One-Stop-Shop). They work with the X-Road ecosystem once it has been provisioned by the Administrator.

### 1. Publishing Services & Zero-Trust (ACLs)
X-Road authenticates **systems**, not end users. A ministry is onboarded once and then reaches any service it is granted.

`xroad/config/xrdsst-config.yaml` shows how DNTT publishes `driver-license` and the Ministry of Justice publishes
`birth-certificate`, each granted to the One-Stop-Shop portal (and selected ministries). OpenAPI 3.1 contracts
for both services are in `xroad/api/`. If you change who can access what, re-run:
```bash
xrdsst -c xroad/config/xrdsst-config.yaml service apply
```

### 2. Consuming Services (Inter-Ministry and via the portal)
You route the request through **your own** Security Server. Both `birth-certificate` and `driver-license` are
consumed by the One-Stop-Shop (subsystem `OSS/PORTAL`, through `ss-oss` on port 5443):

```bash
# Driver license via One-Stop-Shop
curl -k -H "X-Road-Client: TL-TEST/GOV/OSS/PORTAL" \
  "https://localhost:5443/r1/TL-TEST/GOV/MTC/DNTT/driver-license/v1/licenses/TL-12345"

# Birth certificate via One-Stop-Shop
curl -k -H "X-Road-Client: TL-TEST/GOV/OSS/PORTAL" \
  "https://localhost:5443/r1/TL-TEST/GOV/MJ/JUSTICE/birth-certificate/v1/certificates/TL-67890"
```
System-to-system also works, e.g. Justice querying DNTT through its own Security Server (port 1443).
URL format: `<your_security_server>/r1/<provider_subsystem>/<service_code>`.

### 3. Citizen Entry Point (One-Stop-Shop Portal)
The One-Stop-Shop is a consumer information system. It authenticates the citizen with the eID via **OpenID
Connect authorization_code + PKCE**, **verifies the ID-token signature against the IdP JWKS** (RFC 8725), runs
**e-KYC identity verification**, then calls services on the citizen's behalf through its own Security Server
(`ss-oss`).

- Open **`http://localhost:8000`** -> **Sign in with eID** -> log in at the eID mock -> back to the portal.
- The portal runs e-KYC (shows the verified assurance level), then lets the citizen **choose a service**
  (birth-certificate or driver-license). The result renders the X-Road request and the
  `X-Road-Request-Id` / `X-Road-Request-Hash` headers.

### 4. Interactive Flow Simulator
Open `citizen/simulator/simulator.html`. It maps the ecosystem with the **One-Stop-Shop/identity** zone visually separated
from the **X-Road** zone. **Click any server node to open its admin UI.** Click a scenario to animate the
message flow and the zero-trust steps (eID login, ACL check, mTLS, OCSP, signing, timestamping). Mermaid
diagrams of the same flows are in `docs/diagram.md`.

---

## Troubleshooting

Read the real reason instead of guessing: `python3 tools/sandboxctl.py logs` (or
`docker compose exec -T cs sh -lc 'cat /var/log/xroad/.global_conf_gen_status'`).

| Symptom | Real cause | Fix |
|---|---|---|
| `Global configuration generation failing` | One of the required CS pieces is missing | Check `.global_conf_gen_status`, then the rows below |
| `Signing of external configuration failed - active key missing` | No **active** signing key on a source | Add key **and Activate** on Internal **and** External (Step 2.3) |
| `element 'managementService' is not complete ... managementRequestServiceProviderId` | Management Service Provider not set | Create `GOV` class → member `GOV/1` → subsystem `MANAGEMENT`, then set it as provider (Step 2.4-2.7) |
| *Add member* dialog shows "No data available" | No member classes exist | Settings → System Settings → Member Classes → Add `GOV` (Step 2.4) |
| Error returns after a restart | Container restart logs the signing token out | Log in to the signing token again (keys stay; no need to recreate) |
| Security Server owner shows **"unknown member"** | The owner member (e.g. `TL-TEST:GOV:MOH`) is not registered in the Central Server, so its name is missing from global conf | CS → Members → **Add member** (class `GOV`, the owner's code); wait ~1 min for global conf to refresh |
| `tools/scripts/generate-anchor.sh` says HTTP 401 / can't create API key | This CS image rejects `xrd:secret` on `/api/v1` | Download the anchor from the UI (Step 2.10) |
| `/etc/xroad/globalconf` is empty | Generation has not succeeded yet | Fix generation first; the management service consumes it afterwards |

## Cleanup
To shut down the sandbox and wipe all data:
```bash
cd examples/timor-leste
docker compose down -v
```

## Layout

```text
examples/timor-leste/
├── docker-compose.yml        Ecosystem (CS, Test CA, 4 Security Servers, mocks, eID/e-KYC, portal)
├── xroad/                    ── X-ROAD ──
│   ├── config/               topology.yml · xrdsst-config.yaml
│   ├── api/                  OpenAPI 3.1 contracts (birth-certificate, driver-license)
│   └── anchors/              Global config anchor (gitignored)
├── citizen/                  ── CITIZEN / SIMULATED (kept out of X-Road folders) ──
│   ├── identity/             eID (OIDC) + e-KYC: eid-config.json · ekyc.conf
│   ├── portal/               One-Stop-Shop app (OIDC PKCE + JWKS) + Dockerfile
│   └── simulator/            simulator.html (interactive flow)
├── observability/            Grafana + Prometheus + Loki overlay
├── tools/                    sandboxctl.py + scripts/ (install, init-cs, anchor, sign, sbom)
└── docs/                     diagram.md (Mermaid)
```

## Advanced Topics & Sources
- **Orchestrator:** `python3 tools/sandboxctl.py up|status|identity|anchor|test|down`.
- **Observability:** `docker compose -f docker-compose.yml -f observability/docker-compose.observability.yml up -d` (Grafana `:3001`).
- **Compliance (GovTL):** standards & gap matrix in [govtl-compliance.md](../../docs/govtl-compliance.md).
- **SBOM / CVE:** `tools/scripts/sbom.sh` (syft + grype); CI runs the same gate plus secret scanning (`.github/workflows/ci.yml`).
- **Official guide alignment:** built on the NIIS [Local Test Environment with Docker Compose](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/281739671/) guide — same images, credentials (`xrd`/`secret`), PIN (`123456xrd!`) and port scheme. That guide uses **3** Security Servers (`ss1`=management, `ss2`=consumer, `ss3`=provider); we use **4 per ministry** (`ss-mj`=provider+consumer, `ss-moh`=consumer, `ss-mtc`=provider, `ss-oss`=consumer/portal).
- **Kubernetes:** Deploy the Security Server Sidecar per ministry. See the [Sidecar user guide](https://docs.x-road.global/Sidecar/security_server_sidecar_user_guide.html).
- **Test CA:** `testca` (CA + OCSP + TSA in one container); replace with a real approved CA in production.
- **Security Server Toolkit:** [xrdsst on GitHub](https://github.com/nordic-institute/X-Road-Security-Server-toolkit)
