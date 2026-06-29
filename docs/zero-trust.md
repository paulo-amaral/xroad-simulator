# Zero Trust on X-Road

Principle: never trust the network, authenticate and authorize every message, assume breach, least privilege.
X-Road already provides most mechanisms. Your job is to configure them correctly, verify them in tests, and never bypass them.

## Control mapping (ZT tenet → X-Road mechanism → verify)

| Zero-trust tenet | X-Road mechanism | How to verify |
|---|---|---|
| Authenticate the peer | Mutual TLS between Security Servers (authentication certs) | Integration test fails when peer cert is untrusted |
| Authenticate every message | Message-level signing with signing certs | Tampered/unsigned message is rejected |
| Continuous credential validation | OCSP validation of certs on each exchange | Revoked cert path fails closed |
| Trust anchored, not assumed | Signed global configuration from Central Server | Reject unsigned/expired global conf |
| Non-repudiation & audit | ASiC-E message log, RFC-3161 timestamping | Each exchange yields a signed, timestamped container |
| Least privilege | Per-service ACLs, access rights groups, subsystem-scoped grants | Unauthorized subsystem is denied (negative test) |
| Protect keys | HSM via PKCS#11; software token only in dev | Production keys never in software token / source |
| Minimize attack surface | Information system binds to internal interface only; SS is sole gateway | No direct path to the IS bypassing the SS |

## Rules for this project

- **Fail closed.** Any verification error (cert, OCSP, signature, global conf) denies the request. No fallback path that proceeds on error.
- **No secrets in code or git.** Token PINs, API keys, and admin credentials come from environment variables (mirror the `xrdsst` config pattern). The sandbox default PIN/credentials are public test values and must never reach a real instance.
- **Least privilege by default.** Grant a subsystem access to exactly the services it needs, nothing wildcard.
- **Every grant has a matching deny test.** Authorization is only proven when the unauthorized case is tested.
- **Defense in depth.** Platform mTLS does not excuse skipping input validation and output encoding in the information system.

## Secrets & PII reminder

Never write certificates, private keys, PINs, API keys, or real member/PII data into issues, PRs, commits,
logs, or external services. Redact to `<REDACTED>` and flag leaks for rotation.
