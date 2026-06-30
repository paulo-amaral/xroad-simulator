# GovTL Technical Standards — English reference & project compliance

English rendering of the Timor-Leste *Normas, Protocolos e Standards para o Governo Digital* (v1.0, June 2026),
plus a compliance matrix mapping each mandatory norm to this X-Road project. Source (Portuguese):
[Normas de Referência Técnica GovTL.docx.md](./Normas%20de%20Refer%C3%AAncia%20T%C3%A9cnica%20GovTL.docx.md).

Priority categories: **Mandatory** (law must require it), **Recommended** (consolidated best practice),
**Reference** (model that guides the legislator), **Emerging** (anticipate and plan for adoption).

## Mandatory norms most relevant to X-Road work

| Area | Norm | Why it matters here |
|---|---|---|
| Interop | OpenAPI 3.1 (OAS) | API contracts for every government service |
| Interop | mTLS (RFC 8705) | Bidirectional auth between government systems |
| Interop | ISO 8601 / 4217 / 3166, UTF-8 / Unicode 15 | Dates, currencies, country codes; Tetum + Portuguese support |
| Interop | ISO/IEC 19941 | Cloud portability, anti lock-in |
| Identity | NIST SP 800-63-4 (IAL/AAL) | Assurance levels per citizen transaction |
| Identity | X.509 v3 (RFC 5280) | National PKI / CA structure |
| Identity | PAdES / XAdES / CAdES (ETSI EN 319) | Long-term legally valid e-signatures |
| Identity | OCSP / CRL (RFC 6960 / 5280) | Real-time certificate revocation |
| Identity | NIST FIPS 140-3 | HSM validation for PKI keys |
| Identity | AES-256 / SHA-3 / RSA-4096 / ECDSA P-384 | Minimum algorithms; ban MD5, SHA-1, RSA < 2048 |
| Platform | OpenID Connect 1.0, OAuth 2.1 | Citizen SSO and consented authorization |
| Platform | WCAG 2.2 AA | Minimum accessibility for citizen services |
| Platform | HL7 FHIR R4/R5 | Health-data exchange |
| Platform | ISO/IEC 25010:2023 | Measurable software quality |
| Security | ISO/IEC 27001:2022 + 27002:2022 | ISMS for critical-infrastructure operators |
| Security | ISO/IEC 27701, 29100; Privacy by Design | Privacy management and data minimization |
| Security | OWASP ASVS 4.0 (min L2) | App-security verification for public services |
| Procurement | OCDS, UBL 2.3, OSI OSS, ISO 27036, SBOM | Open standards, supply-chain security, anti lock-in |

## Key RFCs (forbid obsolete: TLS 1.0/1.1, plain HTTP, MD5, SHA-1)

- Transport/security: **RFC 8446** TLS 1.3, **RFC 9147** DTLS 1.3, **RFC 8705** OAuth mTLS, **RFC 4301/4303** IPsec.
- Web/API: **RFC 9110** HTTP Semantics, **RFC 9112/9113/9114** HTTP/1.1/2/3, **RFC 9000** QUIC, **RFC 8259** JSON, **RFC 7807** Problem Details.
- Identity: **RFC 6749** OAuth 2.0, **RFC 7636** PKCE, **RFC 9068** JWT access tokens, **RFC 7519/7515/7516/7517/7518** JWT/JWS/JWE/JWK/JWA, **RFC 8725** JWT BCP, **RFC 8414** AS metadata.
- PKI: **RFC 5280** X.509, **RFC 6960** OCSP, **RFC 4210** CMP, **RFC 8555** ACME, **RFC 5652** CMS, **RFC 3161** time-stamping.
- Crypto: **RFC 6234** SHA-2, **RFC 8032** EdDSA, **RFC 7748** X25519/X448, **RFC 8017** RSA.
- Infra/audit: **RFC 5905** NTPv4, **RFC 4033/4034/4035** DNSSEC, **RFC 7858** DoT, **RFC 8484** DoH, **RFC 5424** Syslog.

