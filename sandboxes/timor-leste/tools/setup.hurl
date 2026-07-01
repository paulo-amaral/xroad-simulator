# Declarative Central Server provisioning for the Timor-Leste sandbox, in the xrd-dev-stack style.
# Run inside the Hurl container, following the upstream xrd-dev-stack shape:
#   docker compose --profile test run --rm hurl --insecure \
#     --variables-file /tools/setup.vars --file-root /tools /tools/setup.hurl \
#     --very-verbose --retry 12 --retry-interval 10000
# The cert files are expected under /tools through --file-root, like upstream mounts ca-volume as
# /hurl-files and passes --file-root /hurl-files.
# Test/dev only.

# ── Session login + management API key (this CS rejects basic auth on /api/v1) ──
GET https://cs:4000/
HTTP *
[Captures]
xsrf: cookie "XSRF-TOKEN"

POST https://cs:4000/login
X-XSRF-TOKEN: {{xsrf}}
[FormParams]
username: {{admin_user}}
password: {{admin_pass}}
HTTP *
[Captures]
xsrf: cookie "XSRF-TOKEN"

POST https://cs:4000/api/v1/api-keys
X-XSRF-TOKEN: {{xsrf}}
Content-Type: application/json
```["XROAD_SYSTEM_ADMINISTRATOR","XROAD_SECURITY_OFFICER","XROAD_REGISTRATION_OFFICER","XROAD_MANAGEMENT_SERVICE"]```
HTTP 200
[Captures]
apikey: jsonpath "$.key"

# ── Initialize the instance ────────────────────────────────────────────────────
POST https://cs:4000/api/v1/initialization
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "software_token_pin": "{{token_pin}}", "instance_identifier": "{{instance}}", "central_server_address": "cs" }
[Options]
retry: 30
retry-interval: 6000
HTTP *
[Asserts]
status toEqual 200 # 200 created, or 409 if already initialised — both fine on re-run

# ── Log in to the configuration signing token ──────────────────────────────────
PUT https://cs:4000/api/v1/tokens/0/login
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "password": "{{token_pin}}" }
HTTP *

# ── Internal + external signing keys (generate; activation follows global-conf rules) ──
POST https://cs:4000/api/v1/configuration-sources/INTERNAL/signing-keys
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "key_label": "internal-key", "token_id": "0" }
HTTP *

POST https://cs:4000/api/v1/configuration-sources/EXTERNAL/signing-keys
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "key_label": "external-key", "token_id": "0" }
HTTP *

# ── Member class, members, subsystems ──────────────────────────────────────────
POST https://cs:4000/api/v1/member-classes
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "code": "GOV", "description": "Government" }
HTTP *

POST https://cs:4000/api/v1/members
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "member_id": { "member_class": "GOV", "member_code": "01" }, "member_name": "Government of Timor-Leste" }
HTTP *

POST https://cs:4000/api/v1/members
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "member_id": { "member_class": "GOV", "member_code": "MJ" }, "member_name": "Ministry of Justice" }
HTTP *

POST https://cs:4000/api/v1/members
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "member_id": { "member_class": "GOV", "member_code": "SERVE" }, "member_name": "SERVE I.P." }
HTTP *

POST https://cs:4000/api/v1/members
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "member_id": { "member_class": "GOV", "member_code": "MTC" }, "member_name": "Ministry of Transport and Communications" }
HTTP *

POST https://cs:4000/api/v1/members
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "member_id": { "member_class": "GOV", "member_code": "OSS" }, "member_name": "Balkaun Uniku" }
HTTP *

POST https://cs:4000/api/v1/subsystems
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "subsystem_id": { "member_class": "GOV", "member_code": "01", "subsystem_code": "MANAGEMENT" } }
HTTP *

POST https://cs:4000/api/v1/subsystems
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "subsystem_id": { "member_class": "GOV", "member_code": "MJ", "subsystem_code": "JUSTICE" } }
HTTP *

POST https://cs:4000/api/v1/subsystems
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "subsystem_id": { "member_class": "GOV", "member_code": "SERVE", "subsystem_code": "REGISTRY" } }
HTTP *

POST https://cs:4000/api/v1/subsystems
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "subsystem_id": { "member_class": "GOV", "member_code": "MTC", "subsystem_code": "DNTT" } }
HTTP *

POST https://cs:4000/api/v1/subsystems
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "subsystem_id": { "member_class": "GOV", "member_code": "OSS", "subsystem_code": "PORTAL" } }
HTTP *

# ── Management service provider ─────────────────────────────────────────────────
PATCH https://cs:4000/api/v1/management-services-configuration
Authorization: X-Road-ApiKey token={{apikey}}
Content-Type: application/json
{ "service_provider_id": "SUBSYSTEM:{{instance}}:GOV:01:MANAGEMENT" }
HTTP *

# ── Trust services: CA (FI Provider profile), OCSP, TSA. Retry — these 400 until the first
#    global-configuration generation settles. The cert filenames are single-extension on purpose
#    (the CS rejects double extensions like ca.cert.pem with `double_file_extension`). ──
POST https://cs:4000/api/v1/certification-services
Authorization: X-Road-ApiKey token={{apikey}}
[MultipartFormData]
certificate: file,ca.pem; application/octet-stream
certificate_profile_info: ee.ria.xroad.common.certificateprofile.impl.FiVRKCertificateProfileInfoProvider
tls_auth: false
[Options]
retry: 60
retry-interval: 5000
HTTP *
[Asserts]
status toEqual 201
[Captures]
ca_id: jsonpath "$.id"

POST https://cs:4000/api/v1/certification-services/{{ca_id}}/ocsp-responders
Authorization: X-Road-ApiKey token={{apikey}}
[MultipartFormData]
url: http://testca:8888
HTTP *

POST https://cs:4000/api/v1/timestamping-services
Authorization: X-Road-ApiKey token={{apikey}}
[MultipartFormData]
certificate: file,tsa.pem
url: http://testca:8899
HTTP *

# ── Wait for the first successful global-configuration generation ──────────────
GET https://cs:4000/api/v1/configuration-sources/INTERNAL/anchor/download
Authorization: X-Road-ApiKey token={{apikey}}
[Options]
retry: 60
retry-interval: 6000
HTTP 200
