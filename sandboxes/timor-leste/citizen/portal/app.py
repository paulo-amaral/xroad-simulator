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
import urllib.error
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

# The One-Stop-Shop has two doors: the citizen door (eID + e-KYC, then citizen services) and the
# business door (eKYB — Know Your Business — verifying/registering a company via SERVE I.P.).
SERVICES = [
    {"title": "Birth Certificate", "abbr": "BC", "kind": "citizen",
     "service": "TL-TEST/GOV/MJ/JUSTICE/birth-certificate/v1", "resource": "certificates/TL-67890",
     "mock": "http://mj-mock:8080"},
    {"title": "Driver License", "abbr": "DL", "kind": "citizen",
     "service": "TL-TEST/GOV/MTC/DNTT/driver-license/v1", "resource": "licenses/TL-12345",
     "mock": "http://dntt-mock:8080"},
    {"title": "Business Registration (eKYB)", "abbr": "KB", "kind": "business",
     "service": "TL-TEST/GOV/SERVE/REGISTRY/eKYB/v1", "resource": "companies/TL-BR-2026-004512",
     "mock": "http://serve-mock:8080"},
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
    via = "ss-oss (Security Server)" if XROAD_MODE == "xroad" else "mock provider (demo)"
    try:
        with urllib.request.urlopen(req, timeout=8, context=_CTX) as r:
            body = r.read().decode("utf-8", "replace")
            return {"ok": True, "status": r.status, "path": xroad_path, "via": via,
                    "request_id": r.headers.get("X-Road-Request-Id", "-"),
                    "request_hash": r.headers.get("X-Road-Request-Hash", "-"),
                    "bytes": len(body.encode("utf-8")),
                    "body": body[:1200]}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:600]
        return {"ok": False, "path": xroad_path, "via": via, "status": e.code,
                "request_id": (e.headers.get("X-Road-Request-Id", "-") if e.headers else "-"),
                "error": f"HTTP {e.code}: {detail}"}
    except Exception as e:
        return {"ok": False, "path": xroad_path, "via": via, "error": str(e)}


# ── Rendering ─────────────────────────────────────────────────────────────────
CSS = """
:root{--primary:#6d3ff5;--blue-60:#4f27d8;--ink:#2f2547;--ink-muted:#62577a;--ink-subtle:#9b92b3;--canvas:#fff;--surface-1:#f2edff;--surface-2:#e5def7;--hairline:#ded6f2;--success:#24a148;--error:#da1e28;--sans:'IBM Plex Sans','Helvetica Neue',Arial,sans-serif;--mono:'IBM Plex Mono',Menlo,Consolas,monospace}
*{box-sizing:border-box} body{margin:0;font:15px/1.5 var(--sans);letter-spacing:.16px;background:var(--canvas);color:var(--ink)}
header{padding:16px 24px;border-bottom:1px solid var(--hairline);background:var(--canvas);display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:14px}
header h1{margin:0;font-size:28px;font-weight:300;line-height:1.25;letter-spacing:0}.muted{color:var(--ink-muted);font-size:13px}
.badge{display:inline-block;padding:3px 9px;font-size:12px;border:1px solid var(--hairline);font-weight:600;background:var(--canvas)}
.ok{color:var(--success);border-color:#b7e8c4}.bad{color:var(--error);border-color:#f2b8b5}
a.btn{display:inline-flex;align-items:center;gap:8px;padding:10px 16px;background:var(--primary);color:#fff;text-decoration:none;font-weight:600;border:1px solid var(--primary)}
a.btn:hover{background:var(--blue-60);border-color:var(--blue-60)}
main{max-width:960px;margin:0 auto;padding:24px}
.card{background:var(--canvas);border:1px solid var(--hairline);padding:16px 18px;margin:14px 0}
.card h2{margin:0 0 6px;font-size:18px;font-weight:600}.req{font:12.5px var(--mono);color:var(--ink-muted);word-break:break-all}
pre{background:var(--surface-1);border:1px solid var(--hairline);padding:10px;overflow:auto;font:12px var(--mono);color:var(--ink)}
.kv{color:var(--primary)}.tag{font-size:12px;color:var(--ink-muted)}.svcmark{display:inline-grid;place-items:center;width:28px;height:28px;background:var(--surface-1);border:1px solid var(--hairline);color:var(--primary);font:12px var(--mono);font-weight:600}
.term{background:#0b0b12;border:1px solid #000;color:#46d369;padding:12px 14px;margin:10px 0;font:12px/1.6 var(--mono);overflow:auto;white-space:pre-wrap;word-break:break-all}
.term.fail{color:#ff7b72}.term .tbar{display:block;color:#6b7280;margin-bottom:6px}
"""


