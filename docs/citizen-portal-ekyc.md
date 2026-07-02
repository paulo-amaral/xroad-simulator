# Citizen portal (Balcao Unico / one-stop-shop) and e-KYC on X-Road

## The core distinction

X-Road authenticates **systems**, not citizens. So the Balcao Unico portal does **not** change X-Road's trust
model: it is simply another **consumer subsystem** (e.g. `TL-TEST/GOV/OSS/PORTAL`) behind its own Security
Server. Citizen authentication happens **outside and on top of** X-Road.

Two different "single authentications" coexist; do not conflate them:

| Layer | Mechanism | Question it answers |
|---|---|---|
| System trust (X-Road) | PKI, mTLS, signing certs, ACLs | Is this member system allowed to call this service? |
| Citizen identity (portal) | National eID / IdP (OIDC/SAML) + e-KYC | Is this person who they claim, and are they logged in? |

The portal is the bridge: it authenticates the citizen, then makes X-Road calls on the citizen's behalf.

## Does the portal need e-KYC? Yes

The Balcao Unico is the citizen entry point, so it needs **identity proofing and authentication**:

- **e-KYC (enrolment / proofing):** verify the person at registration. Document verification, biometric/liveness
  check, and validation against authoritative registries.
  Answers "is this real person who they claim?" once.
- **eID / IdP (session authentication):** every login proves the same person returns. Use OpenID Connect or
  SAML against a national eID scheme. Step-up authentication for sensitive operations.

e-KYC checks can themselves be exposed **as X-Road services** (civil registry lookup, biometric match),
so the e-KYC process orchestrates calls over X-Road to the authoritative source of truth.

## How a citizen request flows

1. Citizen logs in to Balcao Unico via eID/OIDC; e-KYC verified at enrolment.
2. Portal (subsystem `OSS/PORTAL`) calls an X-Road service through its Security Server (`ss-oss`).
3. The portal **asserts the citizen identity** in the request so the provider can authorize at the person
   level and log it. X-Road carries a conventional message **user id** (historically the SOAP `userId`; for
   REST, a header/claim agreed in the service contract). The citizen's OIDC session token never travels on
   X-Road, the portal translates session -> X-Road call.
4. Provider Security Server enforces its **ACL** (is `OSS/PORTAL` granted this service?), validates certs via
   OCSP, the message is signed and batch-timestamped (non-repudiation), then routed to the provider system.

## Zero-trust rules specific to a citizen portal

- **Least privilege, per service.** The portal is a high-value aggregator. Grant it access only to the exact
  services citizens use through it, never blanket access. Prefer per-endpoint ACLs.
- **Consent and purpose limitation.** Capture citizen consent; pass purpose; request the minimum data.
- **Audit at the person level.** Carry citizen id + portal id on every call; rely on the message log and
  timestamping for non-repudiation. The audit log spec (`spec-al`) defines events.
- **Token isolation.** Session/eID tokens stay at the portal boundary; they are not forwarded over X-Road.
- **Step-up auth** for sensitive services (e.g. changing records vs reading them).

## Deployment notes

- **Central Server placement is operational.** The Central Server is the instance authority (member registry,
  policy, signed global configuration). Hosting it with one operator does not give that operator access to
  other members' data, which is still governed by certificates and ACLs.
- **Each member keeps its own database.** This matches X-Road's decentralized model: there is no central
  data lake. Each member information system owns its data; each Security Server also has its own local
  `serverconf` and `messagelog` databases. Data is exchanged on request, point to point, never pooled.

## Sandbox representation

Add the portal as another member/subsystem with its own Security Server (`ss-oss`), grant it access to the
`driver-license` and `birth-certificate` services, and stand a mock eID/IdP + e-KYC service beside it. The
worked example does exactly this: `ss-oss` plus `eid-mock` (OIDC) and `ekyc-mock` (verify) containers. See
`sandboxes/timor-leste/citizen/identity/` (eid-config.json, ekyc.conf), `sandboxes/timor-leste/config/topology.yml`,
the portal under `sandboxes/timor-leste/citizen/portal/`, and the interactive map `sandboxes/timor-leste/citizen/simulator/simulator.html`.

## Sources

- X-Road message protocols (user id, headers): https://docs.x-road.global
- Security architecture: https://github.com/nordic-institute/X-Road/blob/develop/doc/Architecture/arc-sec_x_road_security_architecture.md
- Audit log events: https://github.com/nordic-institute/X-Road/blob/develop/doc/Architecture/spec-al_x-road_audit_log_events.md
