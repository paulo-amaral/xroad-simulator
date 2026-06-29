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

### Step 1: Start the Ecosystem
First, ensure you have **Docker Engine**, **Docker Compose**, and **Python 3.13+** installed. Then, run the automated installation script:

```bash
cd examples/timor-leste/tools/scripts
sh install.sh
```
*This starts the Central Server, the Test CA, all 4 Security Servers, the mock providers, the eID/e-KYC mocks and the portal. It also creates a Python virtual environment (`.venv`) with the `xrdsst` automation toolkit.*

UIs Available:
- **Central Server:** `https://localhost:4000` (login `xrd` / `secret`)
- **Test CA:** `http://localhost:8888/testca/`
- **One-Stop-Shop portal:** `http://localhost:8000` · **eID:** `:9080` · **e-KYC:** `:9081`

### Step 2: Initialize the Central Server (complete order)

> **TL;DR (UI clicks):** init instance `TL-TEST` → log in signing token → **Add key + Activate on Internal AND
> External** → Member Class `GOV` → Member `GOV / 01` → Subsystem `MANAGEMENT` → System Settings: Management
> Service Provider = `GOV:01:MANAGEMENT` → add Test CA/OCSP/TSA → download anchor. That full list is the part the
> official docs bury; miss any one and global-config generation silently fails.

**Automated (recommended) — no UI clicks:**
```bash
tools/scripts/provision-cs.sh
```
This does the whole of Step 2 (instance init, signing keys for both sources, member class `GOV`, the 5 members,
their subsystems, and the management service provider) through the Central Server REST API. It does not write
directly to the database. If the image rejects REST API key creation with HTTP 401, use the UI or a supported
bootstrap mechanism instead of bypassing authentication. It is idempotent (re-run safe). Afterwards you still add **Test CA + TSA** (Trust Services) and **download the
anchor** (steps 8 and 10 below), then provision the Security Servers with `xrdsst` (Step 3).

**Manual (UI walkthrough):** do these **in order** in the UI (`https://localhost:4000`, login `xrd` / `secret`).
Each step is required for the Central Server to generate and sign the global configuration. Until it does, the
Security Servers cannot be provisioned and `Global configuration generation failing` is shown.

1. **Initialize the instance.** Set **Instance Identifier** `TL-TEST`, **Central Server Address** `cs`, and the
   software token **PIN** `123456xrd!`.
2. **Log in to the configuration signing token** (Global Configuration). The token must stay logged in;
   **a container restart logs it out** and generation fails again until you log in once more.
3. **Generate AND activate signing keys for BOTH sources.** Under **Global Configuration**, in **both** the
   **Internal Configuration** and **External Configuration** sub-tabs: expand the token → **Add key** → **Activate**.
   A missing/inactive **External** key gives *"Signing of external configuration failed - active key missing"*.
   You end with two active keys (one per source — the "maximum of two" the UI mentions).
4. **Create a Member Class.** **Settings → System Settings → Member Classes → Add**: code `GOV`.
   (Without this, the *Add member* dialog shows "No data available".)
5. **Add a Member.** **Members → Add member**: name `Government of Timor-Leste`, class `GOV`, code `01`.
6. **Add a Subsystem** to that member: **Add subsystem** → code `MANAGEMENT`.
7. **Set the Management Service Provider (required).** **Settings → System Settings → Management Service →
   Service Provider Identifier → Edit** → select `GOV:01:MANAGEMENT` → **Save**. Skipping this fails generation
   with *"element 'managementService' is not complete. One of '{managementRequestServiceProviderId}' is expected"*.
8. **Trust Services → add the Test CA** (upload its certificate from `http://localhost:8888/testca/`), set the
   OCSP responder `http://testca:8888` and the TSA `http://testca:8899`.
9. **Verify generation succeeded** (it runs every ~minute):
   ```bash
   docker compose exec -T cs sh -lc 'cat /var/log/xroad/.global_conf_gen_status'   # expect {"success":true}
   ```
10. **Download the anchor**: **Global Configuration → Internal Configuration → Download anchor**, save it as
    `examples/timor-leste/xroad/anchors/TL-TEST-anchor.xml`.

