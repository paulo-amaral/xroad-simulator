#!/usr/bin/env python3
"""One-Stop-Shop portal — sandbox demo.

A consumer information system. It authenticates the citizen with the eID via OpenID Connect
authorization_code + PKCE (RFC 7636) and verifies the ID-token signature against the IdP JWKS
(RFC 8725). It then calls government services THROUGH ITS SECURITY SERVER (ss-oss): the portal
speaks no X-Road security; ss-oss does mTLS, signing, OCSP and timestamping.

Docker note: the browser reaches the IdP at EID_PUBLIC_URL (localhost), the portal reaches it at
EID_INTERNAL_URL (host.docker.internal). Token issuer/JWKS are validated against EID_INTERNAL_URL.
"""
import base64
import hashlib
import html
import json
import os
import secrets
import ssl
import urllib.parse
import urllib.request
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import jwt
from jwt import PyJWKClient

PORT = int(os.environ.get("PORT", "8080"))
EID_PUBLIC_URL = os.environ.get("EID_PUBLIC_URL", "http://localhost:9080")          # browser-facing
EID_INTERNAL_URL = os.environ.get("EID_INTERNAL_URL", "http://host.docker.internal:9080")  # portal-facing
EKYC_URL = os.environ.get("EKYC_URL", "http://ekyc-mock:80/verify")
CLIENT_ID = os.environ.get("OIDC_CLIENT_ID", "balcao-unico")
REDIRECT_URI = os.environ.get("OIDC_REDIRECT_URI", "http://localhost:8000/callback")
XROAD_MODE = os.environ.get("XROAD_MODE", "demo")
XROAD_CLIENT = os.environ.get("XROAD_CLIENT", "TL-TEST/GOV/OSS/PORTAL")
SS_OSS = os.environ.get("SS_OSS", "https://ss-oss:8443")
ISSUER = EID_INTERNAL_URL + "/default"

# Self-signed sandbox certs on the Security Server (test/dev only; never reuse on a real instance).
# TLS 1.2 floor per GovTL norms (ban TLS 1.0/1.1); production must require 1.3 and verify the chain.
_CTX = ssl.create_default_context()
_CTX.minimum_version = ssl.TLSVersion.TLSv1_2
_CTX.check_hostname = False
_CTX.verify_mode = ssl.CERT_NONE

SECURITY_HEADERS = {
    "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
}

SERVICES = [
    {"title": "Birth Certificate", "icon": "📄",
     "service": "TL-TEST/GOV/MJ/JUSTICE/birth-certificate/v1", "resource": "certificates/TL-67890",
     "mock": "http://mj-mock:8080"},
    {"title": "Driver License", "icon": "🚗",
     "service": "TL-TEST/GOV/MTC/DNTT/driver-license/v1", "resource": "licenses/TL-12345",
     "mock": "http://dntt-mock:8080"},
]

SESSIONS = {}  # sid -> {"state","verifier","claims"}  (in-memory; sandbox only)


# ── OIDC authorization_code + PKCE ────────────────────────────────────────────
def pkce_pair():
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    return verifier, challenge


def authorize_url(state, challenge):
    q = urllib.parse.urlencode({
        "response_type": "code", "client_id": CLIENT_ID, "redirect_uri": REDIRECT_URI,
        "scope": "openid", "state": state, "code_challenge": challenge, "code_challenge_method": "S256",
    })
    return f"{EID_PUBLIC_URL}/default/authorize?{q}"


def exchange_code(code, verifier):
    data = urllib.parse.urlencode({
        "grant_type": "authorization_code", "code": code, "redirect_uri": REDIRECT_URI,
        "client_id": CLIENT_ID, "code_verifier": verifier,
    }).encode()
    with urllib.request.urlopen(EID_INTERNAL_URL + "/default/token", data=data, timeout=10) as r:
        return json.loads(r.read())["id_token"]


def verify_id_token(id_token):
    # RFC 8725: verify the signature against the IdP JWKS, allowlist the algorithm, check aud/iss/exp.
    signing_key = PyJWKClient(EID_INTERNAL_URL + "/default/jwks").get_signing_key_from_jwt(id_token)
    return jwt.decode(id_token, signing_key.key, algorithms=["RS256"],
                      audience=CLIENT_ID, issuer=ISSUER, options={"require": ["exp", "iat"]})


def verify_ekyc():
    # The One-Stop-Shop runs e-KYC identity verification against the e-KYC service (sandbox mock).
    with urllib.request.urlopen(EKYC_URL, timeout=8) as r:
        return json.loads(r.read())


