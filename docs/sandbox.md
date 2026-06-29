# X-Road Sandbox Ecosystem (Docker / Kubernetes)

All images below are **test/development only**. Never use them in production, and never reuse their
default credentials, PINs, or the test CA outside the sandbox.

## Topology — DEFINE THIS FIRST (your input shapes everything downstream)

Before provisioning, decide and record your instance and member layout. This is a domain decision, not a
default to be guessed. Fill in and keep under version control:

```yaml
# topology.yml  — edit to match your scenario
x_road_instance: DEV
members:
  - member_class: GOV
    member_code: "1234"
    subsystems:
      - { code: CONSUMER, role: consumer, security_server: ss2 }
      - { code: PROVIDER, role: provider, security_server: ss3, services: [exampleService] }
security_servers:
  - { code: ss2, owner: GOV/1234 }   # consumer side
  - { code: ss3, owner: GOV/1234 }   # provider side
```

Why it matters: identifiers here propagate into every `X-Road-Client` header, every ACL grant, and every
test assertion. Wrong identifiers mean silent routing or authorization failures later.

## Reference compose stack (NIIS, X-Road 7.7.0)

Five containers form a complete ecosystem:

| Role | Image | UI port | Service ports |
|---|---|---|---|
| Central Server | `niis/xroad-central-server:noble-7.7.0` | 4000 | 4000 |
| Test CA (CA + OCSP + TSA) | `ghcr.io/nordic-institute/xrddev-testca:latest` | 8888 | 8888 |
| Security Server 1 (management) | `niis/xroad-security-server-sidecar:7.7.0` | 1000 | 1080, 1443 |
| Security Server 2 (consumer) | `niis/xroad-security-server-sidecar:7.7.0` | 2000 | 2080, 2443 |
| Security Server 3 (provider) | `niis/xroad-security-server-sidecar:7.7.0` | 3000 | 3080, 3443 |

Sandbox default env (test values, public — never real): `XROAD_ADMIN_USER=xrd`, `XROAD_ADMIN_PASSWORD=secret`,
`XROAD_TOKEN_PIN=123456xrd!`. Central Server UI defaults to `xrd` / `secret`.

```bash
docker compose up -d
docker compose logs -f          # watch initialization
```

For scale/HA tests, deploy the Security Server Sidecar to Kubernetes (Linux x86-64; Docker Desktop on
macOS/Windows is fine for dev but unsupported for production).

## Declarative provisioning with xrdsst (the testable artifact)

Install (from NIIS Artifactory; prerequisites Python 3.6+, pip 21+):

```bash
pip3 install --extra-index-url https://artifactory.niis.org/artifactory/xroad-extensions-release-pypi/ \
  xrdsst --trusted-host artifactory.niis.org
```

Config file references env vars for every secret (`api_key`, `admin_credentials`, `software_token_pin`).
Per server it declares: `url`, `configuration_anchor`, `software_token_id`, owner member, `certificates`,
`clients` (subsystems), and `service_descriptions` with `access` grants.

One-shot, idempotent provisioning of the whole topology:

```bash
xrdsst apply -c config.yaml
```

Equivalent ordered steps (useful for debugging a stuck stage):

```
xrdsst init                 # upload configuration anchor
xrdsst token login          # unlock software token
xrdsst token init-keys      # generate auth + sign keys
xrdsst cert download-csrs   # export CSRs
xrdsst cert import          # import signed certs (from test CA)
xrdsst cert register        # register with Central Server
xrdsst cert activate        # activate auth cert
xrdsst timestamp init       # configure TSA
xrdsst client add           # add subsystems
xrdsst client register      # register clients centrally
xrdsst service add-description
xrdsst service add-access   # grant ACLs (least privilege)
```

Treat `config.yaml` + `topology.yml` as code: review, version, and re-run `xrdsst apply` in CI so the
integration/e2e tests in `tdd.md` run against a reproducible ecosystem.

## References

- Local test env (Docker Compose): https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/281739671/
- Toolkit user guide: https://github.com/nordic-institute/X-Road-Security-Server-toolkit/blob/master/docs/xroad_security_server_toolkit_user_guide.md
- Sidecar user guide: https://docs.x-road.global/Sidecar/security_server_sidecar_user_guide.html
