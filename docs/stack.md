# X-Road Stack & Identifiers

## Official technology matrix (NIIS core)

Align all work to these. Introducing alternatives requires explicit approval.

| Layer | Technology | Components |
|---|---|---|
| Language / runtime | Java 21, C, Node 18, JavaScript | Security Server, Central Server, Configuration proxy, Op. Monitoring |
| Framework | Spring Boot 3 | Security Server, Central Server |
| Frontend | Vue.js 3, TypeScript | Security Server, Central Server |
| RPC | gRPC | all components |
| App server | Jetty 11, Embedded Tomcat 10 | Security Server, Central Server |
| Database | PostgreSQL 15+ | Security Server, Central Server, Op. Monitoring |
| DB migration | Liquibase 4 | Security Server, Central Server, Op. Monitoring |
| API contract | OpenAPI 3 (REST), WSDL (SOAP) | Security Server, Central Server |
| Crypto / HSM | PKCS#11, GnuPG | Security Server, Central Server, Configuration proxy |
| Logging / metrics | Logback, Dropwizard Metrics 4 | all / Security Server |
| Web server | nginx | Central Server, Configuration proxy |

Build tool for the Java components is Gradle; frontend uses Npm 8. Verify the exact version against
`doc/Architecture/arc-tec_x-road_technologies.md` in the X-Road repo before pinning.

## Identifier formats (memorize — they appear in every header and ACL)

```
Client (subsystem) ID : [INSTANCE]/[MEMBER_CLASS]/[MEMBER_CODE]/[SUBSYSTEM_CODE]
Service ID            : [INSTANCE]/[MEMBER_CLASS]/[MEMBER_CODE]/[SUBSYSTEM_CODE]/[SERVICE_CODE]/[VERSION]
Security Server ID    : [INSTANCE]/[MEMBER_CLASS]/[MEMBER_CODE]/[SERVER_CODE]
```

`INSTANCE` is the X-Road instance (e.g. `DEV`, `FI-TEST`, `EE`). `MEMBER_CLASS` is e.g. `GOV`, `COM`, `ORG`.

## REST Message Protocol (consumer view)

```
GET https://<CONSUMER-SS>/r1/{INSTANCE}/{MEMBER_CLASS}/{MEMBER_CODE}/{SUBSYSTEM}/{SERVICE_CODE}/{path}
Header  X-Road-Client: {INSTANCE}/{MEMBER_CLASS}/{MEMBER_CODE}/{SUBSYSTEM}   (the caller)
```

Response headers to assert in tests: `X-Road-Request-Id`, `X-Road-Request-Hash`.
The provider's information system receives the request on the Security Server's internal interface only.

## References

- Technology matrix: https://github.com/nordic-institute/X-Road/blob/develop/doc/Architecture/arc-tec_x-road_technologies.md
- Tech radar: https://nordic-institute.github.io/X-Road-tech-radar/
- Message Protocol for REST: https://docs.x-road.global (Protocols section)
