# Security policy and safeguards

This repository is a **test/development X-Road sandbox**. It must never carry production secrets, real
certificates, private keys, or citizen data.

## Never commit

- Private keys, certificates, CSRs, keystores (`*.key`, `*.pem`, `*.p12`, `*.jks`, ...). Covered by `.gitignore`.
- `.env` files or any file holding passwords, PINs, API keys, or tokens. Use [.env.example](.env.example) as the template.
- X-Road global configuration anchors (`*-anchor.xml`) and downloaded `globalconf`.
- Terraform state (`*.tfstate`) and `*.tfvars` (may contain secrets).
- Real personally identifiable information (names, national IDs, driver-license numbers, addresses).

## Sandbox credentials are not real secrets

Default values such as `xrd` / `secret` and the token PIN are **public test values** from the official X-Road
documentation. They exist only to make the local sandbox run. Do not reuse them anywhere real, and replace
them via `.env` for any shared environment.

## The Test CA is for testing only

`ghcr.io/nordic-institute/xrddev-testca` issues certificates with no real trust. Replace it with an approved
Certificate Authority and TSA before any non-sandbox use.

## Before pushing to GitHub

1. Confirm `.gitignore` is in place and `git status` shows no `.env`, keys, certs, or anchors.
2. Run a secret scan: `pre-commit run --all-files` (config in [.pre-commit-config.yaml](.pre-commit-config.yaml))
   or `gitleaks detect --source .`
3. Review the diff for hardcoded credentials or PII.

## National standards (GovTL)

Security and interoperability must follow the Timor-Leste GovTL technical standards: TLS 1.3 (ban TLS 1.0/1.1),
OpenAPI 3.1, OIDC + PKCE, JWT best practices (RFC 8725), X.509/OCSP/timestamping, ISO 27001/27701, OWASP ASVS
L2, and SBOM in procurement. Compliance matrix and gaps:
[docs/govtl-compliance.md](docs/govtl-compliance.md).

## Reporting a vulnerability

Report security issues privately to the repository owner; do not open a public issue containing exploit
details, secrets, or PII.