# ── X-Road service call (through ss-oss) ──────────────────────────────────────
def call_service(svc):
    xroad_path = f"/r1/{svc['service']}/{svc['resource']}"
    headers = {"X-Road-Client": XROAD_CLIENT, "Accept": "application/json"}
    base = SS_OSS if XROAD_MODE == "xroad" else svc["mock"]
    req = urllib.request.Request(base + xroad_path, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=8, context=_CTX) as r:
            return {"ok": True, "status": r.status, "path": xroad_path,
                    "request_id": r.headers.get("X-Road-Request-Id", "-"),
                    "via": "ss-oss (Security Server)" if XROAD_MODE == "xroad" else "mock provider (demo)",
                    "body": r.read().decode("utf-8", "replace")[:1200]}
    except Exception as e:
        return {"ok": False, "path": xroad_path, "error": str(e)}


# ── Rendering ─────────────────────────────────────────────────────────────────
CSS = """
*{box-sizing:border-box} body{margin:0;font:15px/1.5 system-ui,Segoe UI,Roboto,sans-serif;background:#f4f6fb;color:#1f2a3a}
header{padding:18px 24px;border-bottom:1px solid #d7dee8;background:#fff;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px}
header h1{margin:0;font-size:22px} .muted{color:#5b6b82;font-size:13px}
.badge{display:inline-block;padding:3px 9px;border-radius:999px;font-size:12px;border:1px solid #d7dee8;font-weight:600}
.ok{color:#15803d;border-color:#bbf7d0} .bad{color:#dc2626;border-color:#fecaca}
a.btn{display:inline-block;padding:9px 16px;border-radius:8px;background:#2563eb;color:#fff;text-decoration:none;font-weight:600}
a.btn:hover{filter:brightness(1.05)}
main{max-width:920px;margin:0 auto;padding:22px}
.card{background:#fff;border:1px solid #d7dee8;border-radius:12px;padding:16px 18px;margin:14px 0;box-shadow:0 1px 3px rgba(16,24,40,.05)}
.card h2{margin:0 0 6px;font-size:17px} .req{font:12.5px ui-monospace,Menlo,monospace;color:#5b6b82;word-break:break-all}
pre{background:#f8fafc;border:1px solid #d7dee8;border-radius:8px;padding:10px;overflow:auto;font-size:12px;color:#334155}
.kv{color:#2563eb} .tag{font-size:12px;color:#5b6b82}
"""


def page(body_html, citizen_html):
    return f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>One-Stop-Shop — Timor-Leste</title>
