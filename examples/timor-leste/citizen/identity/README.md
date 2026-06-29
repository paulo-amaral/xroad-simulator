# Citizen identity layer (mock)

Basic, test-only identity layer for the One-Stop-Shop portal. It sits **outside X-Road**: the portal
authenticates and verifies the citizen here, then makes X-Road calls on the citizen's behalf (asserting the
citizen user id). Session/eID tokens never travel over X-Road. See
[citizen-portal-ekyc.md](../../../../docs/citizen-portal-ekyc.md).

## Services

| Service | Image | Endpoint | Role |
|---|---|---|---|
| `eid-mock` | `ghcr.io/navikt/mock-oauth2-server:5.0.1` | `http://localhost:9080/default/.well-known/openid-configuration` | Mock eID / OIDC provider for citizen login |
| `ekyc-mock` | `nginx:1.27-alpine` (static verdict) | `http://localhost:9081/verify` | Mock identity-verification (e-KYC) endpoint |

## OIDC token contract (claims)

`eid-mock` is configured via [eid-config.json](eid-config.json) (`JSON_CONFIG_PATH`). Issued tokens carry the
claims the portal needs to identify the citizen and confirm proofing:

| Claim | Example | Meaning |
|---|---|---|
| `sub` | `tl-citizen-0001` | stable subject id |
| `national_id` | `TL-0001-1990` | national identifier asserted to providers |
| `name` | `Example Citizen` | display name |
| `kyc_level` | `high` | identity-assurance level from e-KYC |
| `kyc_method` | `document+liveness` | how the identity was proofed |

The portal reads `national_id` and `kyc_level` from the validated ID token, applies a minimum assurance for
sensitive services (step-up if needed), and asserts the citizen user id on each X-Road call. Edit the claims
in `eid-config.json` to model other citizens or assurance levels.

## How the portal uses them

1. Citizen logs in via `eid-mock` (OIDC authorization-code flow); the portal validates the ID token.
2. Portal calls `ekyc-mock` `/verify` to confirm identity proofing (in production: document + biometric/liveness).
3. Only then does the portal call government services over X-Road (`ss-oss`), e.g. birth-certificate or
   driver-license, with the citizen user id asserted and a matching ACL on the provider.

## Quick checks

```bash
# OIDC discovery document
curl -s http://localhost:9080/default/.well-known/openid-configuration | head

# e-KYC verdict (mock)
curl -s http://localhost:9081/verify
```

> Test/dev only. Replace `eid-mock` with the real national eID/IdP and `ekyc-mock` with the real e-KYC
> provider before anything beyond the sandbox. Never use these mocks for real identity decisions.
