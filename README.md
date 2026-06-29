# X-Road Simulator Farm

A development sandbox and reference for building on the **X-Road data exchange layer**: a complete X-Road
ecosystem (Central Server, test CA, Security Servers) running on Docker Compose / Kubernetes, plus consumer
and provider services built test-first against it.

Development follows the guides in [docs/](docs/README.md): a mandatory pre-flight gate, test-driven
development, zero-trust controls, and the official X-Road stack.

> All container images and credentials referenced here are for **test and development only**. They must never
> be used in production, and their default PINs, passwords, and test CA must never reach a real instance.

## Project structure

```text
xroad-simulator/
├── README.md                     This file
├── SECURITY.md                   What never to commit; pre-push checks
├── .gitignore / .env.example     Secret hygiene (keys, certs, anchors, state)
├── .githooks/                    Local commit safety hook
├── scripts/                      Repository checks
├── .github/workflows/ci.yml      Validate, secret scan, SBOM + CVE gate
│
├── docs/                         X-ROAD GENERAL reference + GovTL standards (not project-specific)
│   ├── architecture.md, stack.md, zero-trust.md, tdd.md, diagrams.md, sandbox.md,
│   ├── publish-rest-api.md, federation.md, observability.md, citizen-portal-ekyc.md
│   └── govtl-compliance.md (+ GovTL source)
│
├── infra/                        INFRA — Terraform + Ansible install simulation across distros
│
└── examples/timor-leste/         SIMULATED — the runnable sandbox
    ├── docker-compose.yml        CS + Test CA + 4 Security Servers + mocks + eID/e-KYC + portal
    ├── xroad/                    X-Road: config/ (topology, xrdsst), api/ (OpenAPI), anchors/
    ├── citizen/                  Citizen layer: identity/ (eID+e-KYC), portal/, simulator/
    ├── observability/            Grafana + Prometheus + Loki overlay
    ├── tools/                    sandboxctl.py + scripts/ (install, init-cs, anchor, sign, sbom)
    └── docs/                     TL-specific docs: diagram.md
```

Three concerns, separated: **`docs/`** = general X-Road knowledge, **`examples/timor-leste/`** = the
simulated sandbox, **`infra/`** = infrastructure automation.

## Trust model: the technologies X-Road relies on

The Security Server is the single gateway between an information system and the network, and it encapsulates
the security mechanisms below. Configure and verify them; never bypass them.

- **PKI (X.509).** Every Security Server holds two certificate types: authentication certificates that secure
  the inter-server channel, and signing certificates that carry member identity on each message. Certificates
  are issued by a recognized Certification Authority (CA).
- **Mutual TLS (mTLS).** Security Servers authenticate each other with mutual certificate-based TLS on the
  Message Transport Protocol before any message flows. The network is never trusted.
- **Message signing.** Every message is cryptographically signed; signatures serve as digital evidence and are
  aligned with eIDAS. Unsigned or tampered messages are rejected.
- **OCSP validation.** Certificate validity is checked through OCSP. Responses travel inside the transport
  protocol, so a peer needs no direct OCSP reachability. Revoked or expired certificates fail closed.
- **Timestamp validation (TSA, RFC 3161).** Messages and their signatures are logged and batch-timestamped by a
  Time-Stamping Authority to create long-term, non-repudiable proof, asynchronously from the exchange itself.
- **Signed global configuration.** The Central Server signs the global configuration; Security Servers reject
  unsigned or modified configuration.

Detail and how to verify each control in tests:
[zero-trust.md](docs/zero-trust.md) and
[architecture.md](docs/architecture.md).

## Central Server vs Security Server roles

The **Central Server (CS)** is the instance authority. It does not proxy citizen or ministry API traffic. Its
job is governance: member registry, member classes, security server registry, trust services, management
requests, and signed global configuration. Security Servers download and verify that signed configuration.

A **Security Server (SS)** is the gateway that actually exchanges messages. Every ministry, portal, or agency
information system connects through its own SS. The official installation guide also names special SS roles:

| Name in X-Road docs | What it means | Difference from the Central Server |
|---|---|---|
| **Management Security Server** | A normal Security Server that hosts the management service provider subsystem. Other Security Servers send registration requests through it. | It forwards/hosts management service calls, but the CS still owns approval, registry state, and signed global configuration. |
| **Monitoring Security Server** | A normal Security Server used by the operator to collect operational/environmental monitoring data from other Security Servers. | It reads monitoring data over X-Road; it is not the authority for membership, certificates, or global configuration. |
| **Consumer / provider Security Server** | A normal Security Server used by a subsystem to consume or publish services. | It handles mTLS, signing, OCSP, timestamping, ACL checks, and routing for data exchange only. |

So there is still one conceptual **Central Server** for the instance, plus many **Security Servers**. Some
Security Servers carry extra operator roles. In this sandbox, `ss-mtc` plays the management-provider role
(`DNTT + MANAGEMENT`) while `cs` remains the Central Server. See the official Security Server installation
guide: https://docs.x-road.global/Manuals/ig-ss_x-road_v6_security_server_installation_guide.html.

## Official stack

Java 21, Spring Boot 3, Vue.js 3 + TypeScript, PostgreSQL 15+, Liquibase 4, gRPC, OpenAPI 3, PKCS#11 (HSM).
See [stack.md](docs/stack.md).

## Prerequisites

- Docker Engine and Docker Compose (Linux x86-64; Docker Desktop on macOS/Windows is fine for development).
- Python 3 with `venv` and pip (for the `xrdsst` provisioning toolkit).
- Optional: a Kubernetes cluster for deploying the Security Server Sidecar at scale.

