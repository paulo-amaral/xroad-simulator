# Timor-Leste topology & service flows

Two layers, kept separate: the **One-Stop-Shop + identity** layer (citizen login, outside X-Road) and the
**X-Road** layer (secure system-to-system exchange).

## Topology

```mermaid
graph TB
  subgraph BU[One-Stop-Shop - outside X-Road]
    CIT[Citizen]
    EID[eID / OIDC + PKCE]
    EKYC[e-KYC verify]
    POR[One-Stop-Shop portal]
  end

  subgraph XR[X-Road]
    subgraph Trust[Trust services - MTC / TIC Timor]
      CS[Central Server<br/>members, policy, global conf]
      CA[Test CA + OCSP :8888]
      TSA[Test TSA :8899]
    end
    SSO[ss-oss<br/>GOV/OSS]
    subgraph MJ[Ministry of Justice]
      SSJ[ss-mj<br/>GOV/MJ · birth-certificate] --- DBJ[(Justice DB)]
    end
    subgraph MOH[Ministry of Health]
      SSH[ss-moh<br/>GOV/MOH] --- DBH[(Health DB)]
    end
    subgraph MTC[Transport - DNTT]
      SSD[ss-mtc<br/>GOV/MTC · driver-license] --- DBD[(DNTT DB)]
    end
  end

  CIT --> POR
  POR -->|"login (browser :9080)"| EID
  POR -->|"verify"| EKYC
  POR -->|":8443 internal"| SSO

  SSO <-->|"mTLS 5500 / OCSP 5577"| SSJ
  SSO <-->|"mTLS 5500 / OCSP 5577"| SSD
  SSH <-->|"mTLS 5500 / OCSP 5577"| SSD
  SSO -.->|"global conf"| CS
  SSJ -.->|"global conf"| CS
  SSD -.->|"global conf"| CS
  SSJ -.->|"OCSP / timestamp"| CA
  SSD -.->|"timestamp"| TSA

  classDef justica fill:#f3e8ff,stroke:#7c3aed,color:#3b0764;
  classDef saude fill:#fff7ed,stroke:#d97706,color:#7c2d12;
  classDef dntt fill:#ecfeff,stroke:#0891b2,color:#164e63;
  classDef bu fill:#eff6ff,stroke:#2563eb,color:#1e3a8a;
  class MJ,SSJ,DBJ justica;
  class MOH,SSH,DBH saude;
  class MTC,SSD,DBD dntt;
  class BU,CIT,EID,EKYC,POR bu;
```

## Citizen login (OIDC authorization_code + PKCE + JWKS)

Identity is handled in the One-Stop-Shop layer, before any X-Road call.

```mermaid
sequenceDiagram
    autonumber
    participant CIT as Citizen (browser)
    participant POR as One-Stop-Shop portal
    participant EID as eID / OIDC
    participant EKYC as e-KYC

    CIT->>POR: /login
    POR->>CIT: 302 -> /authorize (PKCE code_challenge, state)
    CIT->>EID: authenticate (localhost:9080)
    EID-->>CIT: 302 -> /callback?code,state
    CIT->>POR: /callback?code
    POR->>EID: token (code + code_verifier)  [PKCE]
    EID-->>POR: id_token (RS256 signed)
    POR->>EID: JWKS
    POR->>POR: verify signature + aud + iss + exp (RFC 8725)
    POR->>EKYC: verify
    EKYC-->>POR: VERIFIED (assurance high)
    Note over POR: session created with national_id, kyc_level
```

## Citizen service request via One-Stop-Shop (birth-certificate AND driver-license)

The portal asserts the citizen and calls each service through **its own Security Server (ss-oss)**.

```mermaid
sequenceDiagram
    autonumber
    participant POR as Portal (GOV/OSS/PORTAL)
    participant SSO as ss-oss
    participant SSP as ss-mj / ss-mtc (provider)
    participant ISP as Civil registry / DNTT
    participant TSA as Test TSA

    POR->>SSO: GET /r1/.../birth-certificate/v1/certificates/{id}<br/>and /r1/.../driver-license/v1/licenses/{id}<br/>X-Road-Client: TL-TEST/GOV/OSS/PORTAL  (:5443)
    Note over SSO,SSP: mTLS, message signed, OCSP checked, ACL enforced
    SSO->>SSP: Message Transport Protocol (5500)
    SSP->>ISP: forward (internal interface)
    ISP-->>SSP: record
    SSP-->>SSO: signed response
    SSO-->>POR: response + X-Road-Request-Id, X-Road-Request-Hash
    SSO->>TSA: batch timestamp (RFC 3161, async)
    SSP->>TSA: batch timestamp (RFC 3161, async)
```

## Inter-ministry (system-to-system, no portal)

```mermaid
sequenceDiagram
    autonumber
    participant SSJ as ss-mj (Justice)
    participant SSD as ss-mtc (DNTT)
    SSJ->>SSD: GET /r1/TL-TEST/GOV/MTC/DNTT/driver-license/v1/licenses/{id}<br/>X-Road-Client: TL-TEST/GOV/MJ/JUSTICE  (:1443)
    Note over SSJ,SSD: mTLS + signature + OCSP + ACL
    SSD-->>SSJ: signed response + X-Road-Request-Id
```
