# X-Road provisioning runbook (Timor-Leste sandbox)

Hard-won, end-to-end sequence to take the sandbox from "Security Servers registered" to
**real traffic flowing** (consumer → Security Servers → provider, HTTP 200 + X-Road proof
headers). Every step here is reproducible through the REST APIs; no UI clicks, no direct DB
writes. Test/dev only.

Verify the result at any time with `tools/e2e-test.sh` (Hurl pass/fail) or
`python3 tools/showcase.py` (live demo for officials).

## Official bootstrap shape

This sandbox mirrors the official X-Road 7.8 `Docker/xrd-dev-stack` approach, but maps it to the
Timor-Leste topology:

1. Central Server: initialize instance `TL-TEST`, log in to the software token, create and activate
   internal/external signing keys, add member class `GOV`, members, subsystems, and the management
   service provider.
2. Trust services: add the Test CA, OCSP responder, and Test TSA with its certificate, then wait for
   successful global-configuration generation and download the anchor.
3. Security Servers: initialize from the anchor, log in to software tokens, add timestamping,
   add local clients, generate signing/authentication CSRs.
4. Certificate dance: sign CSRs with the Test CA, import certificates to each Security Server,
   **activate the signing certificate** (so the member can sign), register authentication
   certificates, and approve the Central Server management requests.
5. Management and services: host `SUBSYSTEM:TL-TEST:GOV:01:MANAGEMENT` on `ss-mtc`, register client
   subsystems, publish service descriptions, grant ACLs.
6. Activate every certificate (`tools/scripts/activate-certs.sh`): certificates are imported inactive
   and need a good OCSP response plus, for auth certs, the Central Server's approval before they reach
   `REGISTERED`. The script polls each Security Server and activates what is ready, then run
   Hurl/showcase verification. Skipping this leaves traffic failing although everything looks registered.

Use `./init.sh` for the whole path. If debugging manually, follow the staged commands printed by
`tools/scripts/install.sh`. Avoid a full `xrdsst ... apply` during first bootstrap because it can
collapse certificate, client-registration, and service-registration phases into the wrong order.

## 0. Central Server API access

This Central Server image **rejects HTTP basic auth on `/api/v1`**, so `create_api_key` via
`curl -u xrd:secret` returns 401. Use the same session the admin UI uses instead:

```bash
# 1. GET / to obtain the XSRF-TOKEN cookie  2. POST /login (form)  3. POST /api/v1/api-keys
# The created key is saved to .env as CS_API_KEY (gitignored).
```

The roles needed: `XROAD_SYSTEM_ADMINISTRATOR`, `XROAD_REGISTRATION_OFFICER`,
`XROAD_SECURITY_OFFICER`, `XROAD_MANAGEMENT_SERVICE`.

## 1. The management services Security Server (the hard part)

Registering any subsystem is **itself an X-Road call** to the management service
(`GOV/01/MANAGEMENT/clientReg`). Until a Security Server hosts that provider, every client
stays `SAVED` and you get `UnknownMember: Could not find addresses for service provider
SERVICE:.../MANAGEMENT/clientReg`. We host it on **ss-mtc** (the operator member).

1. **Pre-register the provider's Security Server** (Central Server). The provider
   `GOV:01:MANAGEMENT` is already appointed; the missing piece is `security_server_id`:
   ```
   POST /api/v1/management-services-configuration/register-provider
   {"security_server_id":"TL-TEST:GOV:MTC:ss-mtc"}
   ```
   After this the `GOV:01:MANAGEMENT` client on ss-mtc flips to `REGISTERED` (pre-registered).
2. **Signing certificate for member GOV/01 on ss-mtc** (cross-member hosting needs it):
   `POST /tokens/0/keys-with-csrs` (SIGNING, member `TL-TEST:GOV:01`, fields from
   `GET /certificate-authorities/Test CA/csr-subject-fields`) → download CSR (DER).
   - **Sign with `type=sign`**: `curl -F certreq=@csr -F type=sign http://localhost:8888/testca/sign`.
     The default `auto` issues an *authentication* cert and the import fails with
     `cert_wrong_usage`. Then `POST /token-certificates`.
3. **Publish the management WSDL** on the `GOV:01:MANAGEMENT` client (ss-mtc):
   `POST /clients/TL-TEST:GOV:01:MANAGEMENT/service-descriptions {"url":"http://cs/managementservices.wsdl","type":"WSDL"}`,
   set every service URL to `https://cs:4002/managementservice/manage/`
   (`PATCH /services/{id}` with `url_all:true`), then `PUT /service-descriptions/{id}/enable`.
