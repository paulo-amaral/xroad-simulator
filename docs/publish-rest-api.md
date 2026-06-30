# Publish a REST API to X-Road (provider side)

Procedure on the **provider** Security Server, per the official guide. Contract-first: write/validate the
OpenAPI 3 spec before publishing, then import it.

## 1. Subsystem exists and is registered

In **Clients**, the publishing member has a subsystem (e.g. `DNTT`). Use **Add subsystem** if needed and keep
**Register subsystem** checked. Status moves `Registration in progress` → `Registered` once the Central Server
operator approves. You may configure services before registration completes, but external members cannot call
the service until both registration and configuration are done.

## 2. Add the service description (Services tab)

Pick the description type:

| Type | When | Endpoints |
|---|---|---|
| **OpenAPI 3** | Preferred. Spec is the contract. | Derived from the spec automatically. |
| **REST** | No spec available. | You add each endpoint (HTTP method + path) by hand. |

Set:
- **URL** = the provider information system base URL (internal interface), e.g. `http://dntt-mock:8080`.
- **Service code** = the X-Road service code, e.g. `driver-license`. This is the code consumers use in the path.
- For OpenAPI 3, give the URL of the spec; for REST, add endpoints under the service after creating it.

Then **enable** the service.

## 3. Grant access (least privilege)

Add access rights on the service (or per endpoint, for finer control): select the consumer subsystems allowed
to call it, e.g. `TL-TEST/GOV/MJ/JUSTICE` and `TL-TEST/GOV/MOH/HEALTH`. Grant only what each consumer needs.
A subsystem with no grant is denied; cover that with a negative test.

## 4. How a consumer calls it

Through the consumer's own Security Server, using the REST Message Protocol:

```
GET https://<CONSUMER-SS>/r1/{INSTANCE}/{CLASS}/{CODE}/{SUBSYSTEM}/{SERVICE_CODE}/{path}
Header  X-Road-Client: {INSTANCE}/{CLASS}/{CODE}/{SUBSYSTEM}     (the caller)
```

Example (Justice → DNTT):

```
GET https://ss-mj/r1/TL-TEST/GOV/MTC/DNTT/driver-license/v1/licenses/{id}
X-Road-Client: TL-TEST/GOV/MJ/JUSTICE
```

Response carries `X-Road-Request-Id` and `X-Road-Request-Hash`.

## Automating it

`xrdsst` declares the service and its access grants in config (`service_descriptions` with `rest_service_code`
or an OpenAPI URL, plus `access`). See the worked example `sandboxes/timor-leste/xroad/config/xrdsst-config.yaml`.

## Sources

- How to Publish a REST API to X-Road: https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/1153957893/
- REST Message Protocol: https://docs.x-road.global (Protocols section)
