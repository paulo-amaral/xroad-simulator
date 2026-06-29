# X-Road provisioning runbook (Timor-Leste sandbox)

Hard-won, end-to-end sequence to take the sandbox from "Security Servers registered" to
**real traffic flowing** (consumer → Security Servers → provider, HTTP 200 + X-Road proof
headers). Every step here is reproducible through the REST APIs; no UI clicks, no direct DB
writes. Test/dev only.

Verify the result at any time with `python3 tools/showcase.py` (live demo for officials) or
`tools/e2e-test.sh` (pass/fail).

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
SERVICE:.../MANAGEMENT/clientReg`. We host it on **ss-mtc** (the operator, MTC / TIC Timor).

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
| `SslAuthenticationFailed: ... not registered at security server ss-X` on **cross-SS** calls (but local works) | Every Security Server address in the global conf was `127.0.0.1`; in Docker each container's localhost is itself, so a cross-SS call loops back | Set each address to its container hostname: `PUT /system/server-address {"address":"ss-mtc"}` (one per server) |
| `TimestamperFailed: Cannot time-stamp messages` → `Could not find TSP certificate for timestamp` | The TSA was registered in the CS with a URL but **no certificate** | Extract the Test CA TSA cert (`/home/ca/CA/certs/tsa.cert.pem`), delete the certless entry, `POST /timestamping-services` (multipart `url` + `certificate`) |
| `Security server has no valid authentication certificate` / `TLS handshake failed` after a date change | Cached OCSP responses expired | `supervisorctl restart xroad-signer` on the affected Security Server to re-fetch OCSP |

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