4. **Grant access** to the management services for the `security-server-owners` global group:
   `POST /clients/TL-TEST:GOV:01:MANAGEMENT/service-clients/TL-TEST:security-server-owners/access-rights`
   with `clientReg`, `clientDeletion`, `authCertDeletion`, `addressChange`, etc.

## 2. The three foundational fixes (or nothing flows)

These were the silent killers — the servers showed "registered" but no real message could pass.

| Symptom | Root cause | Fix |
|---|---|---|
| `init.sh` hangs forever at "waiting for global conf"; CS shows `Global configuration generation failing ... element 'managementService' is not complete ... managementRequestServiceProviderId is expected` | The management service **provider was never set**. The PATCH used the prefixed id `SUBSYSTEM:TL-TEST:GOV:01:MANAGEMENT`, which the CS API rejects with `invalid_service_provider_id`; the script only warned, so provisioning continued with the provider empty and generation could never succeed | PATCH `/management-services-configuration` with the **plain** subsystem id `TL-TEST:GOV:01:MANAGEMENT` (no `SUBSYSTEM:` prefix — the API stores it prefixed, but rejects it on input). `provision-cs.sh` now uses the plain form and **aborts loudly** if it fails instead of hanging |
| `SslAuthenticationFailed: ... not registered at security server ss-X` on **cross-SS** calls (but local works) | Every Security Server address in the global conf was `127.0.0.1`; in Docker each container's localhost is itself, so a cross-SS call loops back | Set each address to its container hostname: `PUT /system/server-address {"address":"ss-mtc"}` (one per server) |
| `TimestamperFailed: Cannot time-stamp messages` → `Could not find TSP certificate for timestamp` | The TSA was registered in the CS with a URL but **no certificate** | Extract the Test CA TSA cert (`/home/ca/CA/certs/tsa.cert.pem`), delete the certless entry, `POST /timestamping-services` (multipart `url` + `certificate`) |
| `Security server has no valid authentication certificate` / `TLS handshake failed` after a date change | Cached OCSP responses expired | `supervisorctl restart xroad-signer` on the affected Security Server to re-fetch OCSP |
| `Signer.InternalError: ... OCSP Response was null` on cert activation, **or** `TimestampValidation: Failed to verify timestamp` after hours of working traffic | A **stale duplicate Test CA** in the Central Server. The Test CA regenerates its key whenever `testca-home` is wiped, but the CS persists its trust list, so two `Test CA` entries end up sharing one subject DN. The Security Server keys CAs and TSAs by issuer DN, so the wrong (stale) entry can win and the OCSP responder URL and TSA certificate no longer resolve | Keep only the certification/timestamping services whose certificate matches the live `testca:/home/ca/CA/certs/{ca,tsa}.cert.pem`, delete the rest; `init.sh` step 4 now reconciles this on every run |

Order matters: fix **ss-mtc's address first** (its management service is local), let the global
conf propagate (~1 min), then the other servers can reach it.

## 3. Register the subsystems and publish services

With the management service live and addresses correct:

```
PUT /clients/TL-TEST:GOV:MJ:JUSTICE/register      (ss-mj :1000)
PUT /clients/TL-TEST:GOV:MTC:DNTT/register        (ss-mtc :3000)
PUT /clients/TL-TEST:GOV:OSS:PORTAL/register      (ss-oss :5000)
# approve each at the CS: POST /api/v1/management-requests/{id}/approval
```

Then grant the consumer access to the services (per `xroad/config/xrdsst-config.yaml`):

```
POST /clients/TL-TEST:GOV:MJ:JUSTICE/service-clients/TL-TEST:GOV:OSS:PORTAL/access-rights {"items":[{"service_code":"birth-certificate"}]}
POST /clients/TL-TEST:GOV:MTC:DNTT/service-clients/TL-TEST:GOV:OSS:PORTAL/access-rights {"items":[{"service_code":"driver-license"}]}
```

## 4. Error ladder (how to read progress)

Each fix advances the error by one layer — use it as a map:

```
UnknownMember (no mgmt host)
  → SslAuthenticationFailed (address 127.0.0.1)
  → AccessDenied (missing service ACL)
  → OutdatedGlobalConf (stale global conf, transient)
  → no valid auth certificate / TLS handshake (stale OCSP)
  -> HTTP 200 + X-Road-Request-Id OK
```

## 5. Turn on the portal

`docker-compose.yml`: `XROAD_MODE: "xroad"` makes the One-Stop-Shop route through `ss-oss:8443`
instead of calling the mocks directly. Recreate: `docker compose up -d portal`.

## Sources

- Central Server User Guide — Management Services: <https://docs.x-road.global>
- Security Server installation guide (ports, repos): <https://docs.x-road.global>
- Security Server Toolkit (`xrdsst`): <https://github.com/nordic-institute/X-Road-Security-Server-toolkit>
