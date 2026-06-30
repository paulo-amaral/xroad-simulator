#!/usr/bin/env python3
"""Orchestrate the Timor-Leste X-Road sandbox: up, status, identity, anchor, down.

Standard library only, kept in Python to match the X-Road provisioning tooling (xrdsst).
Run from sandboxes/timor-leste:  ./sandboxctl.py <command>
"""
import argparse
import http.cookiejar
import json
import os
import re
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

EXAMPLE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/ -> example root
COMPOSE_FILE = os.path.join(EXAMPLE_DIR, "docker-compose.yml")
CS_URL = "https://localhost:4000"
EID_DISCOVER = "http://localhost:9080/default/.well-known/openid-configuration"
EKYC_VERIFY = "http://localhost:9081/verify"
PORTAL_URL = "http://localhost:8000"
ANCHOR_OUT = os.path.join(EXAMPLE_DIR, "xroad", "anchors", "TL-TEST-anchor.xml")

# Insecure context for localhost self-signed sandbox certs (test/dev only; never reuse on a real instance).
# TLS 1.2 floor per GovTL norms (ban TLS 1.0/1.1); production must require 1.3 and verify the chain.
_CTX = ssl.create_default_context()
_CTX.minimum_version = ssl.TLSVersion.TLSv1_2
_CTX.check_hostname = False
_CTX.verify_mode = ssl.CERT_NONE


def log(msg):
    print(f"\033[1;34m[sandboxctl]\033[0m {msg}")


def compose(*args):
    subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, *args], check=True)


def http_get(url, timeout=8):
    with urllib.request.urlopen(url, timeout=timeout, context=_CTX) as r:
        return r.status, r.read().decode("utf-8", "replace")


def wait_http(url, timeout=300):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            http_get(url, timeout=5)
            return True
        except Exception:
            time.sleep(5)
    return False


def check(name, url, want=""):
    try:
        status, body = http_get(url)
    except Exception as e:
        print(f"  \033[1;31m[FAIL]\033[0m {name:22} {e}")
        return False
    if status != 200 or (want and want not in body):
        print(f"  \033[1;31m[FAIL]\033[0m {name:22} status {status}")
        return False
    extra = ""
    if want == "issuer":
        try:
            extra = json.loads(body).get("issuer", "")
        except Exception:
            pass
    print(f"  \033[1;32m[OK]\033[0m {name:22} {extra}")
    return True


def cmd_up(args):
    log("pulling images")
    compose("pull")
    log("starting the ecosystem")
    compose("up", "-d")
    log(f"waiting for the Central Server at {CS_URL}")
    if not wait_http(CS_URL):
        sys.exit("Central Server not ready")
    log("up. Run './sandboxctl.py status' or open simulator.html")
    cmd_identity(args)


def cmd_status(args):
    compose("ps")
    print()
    check("Central Server", CS_URL)
    check("eID (OIDC)", EID_DISCOVER, "issuer")
    check("e-KYC", EKYC_VERIFY, "VERIFIED")


def cmd_identity(args):
    ok = check("eID (OIDC) discovery", EID_DISCOVER, "issuer")
    ok = check("e-KYC verify", EKYC_VERIFY, "VERIFIED") and ok
    if not ok:
        sys.exit("identity layer not healthy yet")


def create_api_key():
    # Create a management API key through the same session login used by the admin UI.
    admin = os.environ.get("XROAD_ADMIN", "xrd:secret")
    user, _, pw = admin.partition(":")
    roles = json.dumps(["XROAD_SYSTEM_ADMINISTRATOR", "XROAD_REGISTRATION_OFFICER", "XROAD_SECURITY_OFFICER"]).encode()
    cookiejar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=_CTX),
        urllib.request.HTTPCookieProcessor(cookiejar),
    )
    opener.open(CS_URL + "/", timeout=15).read()
    csrf = ""
    for cookie in cookiejar:
        if cookie.name == "XSRF-TOKEN":
            csrf = cookie.value
    data = urllib.parse.urlencode({"username": user, "password": pw}).encode()
    login = urllib.request.Request(CS_URL + "/login", data=data, method="POST",
                                   headers={"X-XSRF-TOKEN": csrf})
    opener.open(login, timeout=15).read()
    for cookie in cookiejar:
        if cookie.name == "XSRF-TOKEN":
            csrf = cookie.value
    req = urllib.request.Request(CS_URL + "/api/v1/api-keys", data=roles, method="POST",
                                 headers={"Content-Type": "application/json", "X-XSRF-TOKEN": csrf})
    with opener.open(req, timeout=15) as r:
        return json.loads(r.read())["key"]


