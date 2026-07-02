# Core concepts: Member vs Subsystem vs Security Server

These three are different things. Mixing them up is the most common X-Road onboarding mistake.

| Concept | What it is | Identifier | Where in the Central Server |
|---|---|---|---|
| **Member** | An organization that joins X-Road (agency, company, operator) | `INSTANCE/CLASS/CODE` e.g. `TL-TEST/GOV/MJ` | Members / Clients |
| **Subsystem** | A logical group of services **inside** a member. It consumes/provides services and holds ACLs. | `…/CLASS/CODE/SUBSYSTEM` e.g. `TL-TEST/GOV/MJ/JUSTICE` | Member → Subsystems tab |
| **Security Server** | The gateway machine that hosts clients and routes signed messages over mTLS. Has an owner member + a server code. | `INSTANCE/CLASS/CODE/SERVER_CODE` e.g. `TL-TEST/GOV/MJ/ss-mj` | Security Servers menu |

**Security Servers are NOT subsystems.** You never add a Security Server on the Subsystems tab.

## How they relate

```mermaid
graph TB
  subgraph M[Member — GOV/MJ sample provider]
    SUB1[Subsystem JUSTICE<br/>provides birth-certificate]
    SUB2[Subsystem ...]
  end
  SS[Security Server ss-mj<br/>owner GOV/MJ]
  M -->|owns| SS
  SUB1 -->|registered as a client on| SS
  SS <-->|mTLS 5500 / OCSP 5577| NET[Other Security Servers]
```

- A **member** owns one or more **Security Servers**.
- A **member** has zero or more **subsystems**.
- A **subsystem** becomes usable only when it is **registered as a client on a Security Server** (a management
  request approved by the Central Server). Until then it shows **UNREGISTERED**.

## Registration flow (per organization)

1. **Register the member** in the Central Server (Members → Add member; needs a member class first).
2. **Register the Security Server**: run its setup wizard (owner member + server code), generate the
   **authentication key** (CSR), sign it at the CA, import it, register the auth cert. The Central Server
   operator approves it under **Management Requests**. It then appears under **Security Servers**.
3. **Add and register the subsystems**: add the subsystem to the member, then on the Security Server **Add
   client** for that subsystem and send the registration request; the Central Server approves it.

## Statuses you will see

| Status | Meaning |
|---|---|
| `SAVED` | Saved locally on the Security Server, not yet sent for registration |
| `REGISTRATION IN PROGRESS` | Request sent, waiting for Central Server approval |
| `UNREGISTERED` | Exists logically (e.g. a subsystem) but not registered on any Security Server |
| `REGISTERED` | Active in the global configuration; usable |

## In this sandbox

- Members: `GOV/MJ`, `GOV/MOH`, `GOV/MTC`, `GOV/OSS` (plus `GOV/01` for the management service).
- Security Servers: `ss-mj`, `ss-moh`, `ss-mtc`, `ss-oss` (each owned by its member).
- Subsystems: `JUSTICE`, `HEALTH`, `DNTT`, `PORTAL`, `MANAGEMENT`.

### Full sandbox map (members, Security Servers, subsystems, who consumes what)

```mermaid
graph TB
  subgraph GOVT[Member GOV/01 — Operator]
    MGMT[MANAGEMENT<br/>management service provider]
  end
  subgraph MJ[Member GOV/MJ — Justice provider]
    SMJ[ss-mj] --- JUSTICE[JUSTICE<br/>provides birth-certificate/v1]
  end
  subgraph MOH[Member GOV/MOH — Health consumer]
    SMOH[ss-moh] --- HEALTH[HEALTH]
  end
  subgraph MTC[Member GOV/MTC — Transport / DNTT]
    SMTC[ss-mtc] --- DNTT[DNTT<br/>provides driver-license/v1]
  end
  subgraph OSS[Member GOV/OSS — One-Stop-Shop]
    SOSS[ss-oss] --- PORTAL[PORTAL<br/>citizen portal]
  end

  PORTAL -->|consumes| JUSTICE
  PORTAL -->|consumes| DNTT
  HEALTH -->|consumes| JUSTICE
  HEALTH -->|consumes| DNTT
  JUSTICE -->|consumes| DNTT

  classDef gov fill:#eef2ff,stroke:#4f46e5,color:#312e81;
  classDef mj fill:#f3e8ff,stroke:#7c3aed,color:#3b0764;
  classDef moh fill:#fff7ed,stroke:#d97706,color:#7c2d12;
  classDef mtc fill:#ecfeff,stroke:#0891b2,color:#164e63;
  classDef oss fill:#eff6ff,stroke:#2563eb,color:#1e3a8a;
  class GOVT,MGMT gov;
  class MJ,SMJ,JUSTICE mj;
  class MOH,SMOH,HEALTH moh;
  class MTC,SMTC,DNTT mtc;
  class OSS,SOSS,PORTAL oss;
```

- Each **member** owns one **Security Server** and exposes its services through a **subsystem**.
- Access (consume arrows) follows the ACLs in `xroad/config/topology.yml`: `driver-license` is granted to
  `PORTAL`, `JUSTICE`, `HEALTH`; `birth-certificate` is granted to `PORTAL`, `HEALTH`.

See `sandboxes/timor-leste/xroad/config/topology.yml` for the full map and the example README Step 2b for the
UI walkthrough. Official reference: <https://docs.x-road.global/>.