## SLA / KPI minimums for state ICT contracts (anti lock-in)

Availability ≥ 99.5% (transactional) / 99.9% (critical infra); RTO ≤ 4h (priority) / 2h (critical);
RPO ≤ 1h (transactional); MTTR ≤ 4h (P1); API latency p95 ≤ 200ms (transactional) / 500ms (query);
API error rate ≤ 0.1% (critical); vulnerability fix: Critical ≤ 24h, High ≤ 7d, Medium ≤ 30d;
data export in open formats ≤ 30 days; source-code escrow; ≤ 30% proprietary components, 0% proprietary
formats for permanent storage; security-incident notification to CERT within 4h.

## Compliance matrix — this project

Legend: met · partial / sandbox-only · gap (action needed).

| Norm | Status | Notes / action |
|---|---|---|
| mTLS between systems (RFC 8705) | met | Provided by X-Road Security Servers. Dev tooling uses `-k`/skip-verify on localhost only (documented). |
| X.509 PKI, OCSP (6960), TSA (3161) | met | Native to X-Road. Sandbox uses the Test CA; replace with FIPS 140-3 HSM + approved CA in production. |
| TLS 1.3 / ban TLS 1.0-1.1 (RFC 8446) | partial | X-Road enforces modern TLS. Local clients now pin a **TLS 1.2 floor**; production must require 1.3. |
| OpenAPI 3.1 for services | partial | Added specs under `sandboxes/timor-leste/api/`. Publish them as OpenAPI service descriptions (not plain REST). |
| OIDC 1.0 / OAuth 2.1 (citizen SSO) | partial | Portal integrates the eID mock. Production must use **authorization_code + PKCE (RFC 7636)**, not client_credentials. |
| JWT BCP (RFC 8725) | gap -> partial | Portal now rejects `alg=none`; production must **verify the signature** against the IdP JWKS and allowlist algs. |
| Algorithms: AES-256/SHA-3/RSA-4096/ECDSA P-384 | partial | Enforce in CA cert profiles and TLS cipher policy; ban MD5/SHA-1/RSA<2048. |
| Accessibility WCAG 2.2 AA | gap | Portal is a demo; production portal must meet AA (contrast, keyboard, ARIA, lang). |
| ISO 27001/27002, OWASP ASVS L2 | partial | Repo has secret hygiene, fail-closed, least-privilege ACLs, security headers on the portal. Full ISMS is organizational. |
| Privacy by Design, ISO 27701/29100 | met | Decentralized DBs (no data lake), least-privilege ACLs, minimal asserted claims, token isolation. |
| UTF-8 / Unicode (Tetum, Portuguese) | met | All services UTF-8. |
| Syslog (RFC 5424) audit | partial | Observability overlay ships logs (Loki); add syslog/audit-log forwarding for the real audit trail. |
| SBOM (procurement) | gap | Add an SBOM step (e.g. `syft`/`cyclonedx`) in CI before release. |
| Open source / open standards (anti lock-in) | met | X-Road, Docker, Postgres, nginx, Python stdlib; open formats throughout. |
| DNSSEC, post-quantum planning | gap (emerging) | Out of sandbox scope; plan for the `.tl` zone and PQC (FIPS 203/204/205) roadmap. |

## Recommended next actions (priority order)

1. Publish the two services as **OpenAPI 3.1** descriptions (specs already in `openapi/`).
2. Implement the citizen login as **authorization_code + PKCE**; verify the ID-token signature (JWKS) and allowlist `RS256`/`ES256`.
3. Enforce a **TLS 1.3** policy and the approved cipher/algorithm set at the Security Servers and any reverse proxies.
4. Add **SBOM** generation and a CVE gate to CI; wire the SLA KPIs into the observability dashboards.
5. Plan **WCAG 2.2 AA** for the production portal and **DNSSEC** + **PQC** roadmaps.

## Sources

- GovTL standards (Portuguese source): same directory.
- X-Road security architecture: <https://github.com/nordic-institute/X-Road/blob/develop/doc/Architecture/arc-sec_x_road_security_architecture.md>