def cmd_anchor(args):
    key = os.environ.get("CS_API_KEY")
    if not key:
        log("no CS_API_KEY set; creating a management API key via UI session")
        try:
            key = create_api_key()
        except Exception as e:
            sys.exit(f"could not create API key (is the Central Server up and initialized?): {e}")
    endpoint = CS_URL + "/api/v1/configuration-sources/INTERNAL/anchor/download"
    log(f"downloading anchor from {endpoint}")
    req = urllib.request.Request(endpoint, headers={"Authorization": f"X-Road-ApiKey token={key}"})
    try:
        with urllib.request.urlopen(req, timeout=15, context=_CTX) as r:
            body = r.read()
    except urllib.error.URLError as e:
        sys.exit(f"download failed: {e}")
    if b"<?xml" not in body:
        sys.exit("unexpected response - is the Central Server initialized?")
    os.makedirs(os.path.dirname(ANCHOR_OUT), exist_ok=True)
    with open(ANCHOR_OUT, "wb") as f:
        f.write(body)
    log(f"anchor saved to {ANCHOR_OUT}")


def cmd_test(args):
    ok = check("Portal (One-Stop-Shop)", PORTAL_URL, "One-Stop-Shop")
    ok = check("  birth-certificate", PORTAL_URL, "Birth Certificate") and ok
    ok = check("  driver-license", PORTAL_URL, "Driver License") and ok
    if not ok:
        sys.exit("portal not serving the services yet")


def cmd_logs(args):
    # Read-only: discover and filter a service's logs (default cs) for config/signing issues.
    svc, pattern = args.service, args.grep
    log(f"on-disk logs in {svc}:/var/log/xroad")
    subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, "exec", svc, "sh", "-lc",
                    f"ls -1 /var/log/xroad/ 2>/dev/null; echo '--- matches ---'; "
                    f"grep -rinE '{pattern}' /var/log/xroad/ 2>/dev/null | tail -n 60"], check=False)
    log(f"container stdout (last 15m) for {svc}:")
    out = subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, "logs", "--since", "15m", svc],
                         check=False, capture_output=True, text=True).stdout
    rx = re.compile(pattern, re.I)
    matched = [ln for ln in out.splitlines() if rx.search(ln)]
    print("\n".join(matched[-60:]) if matched else "(no matching lines in container stdout)")


def cmd_down(args):
    if args.wipe:
        compose("down", "-v")
    else:
        compose("stop")


def main():
    p = argparse.ArgumentParser(description="Timor-Leste X-Road sandbox orchestrator")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("up", help="start and wait for the Central Server").set_defaults(func=cmd_up)
    sub.add_parser("status", help="compose ps + health of CS, eID, e-KYC").set_defaults(func=cmd_status)
    sub.add_parser("identity", help="check the eID and e-KYC mocks").set_defaults(func=cmd_identity)
    sub.add_parser("anchor", help="download the global-config anchor (needs CS_API_KEY)").set_defaults(func=cmd_anchor)
    sub.add_parser("test", help="check the portal renders and calls the services").set_defaults(func=cmd_test)
    lg = sub.add_parser("logs", help="scan a service's logs for config/signing issues (read-only)")
    lg.add_argument("service", nargs="?", default="cs")
    lg.add_argument("--grep", default="global ?conf|signing|active key|error|fail")
    lg.set_defaults(func=cmd_logs)
    d = sub.add_parser("down", help="stop the sandbox without deleting persistent state")
    d.add_argument("--wipe", action="store_true", help="remove containers and volumes")
    d.set_defaults(func=cmd_down)
    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
