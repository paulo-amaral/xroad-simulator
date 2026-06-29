# Architecture & Market Best Practices

Anchor every design decision to the official X-Road component model, then apply mainstream
engineering practice on top. Read the official architecture docs before designing:

- General architecture — `doc/Architecture/arc-g_x-road_arhitecture.md`
- Security architecture — `doc/Architecture/arc-sec_x_road_security_architecture.md`
- Security Server — `doc/Architecture/arc-ss_x-road_security_server_architecture.md`
- Central Server — `doc/Architecture/arc-cs_x-road_central_server_architecture.md`
- Configuration proxy — `doc/Architecture/arc-cp_x-road_configuration_proxy_architecture.md`
- Audit log events — `doc/Architecture/spec-al_x-road_audit_log_events.md`

## X-Road component model (what owns what)

| Component | Responsibility |
|---|---|
| **Security Server** | Sole gateway between an information system and X-Road. Mediates SOAP/REST calls, manages signing + authentication keys (software or HSM token), signs/verifies messages, caches global config and OCSP validity, runs the message log and optional monitoring. "Encapsulates the security aspects of the X-Road infrastructure." |
| **Central Server** | Authoritative registry of members and security servers; holds the instance security policy (trusted CAs and TSAs); signs and distributes global configuration. |
| **Configuration Proxy** | Optional. Re-distributes signed global configuration to improve availability and offload the Central Server. |
| **Certification Authority (CA)** | Issues authentication certs (to security servers) and signing certs (to members); publishes validity via OCSP. |
| **Time-Stamping Authority (TSA)** | Issues RFC-3161 timestamps proving data existed at a point in time; consumed via async batch timestamping. |

## Trust model (PKI / mTLS / OCSP / timestamping) — this is the security spine

- **PKI foundation.** X.509 certs from recognized CAs. Each Security Server holds two cert types:
  **authentication certs** (secure the inter-server channel) and **signing certs** (member identity on messages).
- **Mutual TLS.** Security Servers use mutual certificate-based TLS on the Message Transport Protocol. Bidirectional verification before any message flows. Never trust the network.
- **Message signing.** Every message is signed; signatures are digital evidence (eIDAS-aligned). Tampered or unsigned messages are rejected.
- **OCSP validation.** Validity is checked via OCSP; responses ride *inside* the transport protocol, so the peer does not need direct OCSP reachability. Revoked → fail closed.
- **Timestamping.** Messages and signatures are logged and **batch-timestamped asynchronously** for long-term proof, decoupling exchange availability from TSA availability.
- **Signed global configuration.** The Central Server signs global config; security servers reject unsigned or tampered config.

See `zero-trust.md` for how to verify each of these in tests.

## Market best practices to apply (with the X-Road reason)

- **Hexagonal / ports-and-adapters.** Keep domain logic free of X-Road concerns. The Security Server already handles transport security, so model X-Road as an inbound/outbound *adapter*; the information system stays protocol-agnostic and unit-testable.
- **Contract-first.** Publish and version the OpenAPI 3 (REST) or WSDL (SOAP) contract before coding. It is the source of truth for contract tests.
- **Bind to the internal interface only.** The information system is never exposed directly; the Security Server is the single gateway. No bypass route.
- **Infrastructure as code.** `docker-compose.yml` + declarative `xrdsst` config + Kubernetes manifests, all version-controlled and re-runnable in CI (see `sandbox.md`).
- **Config & secrets via environment / HSM.** Twelve-factor config; PINs, API keys, and keys never in source. Production signing/auth keys belong in an HSM via PKCS#11.
- **Observability.** Structured logging (Logback/JSON), metrics (Micrometer/Dropwizard), and X-Road operational + environmental monitoring. The audit log spec (`spec-al`) defines the events to emit.
- **CI/CD + test pyramid.** Provision the sandbox with `xrdsst apply`, run unit → contract → integration → e2e (see `tdd.md`). Fail the build on a red test or a failed security/dependency scan.
- **Resilience.** Because timestamping and OCSP are async/batched, design and test for transient CA/TSA unavailability; the exchange must still complete and reconcile proof later.
- **Versioning & process.** Semantic versioning of the service contract, trunk-based development, conventional commits, dependency/CVE scanning in the pipeline.

## References

- Architecture docs index: https://github.com/nordic-institute/X-Road/tree/develop/doc/Architecture
- Official documentation portal: https://docs.x-road.global
- Knowledge base: https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/overview