> Note: `tools/scripts/init-cs.sh` and `generate-anchor.sh` try the management REST API, but this Central Server
> image rejects the UI credentials (`xrd:secret`) on `/api/v1` (HTTP 401), so the steps above are done in the UI.
> Steps 4-7 (member class, member, subsystem, management service provider) are UI-only.

### Step 2b: Register the members, then configure each Security Server (UI)

First, in the **Central Server** register one member per ministry (Members → **Add member**, class `GOV`). A
Security Server's **owner member** must already exist in the Central Server. New to the model? Read
[Member vs Subsystem vs Security Server](../../docs/concepts.md) first — Security Servers are **not** subsystems.

| Security Server | Admin UI | Owner Member Class | Owner Member Code | Security Server Code |
|---|---|---|---|---|
| ss-mj (Justice) | `https://localhost:1000` | `GOV` | `MJ` | `ss-mj` |
| ss-moh (Health) | `https://localhost:2000` | `GOV` | `MOH` | `ss-moh` |
| ss-mtc (DNTT) | `https://localhost:3000` | `GOV` | `MTC` | `ss-mtc` |
| ss-oss (One-Stop-Shop) | `https://localhost:5000` | `GOV` | `OSS` | `ss-oss` |

> **Member Code** uniquely identifies the member within its class (in production use the official registry/business ID).
> **Security Server Code** uniquely identifies this server within the same owner. Codes are permanent; see the
> naming guide for the rules (charset `A-Z 0-9 -`, codes are stable, never reused).

On each Security Server's first login, the **Initial configuration** wizard runs:

1. **Configuration Anchor** → **Upload** `xroad/anchors/TL-TEST-anchor.xml` → **Continue**.
2. **Owner Member** → **Member Class** `GOV`, **Member Code** from the table above.
3. **Security Server Code** → from the table above → **Continue**.
4. **Token PIN** → defines the **software-token PIN** (where this server's AUTH keys live). Enter it in both
   **PIN** and **Confirm PIN**, then **Submit**.
   - **Test only:** use the **same PIN on every Security Server** — `123456xrd!`. It must match `XROAD_TOKEN_PIN`
     in `docker-compose.yml` and the `TOKEN_PIN` that `xrdsst` uses to log in to the token. A different PIN per
     server would force you to track one per server and break the shared `xrdsst` config.
   - **Production:** use a distinct, strong PIN per server, stored as a secret (never in the repo).

| Security Server | Software-token PIN (test only) |
|---|---|
| ss-mj · ss-moh · ss-mtc · ss-oss | `123456xrd!` (same for all in the sandbox) |

After the wizard, finish provisioning the server:

5. **Keys & Certificates** → soft token → generate an **authentication key** (creates a CSR) and a **signing key** (CSR).
6. **Sign the CSRs** with the Test CA: `tools/scripts/sign-csr.sh <csr> <out>` (or the CA UI `http://localhost:8888/testca/`), then **import** the signed certificates back into the Security Server.
7. **Register** the authentication certificate. The Central Server operator approves it under **Management Requests** (auth-cert registration + client registration).
8. Add the member's **subsystem** (e.g. `JUSTICE`, `DNTT`, `PORTAL`) and **register** it; the Central Server approves.

The automated alternative to steps 1-8 is `xrdsst` (Step 3 below), which does all of this declaratively.

### Step 3: Automate Security Server Configuration
With the anchor downloaded, you can use the `xrdsst` toolkit to automate the configuration of all 4 Security Servers at once.

Run everything from the example root (`examples/timor-leste`). The declarative config lives in `xroad/config/`.

```bash
cd examples/timor-leste
cp ../../.env.example .env       # the template lives at the repo root
# Edit .env and ensure XRDSST_ADMIN and TOKEN_PIN are correct
set -a; source .env; set +a
source .venv/bin/activate

tools/scripts/generate-ss-api-keys.sh
set -a; source .env; set +a
xrdsst -c xroad/config/xrdsst-config.yaml apply            # certificates, subsystems, services, ACLs
```

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
