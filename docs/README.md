# Documentation

General X-Road reference, separated by concern.

## X-Road (general knowledge — official, not specific to this project)

- [concepts.md](concepts.md) — Member vs Subsystem vs Security Server, and the registration flow
- [architecture.md](architecture.md) — component model, trust model, market best practices
- [stack.md](stack.md) — official technology matrix and identifier formats
- [zero-trust.md](zero-trust.md) — zero-trust controls mapped to X-Road mechanisms
- [tdd.md](tdd.md) — test pyramid for X-Road services
- [diagrams.md](diagrams.md) — protocols, ports, and Mermaid templates
- [publish-rest-api.md](publish-rest-api.md) — publishing a provider REST API
- [federation.md](federation.md) — federating two X-Road ecosystems
- [observability.md](observability.md) — native + Grafana/Prometheus/Loki monitoring
- [citizen-portal-ekyc.md](citizen-portal-ekyc.md) — citizen portals, eID/e-KYC vs X-Road
- [sandbox.md](sandbox.md) — how to stand up an X-Road sandbox (NIIS test images + xrdsst)
- [technical-standards-compliance.md](technical-standards-compliance.md) — technical standards baseline + project compliance matrix

## Where the rest lives

- **Simulated example** (the runnable sandbox, mocks, portal, simulator): [../sandboxes/timor-leste/](../sandboxes/timor-leste/README.md)
- **Infra** (Terraform + Ansible install simulation across distros): [../infra/](../infra/README.md)
