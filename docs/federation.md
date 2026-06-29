# Federation between two X-Road ecosystems

Federation joins two X-Road instances so members publish and consume each other's services as if in the same
ecosystem (for example a Timor-Leste instance exchanging with a neighbouring country's instance). Trust is
extended by exchanging Central Server **external configuration anchors**; the instances are not merged.

## Prerequisites (structural — get these right early)

- **Unique instance identifiers.** Two ecosystems with the same identifier cannot federate. Choose e.g.
  `TL-TEST` distinct from the partner's code.
- **Distinct CA Common Names.** Approved CAs in each ecosystem must have different CN values.
- **Compatible certificate profile** implementations on both sides' classpath.
- **Network access:**
  - Central Servers reach each other on ports **80 and 443** (and must be reachable by both ecosystems' Security Servers).
  - Security Servers reach partner Security Servers on **5500** and **5577**.
- Both ecosystems must be initialised and **fully operational** before starting.

## Central Server steps (both sides)

1. On each Central Server, **Global Configuration → External Configuration**: download the external
   configuration anchor.
2. Exchange them: upload ecosystem A's anchor into Central Server B under **Global Configuration → Trusted
   Anchors**, and B's anchor into A.

## Security Server steps (per server needing cross-ecosystem exchange)

Federation is disabled by default. On each relevant Security Server:

```bash
sudo vi /etc/xroad/conf.d/local.ini
# add:
# [configuration-client]
# allowed-federations=<FEDERATED_INSTANCE_IDENTIFIER>
sudo supervisorctl restart xroad-confclient xroad-proxy
```

## Using federated services

- A consumer calls a service in the other instance using **that instance's identifier** in the path, e.g.
  `/r1/{PARTNER_INSTANCE}/{CLASS}/{CODE}/{SUBSYSTEM}/{SERVICE_CODE}/...` with its own `X-Road-Client` header.
- The provider grants **access rights to the external subsystem** exactly as it would a local one (least privilege still applies).

## Verify

- **Diagnostics → Connection Testing** (X-Road 7.8.0+): pick source client, REST request type, the federated
  **Target Instance**, target client, then **Test**.
- Or send a `listMethods` metaservice request with cross-instance client identifiers via curl.

## Sandbox note

To rehearse federation in the sandbox, run a second ecosystem (its own Central Server + Test CA + Security
Servers) with a different instance identifier and a Test CA whose CN differs, then exchange anchors as above.

## Sources

- How to Configure Federation Between Two X-Road Ecosystems: https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/1712226307/
- Central Server User Guide (external configuration / trusted anchors): https://docs.x-road.global