<style>{CSS}</style></head><body>
<header><div><h1>One-Stop-Shop</h1><div class="muted">Government services portal — Timor-Leste (sandbox)</div></div>
<div>{citizen_html}</div></header>
<main>{body_html}</main></body></html>"""


def render_card(svc, res):
    head = f'<h2>{svc["icon"]} {html.escape(svc["title"])}</h2>'
    req = f'<div class="req">GET {html.escape(res["path"])}<br>X-Road-Client: {html.escape(XROAD_CLIENT)}</div>'
    if res["ok"]:
        meta = (f'<div class="tag">via <span class="kv">{html.escape(res["via"])}</span> · '
                f'status {res["status"]} · X-Road-Request-Id: {html.escape(res["request_id"])}</div>')
        return f'<div class="card">{head} <span class="badge ok">OK</span>{req}{meta}<pre>{html.escape(res["body"])}</pre></div>'
    return f'<div class="card">{head} <span class="badge bad">FALHOU</span>{req}<pre>{html.escape(res["error"])}</pre></div>'


def service_menu():
    items = "".join(
        f'<a class="btn" style="margin:0 10px 8px 0" href="/request?svc={i}">'
        f'{html.escape(s["icon"])} {html.escape(s["title"])}</a>'
        for i, s in enumerate(SERVICES))
    return ('<div class="card"><h2>Choose a service to request</h2>'
            '<p class="muted">Pick a service. The One-Stop-Shop requests it on your behalf through its '
            'Security Server (ss-oss); X-Road validates the call and returns the result.</p>'
            f'<div>{items}</div></div>')


def home_logged_in(sess, result_html=""):
    claims = sess.get("claims", {})
    ekyc = sess.get("ekyc", {})
    name = html.escape(str(claims.get("name", "Citizen")))
    nid = html.escape(str(claims.get("national_id", "-")))
    status = str(ekyc.get("status", "UNVERIFIED"))
    badge = "ok" if status == "VERIFIED" else "bad"
    detail = html.escape(f'assurance {ekyc.get("assurance", "-")} · {ekyc.get("method", "-")}')
    citizen = (f'<div><b>{name}</b> <span class="tag">national_id {nid}</span></div>'
               f'<div class="muted">eID verified (JWKS signature) · '
               f'e-KYC <span class="badge {badge}">{html.escape(status)}</span> '
               f'<span class="tag">{detail}</span> · '
               f'<a class="muted" href="/logout">sign out</a></div>')
    intro = ('<p class="muted">Session started via OIDC authorization_code + PKCE; the ID-token signature was '
             'verified against the eID JWKS, then the One-Stop-Shop ran e-KYC identity verification.</p>')
    return page(intro + service_menu() + result_html, citizen)


def home_anonymous(error=""):
    err = f'<div class="card"><span class="badge bad">Login error</span><pre>{html.escape(error)}</pre></div>' if error else ""
    body = ('<div class="card"><h2>Sign in to the One-Stop-Shop</h2>'
            '<p class="muted">Authenticate with your digital identity (eID) to access the services.</p>'
            '<p><a class="btn" href="/login">Sign in with eID</a></p></div>' + err)
    return page(body, '<span class="badge">not authenticated</span>')


# ── HTTP handler ──────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    server_version = "portal"
    sys_version = ""

    def _sid(self):
        c = cookies.SimpleCookie(self.headers.get("Cookie", ""))
        return c["sid"].value if "sid" in c else None

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path, qs = parsed.path, urllib.parse.parse_qs(parsed.query)
        if path == "/healthz":
            return self._send(200, "ok", "text/plain")
        if path == "/login":
            return self._login()
        if path == "/callback":
            return self._callback(qs)
        if path == "/logout":
            sid = self._sid()
            SESSIONS.pop(sid, None)
            return self._redirect("/")
        if path == "/request":
            return self._request(qs)
        if path not in ("/", "/index.html"):
            return self._send(404, "not found", "text/plain")
        sess = SESSIONS.get(self._sid() or "")
        if sess and sess.get("claims"):
            return self._send(200, home_logged_in(sess), "text/html; charset=utf-8")
        return self._send(200, home_anonymous(), "text/html; charset=utf-8")

    def _login(self):
        sid = secrets.token_urlsafe(24)
        state = secrets.token_urlsafe(16)
        verifier, challenge = pkce_pair()
        SESSIONS[sid] = {"state": state, "verifier": verifier}
        self._redirect(authorize_url(state, challenge),
                       set_cookie=f"sid={sid}; HttpOnly; Path=/; SameSite=Lax")

    def _callback(self, qs):
        sid = self._sid()
        sess = SESSIONS.get(sid or "")
        if not sess:
            return self._send(400, home_anonymous("session expired"), "text/html; charset=utf-8")
        if qs.get("state", [""])[0] != sess.get("state"):
            return self._send(400, home_anonymous("invalid state (CSRF)"), "text/html; charset=utf-8")
        try:
            id_token = exchange_code(qs.get("code", [""])[0], sess["verifier"])
            sess["claims"] = verify_id_token(id_token)
        except Exception as e:
            return self._send(400, home_anonymous(f"token verification failed: {e}"), "text/html; charset=utf-8")
        try:
            sess["ekyc"] = verify_ekyc()
        except Exception as e:
            sess["ekyc"] = {"status": "UNVERIFIED", "error": str(e)}
        self._redirect("/")

    def _request(self, qs):
        sess = SESSIONS.get(self._sid() or "")
        if not (sess and sess.get("claims")):
            return self._redirect("/")
        try:
            svc = SERVICES[int(qs.get("svc", ["-1"])[0])]
        except (ValueError, IndexError):
            return self._send(404, "unknown service", "text/plain")
        card = render_card(svc, call_service(svc))
        back = '<p><a class="muted" href="/">&larr; back to services</a></p>'
        return self._send(200, home_logged_in(sess, card + back), "text/html; charset=utf-8")

    def _redirect(self, location, set_cookie=None):
        self.send_response(302)
        self.send_header("Location", location)
        if set_cookie:
            self.send_header("Set-Cookie", set_cookie)
        for k, v in SECURITY_HEADERS.items():
            self.send_header(k, v)
        self.end_headers()

    def _send(self, code, body, ctype):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        for k, v in SECURITY_HEADERS.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print(f"One-Stop-Shop portal on :{PORT} (mode={XROAD_MODE}, issuer={ISSUER})")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