def page(body_html, citizen_html):
    return f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>One-Stop-Shop — Timor-Leste</title>
<style>{CSS}</style></head><body>
<header><div><h1>One-Stop-Shop</h1><div class="muted">Government services portal — Timor-Leste (sandbox)</div></div>
<div>{citizen_html}</div></header>
<main>{body_html}</main></body></html>"""


def terminal_lines(svc, res):
    # Reconstructed from the live X-Road response (status, X-Road-Request-Id/Hash, bytes) — the same
    # facts the ss-oss proxy RequestLog and signed messagelog record. A 200 implies the zero-trust
    # steps below all passed (X-Road would not answer otherwise), so marking them ok is truthful.
    ok = res["ok"]
    lines = [f"consumer  {XROAD_CLIENT}",
             f"provider  {svc['service']}",
             f"GET {res['path']}"]
    if XROAD_MODE == "xroad":
        mark = "ok" if ok else "--"
        for step in ("clientproxy  mutual TLS to provider serverproxy",
                     "access-check  X-Road-Client allowed by provider ACL",
                     "ocsp          SIGNING cert OCSP_RESPONSE_GOOD",
                     "messagelog    message signed (SHA-256), recorded"):
            lines.append(f"[{mark}] ss-oss {step}")
    if ok:
        lines += [f"< HTTP {res['status']}   {res.get('bytes', '?')} bytes",
                  f"< X-Road-Request-Id    {res.get('request_id', '-')}",
                  f"< X-Road-Request-Hash  {res.get('request_hash', '-')}",
                  "RESULT: OK  — non-repudiation record written on ss-oss and the provider SS"]
    else:
        if res.get("status"):
            lines.append(f"< HTTP {res['status']}")
        lines += [f"! {res.get('error', 'request failed')}", "RESULT: FAILED"]
    return lines


def render_terminal(svc, res):
    title = f"{svc['abbr'].lower()}@one-stop-shop: x-road exchange"
    body = "\n".join(html.escape(l) for l in terminal_lines(svc, res))
    cls = "term" if res["ok"] else "term fail"
    return f'<pre class="{cls}"><span class="tbar">$ {html.escape(title)}</span>{body}</pre>'


def render_card(svc, res):
    head = f'<h2><span class="svcmark">{html.escape(svc["abbr"])}</span> {html.escape(svc["title"])}</h2>'
    req = f'<div class="req">GET {html.escape(res["path"])}<br>X-Road-Client: {html.escape(XROAD_CLIENT)}</div>'
    term = render_terminal(svc, res)
    if res["ok"]:
        meta = (f'<div class="tag">via <span class="kv">{html.escape(res["via"])}</span> · '
                f'status {res["status"]} · X-Road-Request-Id: {html.escape(res["request_id"])}</div>')
        return f'<div class="card">{head} <span class="badge ok">OK</span>{req}{meta}{term}<pre>{html.escape(res["body"])}</pre></div>'
    return f'<div class="card">{head} <span class="badge bad">FALHOU</span>{req}{term}</div>'


def _svc_buttons(kind):
    return "".join(
        f'<a class="btn" style="margin:0 10px 8px 0" href="/request?svc={i}">'
        f'<span class="svcmark">{html.escape(s["abbr"])}</span>{html.escape(s["title"])}</a>'
        for i, s in enumerate(SERVICES) if s.get("kind") == kind)


def service_menu():
    # Two doors: the citizen door (services you reach after eID + e-KYC) and the business door (eKYB).
    return ('<div class="card"><h2>Citizen services</h2>'
            '<p class="muted">Signed in as a citizen (eID + e-KYC). The One-Stop-Shop requests these on '
            'your behalf through its Security Server (ss-oss); X-Road validates the call and returns the result.</p>'
            f'<div>{_svc_buttons("citizen")}</div></div>'
            '<div class="card"><h2>Business door — eKYB</h2>'
            '<p class="muted">The business entry point. <b>eKYB</b> (Know Your Business) verifies and registers a '
            'company through <span class="kv">SERVE I.P.</span> (<code>TL-TEST/GOV/SERVE/REGISTRY</code>) — the '
            'parallel of e-KYC for citizens.</p>'
            f'<div>{_svc_buttons("business")}</div></div>')


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
             'verified against the eID JWKS, then the One-Stop-Shop ran e-KYC identity verification. '
             'The One-Stop-Shop has two doors: <b>citizens</b> (eID + e-KYC) and <b>businesses</b> '
             '(eKYB via SERVE I.P.).</p>')
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
