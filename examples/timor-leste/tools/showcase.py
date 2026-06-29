#!/usr/bin/env python3
"""Live X-Road demo for officials.

Issues real consumer requests as the One-Stop-Shop (TL-TEST/GOV/OSS/PORTAL) through its
Security Server (ss-oss :5443). For each call it prints the request, the X-Road proof
headers (Request-Id, Request-Hash), and the provider's response — proving the message
actually transited the X-Road Security Servers. Test/dev sandbox only.

Run from examples/timor-leste:  python3 tools/showcase.py
"""
import json
import ssl
import urllib.request

CLIENT = "TL-TEST/GOV/OSS/PORTAL"
BASE = "https://localhost:5443/r1"  # ss-oss information-system access point (host-mapped)
CALLS = [
    ("Driver License  (MTC / DNTT)", "TL-TEST/GOV/MTC/DNTT/driver-license/v1/licenses/TL-12345"),
    ("Birth Certificate (MJ / Justice)", "TL-TEST/GOV/MJ/JUSTICE/birth-certificate/v1/certificates/TL-67890"),
]

# Self-signed sandbox certs on the Security Server (test/dev only).
_CTX = ssl.create_default_context()
_CTX.check_hostname = False
_CTX.verify_mode = ssl.CERT_NONE

B, G, R, Y, DIM, X = "\033[1;34m", "\033[1;32m", "\033[1;31m", "\033[0;33m", "\033[2m", "\033[0m"


def call(name, path):
    req = urllib.request.Request(f"{BASE}/{path}", headers={"X-Road-Client": CLIENT})
    print(f"\n{B}== {name} =={X}")
    print(f"  {DIM}request {X} GET /r1/{path}")
    print(f"  {DIM}client  {X} {CLIENT}")
    try:
        r = urllib.request.urlopen(req, timeout=12, context=_CTX)
        body, status, headers = r.read().decode("utf-8", "replace"), r.status, dict(r.headers)
    except Exception as e:
        print(f"  {R}FAILED{X}  {e}")
        return False
    ok = status == 200
    print(f"  {DIM}status  {X} {(G if ok else R)}HTTP {status}{X}")
    print(f"  {Y}X-Road proof headers{X}")
    for k, v in headers.items():
        if k.lower().startswith("x-road"):
            print(f"    {k}: {v}")
    try:  # the echo provider returns the request it received, including the X-Road headers
        d = json.loads(body)
        seen = {k: v for k, v in (d.get("headers") or {}).items() if k.lower().startswith("x-road")}
        print(f"  {Y}provider received{X} (echoed)")
        print(f"    path: {d.get('path')}")
        for k, v in seen.items():
            print(f"    {k}: {v}")
    except ValueError:
        print(f"  body: {body[:200]}")
    return ok


def main():
    print(f"{B}X-Road Timor-Leste — live service demo{X}")
    print(f"{DIM}Consumer {CLIENT} calling government services through its Security Server.{X}")
    results = [call(n, p) for n, p in CALLS]
    passed = sum(results)
    color = G if passed == len(results) else R
    print(f"\n{color}{passed}/{len(results)} services answered through X-Road.{X}\n")


if __name__ == "__main__":
    main()