## Install and run the sandbox

The Timor-Leste reference ecosystem (X-Road 7.7.0) runs the Central Server, the test CA, and four Security Server
Sidecars, one per member: Justice (`ss-mj`), Health (`ss-moh`), Transport/DNTT (`ss-mtc`), and the
One-Stop-Shop (`ss-oss`). Behind the Security Servers sit the provider mocks `mj-mock` and `dntt-mock`;
the supporting citizen-identity mocks are `eid-mock` and `ekyc-mock` (Health consumes only, so it has no
provider mock). Full topology, ports, and the provisioning sequence are in the
[Timor-Leste README](examples/timor-leste/README.md); the generic sandbox pattern is in
[sandbox.md](docs/sandbox.md).

1. **Define your topology first.** Edit
   [examples/timor-leste/xroad/config/topology.yml](examples/timor-leste/xroad/config/topology.yml): X-Road instance, member classes/codes,
   subsystems, and which Security Server owns each. These identifiers propagate into every request header,
   ACL, and test.

2. **Start the ecosystem.**
   ```bash
   cd examples/timor-leste
   tools/scripts/install.sh
   ```
   Default UI ports: Central Server `4000`, test CA `8888`, Security Servers `1000` (ss-mj) / `2000`
   (ss-moh) / `3000` (ss-mtc) / `5000` (ss-oss).

3. **Initialize the Central Server and download the anchor.** Follow Step 2 in the
   [Timor-Leste README](examples/timor-leste/README.md). The Security Servers need
   `xroad/anchors/TL-TEST-anchor.xml` before `xrdsst` can provision them.

4. **Provision declaratively.** Keep secrets in environment variables, then apply:
   ```bash
   cp ../../.env.example .env
   set -a; source .env; set +a
   source .venv/bin/activate
   tools/scripts/generate-ss-api-keys.sh
   set -a; source .env; set +a
   xrdsst -c xroad/config/xrdsst-config.yaml apply
   ```
   This runs the full sequence (anchor, token login, key generation, certificate import/register/activate,
   timestamping, client and service registration, access grants). The ordered per-step commands are listed in
   [sandbox.md](docs/sandbox.md) for debugging.

5. **Develop test-first.** Follow the test pyramid in
   [tdd.md](docs/tdd.md): unit → contract (OpenAPI/WSDL) → integration against the
   sandbox → end-to-end across the full ecosystem.

## Network ports (Security Server defaults)

| Port | Direction | Purpose |
|---|---|---|
| TCP 5500 | external, in/out | Message exchange between Security Servers (mTLS) |
| TCP 5577 | external, in/out | OCSP response queries between Security Servers |
| TCP 4001 | external, out | Communication with the Central Server |
| TCP 80, 443 | external, out | Global configuration download, OCSP, timestamping |
| TCP 4000 | internal, in | Admin UI and management REST API (local only) |
| TCP 8080, 8443 | internal, in | Information system access points |

Trust-zone rule: only 5500 and 5577 face the external network; information systems sit behind 8080/8443 on
the internal network; the admin UI (4000) is local only. Full table:
[diagrams.md](docs/diagrams.md).

## Integration diagrams

Inter-ministry integrations are documented as versioned Mermaid diagrams (call sequence and federation
topology), kept next to the `xrdsst` configuration and updated in the same change. Ready-to-copy templates,
the protocol selection table, and the port map are in
[diagrams.md](docs/diagrams.md). Architecture and market best practices:
[architecture.md](docs/architecture.md).

## Simulate the install across Linux distros (Terraform + Ansible)

[infra/](infra/README.md) builds a matrix of systemd containers (Ubuntu 22.04/24.04, Rocky 8/9) with
Terraform and runs the official X-Road package install on each with Ansible, validating apt and yum repository
wiring per distro as in the documentation.

```bash
cd infra/terraform && terraform init && terraform apply
cd ../ansible && ansible-playbook -i inventory.ini site.yml
```

## Worked example: Timor-Leste (three ministries + One-Stop-Shop)

[examples/timor-leste/](examples/timor-leste/README.md) joins the Ministry of Justice, the Ministry of Health,
and Transport/DNTT, plus a One-Stop-Shop portal, to one `TL-TEST` instance. Justice publishes a
birth-certificate service and Transport/DNTT publishes a driver-license service; the One-Stop-Shop consumes
both on the citizen's behalf, while Health is a consumer. It includes a full Docker Compose ecosystem
(Central Server, Test CA, four Security Servers — one per member — provider mocks, eID/e-KYC, and the portal),
an `xrdsst` provisioning config, federation/sequence diagrams, and a walkthrough that shows how to sign
certificates with the sandbox Test CA when you have no Certificate Authority of your own.

```bash
cd examples/timor-leste && docker compose up -d
```

## Official documentation

- X-Road documentation portal: https://docs.x-road.global
- X-Road core repository (NIIS): https://github.com/nordic-institute/X-Road
- Architecture documents: https://github.com/nordic-institute/X-Road/tree/develop/doc/Architecture
- Security architecture: https://github.com/nordic-institute/X-Road/blob/develop/doc/Architecture/arc-sec_x_road_security_architecture.md
- Security Server Toolkit (`xrdsst`): https://github.com/nordic-institute/X-Road-Security-Server-toolkit
- Tech radar: https://nordic-institute.github.io/X-Road-tech-radar/
- Knowledge base: https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/overview
- Local test environment (Docker Compose): https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/281739671/
