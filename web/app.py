"""
MailBox admin paneli — Mailcow üzərində nazik onboarding interfeysi.

TƏHLÜKƏSİZLİK: Bu tətbiqin ÖZ girişi yoxdur. O, yalnız 127.0.0.1-ə bağlanır və
Caddy-nin basic_auth-u ilə qorunur (bax caddy/mailadmin.Caddyfile). Onu heç vaxt
birbaşa xaricə açma — Mailcow API açarı burada saxlanılır.
"""
import os
import secrets
import string

import dns.resolver
import dns.reversename
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

MAIL_HOSTNAME = os.environ["MAIL_HOSTNAME"]
SERVER_IP = os.environ["SERVER_IP"]
API_KEY = os.environ["MAILCOW_API_KEY"]
API_BASE = os.environ.get("MAILCOW_API_URL", f"https://{MAIL_HOSTNAME}/api/v1")

Q_ALIASES = os.environ.get("DOMAIN_MAX_ALIASES", "400")
Q_MAILBOXES = os.environ.get("DOMAIN_MAX_MAILBOXES", "10")
Q_DEFAULT = os.environ.get("DOMAIN_DEFAULT_QUOTA", "1024")
Q_MAX_MB = os.environ.get("DOMAIN_MAX_MAILBOX_QUOTA", "5120")
Q_TOTAL = os.environ.get("DOMAIN_TOTAL_QUOTA", "5120")

app = FastAPI(title="MailBox admin")
HERE = os.path.dirname(__file__)


# --------------------------------------------------------------------------
# Mailcow API
# --------------------------------------------------------------------------
def mailcow(method: str, path: str, body: dict | None = None):
    try:
        r = httpx.request(
            method,
            f"{API_BASE}{path}",
            headers={"X-API-Key": API_KEY, "Content-Type": "application/json"},
            json=body,
            timeout=30.0,
        )
    except httpx.HTTPError as e:
        raise HTTPException(502, f"Mailcow API-yə çatmaq mümkün olmadı: {e}")

    if r.status_code in (401, 403):
        raise HTTPException(
            502,
            "Mailcow API açarı rədd edildi (401/403). Paneldə API açarının "
            "IP icazə siyahısını yoxla.",
        )
    if r.status_code >= 400:
        raise HTTPException(502, f"Mailcow API xətası {r.status_code}: {r.text[:300]}")
    try:
        return r.json()
    except ValueError:
        raise HTTPException(502, f"Mailcow gözlənilməz cavab verdi: {r.text[:300]}")


def expect_success(resp, ctx: str):
    """Mailcow add/* endpoint-ləri [{'type': 'success'|'danger', 'msg': [...]}] qaytarır."""
    item = resp[0] if isinstance(resp, list) and resp else resp
    if not isinstance(item, dict) or item.get("type") != "success":
        msg = item.get("msg") if isinstance(item, dict) else resp
        raise HTTPException(400, f"{ctx}: {msg}")
    return item


def genpass(n: int = 20) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(n))


# --------------------------------------------------------------------------
# DNS
# --------------------------------------------------------------------------
_resolver = dns.resolver.Resolver()
_resolver.nameservers = ["1.1.1.1", "8.8.8.8"]
_resolver.lifetime = 5.0


def _txt(name: str) -> list[str]:
    try:
        answers = _resolver.resolve(name, "TXT")
    except Exception:
        return []
    out = []
    for rdata in answers:
        # uzun TXT-lər hissələrə bölünür; birləşdiririk
        out.append(b"".join(rdata.strings).decode(errors="replace"))
    return out


def dns_records(domain: str, dkim_txt: str) -> list[dict]:
    return [
        {"type": "MX", "name": "@", "value": MAIL_HOSTNAME, "extra": "prioritet 10"},
        {"type": "TXT", "name": "@", "value": "v=spf1 mx ~all", "extra": "SPF — mövcud SPF varsa BİRLƏŞDİR, əvəz etmə"},
        {"type": "TXT", "name": "dkim._domainkey", "value": dkim_txt, "extra": "DKIM"},
        {"type": "TXT", "name": "_dmarc", "value": f"v=DMARC1; p=none; pct=100; rua=mailto:postmaster@{domain}", "extra": "DMARC"},
        {"type": "SRV", "name": "_autodiscover._tcp", "value": f"0 1 443 {MAIL_HOSTNAME}", "extra": "istəyə görə (Outlook)"},
    ]


def check_dns(domain: str) -> list[dict]:
    results = []

    def add(label, status, detail):
        results.append({"label": label, "status": status, "detail": detail})

    # MX
    try:
        mx = sorted(f"{r.preference} {str(r.exchange).rstrip('.')}" for r in _resolver.resolve(domain, "MX"))
    except Exception:
        mx = []
    if not mx:
        add("MX", "fail", "MX qeydi yoxdur")
    elif any(m.endswith(MAIL_HOSTNAME) for m in mx):
        others = [m for m in mx if not m.endswith(MAIL_HOSTNAME)]
        if others:
            add("MX", "warn", f"bizə işarə edir, amma başqa MX-lər də var: {', '.join(others)}")
        else:
            add("MX", "ok", ", ".join(mx))
    else:
        add("MX", "fail", f"bizə işarə etmir: {', '.join(mx)} (gözlənilən {MAIL_HOSTNAME})")

    # SPF
    spf = [t for t in _txt(domain) if t.lower().startswith("v=spf1")]
    if not spf:
        add("SPF", "fail", "SPF qeydi yoxdur")
    elif len(spf) > 1:
        add("SPF", "fail", f"BİRDƏN ÇOX SPF qeydi ({len(spf)}) — SPF tamamilə etibarsız sayılır")
    else:
        rec = spf[0]
        authorized = (
            " mx " in f" {rec} "
            or f"a:{MAIL_HOSTNAME}" in rec
            or f"ip4:{SERVER_IP}" in rec
        )
        add("SPF", "ok" if authorized else "fail",
            rec if authorized else f"serverimizi icazələndirmir: {rec}")

    # DKIM
    live = [t for t in _txt(f"dkim._domainkey.{domain}") if t.lower().startswith("v=dkim1")]
    if not live:
        add("DKIM", "fail", "dkim._domainkey qeydi yoxdur")
    elif len(live) > 1:
        add("DKIM", "fail", "birdən çox DKIM qeydi var")
    else:
        try:
            mc = mailcow("GET", f"/get/dkim/{domain}").get("dkim_txt", "")
        except HTTPException:
            mc = ""
        norm = lambda s: s.replace(" ", "").split("p=")[-1]
        if mc and norm(live[0]) == norm(mc):
            add("DKIM", "ok", "mövcuddur və Mailcow-dakı açarla eynidir")
        elif mc:
            add("DKIM", "fail", "DNS-dəki açar Mailcow-dakından FƏRQLİDİR — imza yoxlanmayacaq")
        else:
            add("DKIM", "warn", "DNS-də var, Mailcow-dakı açarla tutuşdurmaq alınmadı")

    # DMARC
    dmarc = [t for t in _txt(f"_dmarc.{domain}") if t.lower().startswith("v=dmarc1")]
    if not dmarc:
        add("DMARC", "warn", "yoxdur (məcburi deyil, tövsiyə olunur)")
    elif len(dmarc) > 1:
        add("DMARC", "fail", "birdən çox DMARC qeydi — etibarsız sayılır")
    else:
        add("DMARC", "ok", dmarc[0])

    # PTR (serverə aiddir, domenə yox)
    try:
        rev = dns.reversename.from_address(SERVER_IP)
        ptr = str(_resolver.resolve(rev, "PTR")[0]).rstrip(".")
    except Exception:
        ptr = ""
    add("PTR", "ok" if ptr == MAIL_HOSTNAME else "fail",
        ptr or "PTR qeydi yoxdur")

    return results


# --------------------------------------------------------------------------
# Modellər
# --------------------------------------------------------------------------
class DomainIn(BaseModel):
    domain: str = Field(min_length=3)


class MailboxIn(BaseModel):
    domain: str
    local_part: str
    quota: str = Q_DEFAULT
    name: str = ""


class DomainAdminIn(BaseModel):
    username: str
    domains: list[str]


# --------------------------------------------------------------------------
# Endpoint-lər
# --------------------------------------------------------------------------
@app.get("/api/config")
def cfg():
    return {"mail_hostname": MAIL_HOSTNAME, "server_ip": SERVER_IP}


@app.get("/api/domains")
def list_domains():
    resp = mailcow("GET", "/get/domain/all")
    if isinstance(resp, dict):
        resp = [resp]
    return [
        {
            "domain": d.get("domain_name") or d.get("domain"),
            "mailboxes": f"{d.get('mboxes_in_domain', 0)} / {d.get('max_num_mboxes_for_domain', 0)}",
            "quota_used": d.get("bytes_total", 0),
            "active": d.get("active_int", d.get("active", 0)),
        }
        for d in resp
        if isinstance(d, dict)
    ]


@app.post("/api/domains")
def add_domain(body: DomainIn):
    domain = body.domain.strip().lower()

    resp = mailcow("POST", "/add/domain", {
        "domain": domain, "description": "",
        "aliases": Q_ALIASES, "mailboxes": Q_MAILBOXES,
        "defquota": Q_DEFAULT, "maxquota": Q_MAX_MB, "quota": Q_TOTAL,
        "active": "1", "backupmx": "0", "relay_all_recipients": "0",
        "dkim_selector": "dkim", "key_size": "2048", "gal": "1",
    })
    already = "exists" in str(resp).lower()
    if not already:
        expect_success(resp, "Domen yaratma")

    dkim = mailcow("GET", f"/get/dkim/{domain}").get("dkim_txt", "")
    if not dkim:
        expect_success(
            mailcow("POST", "/add/dkim", {"domains": domain, "dkim_selector": "dkim", "key_size": "2048"}),
            "DKIM yaratma",
        )
        dkim = mailcow("GET", f"/get/dkim/{domain}").get("dkim_txt", "")
    if not dkim:
        raise HTTPException(500, "DKIM açarı alınmadı")

    return {"domain": domain, "already_existed": already, "records": dns_records(domain, dkim)}


@app.get("/api/dns/{domain}")
def dns_check(domain: str):
    return {"domain": domain, "checks": check_dns(domain)}


@app.get("/api/dns/{domain}/records")
def dns_records_for(domain: str):
    dkim = mailcow("GET", f"/get/dkim/{domain}").get("dkim_txt", "")
    if not dkim:
        raise HTTPException(404, "Bu domen üçün DKIM açarı yoxdur")
    return {"domain": domain, "records": dns_records(domain, dkim)}


@app.get("/api/dns/{domain}/records.txt", response_class=PlainTextResponse)
def dns_records_txt(domain: str):
    recs = dns_records_for(domain)["records"]
    lines = [f"{domain} — DNS qeydləri", f"Mail serveri: {MAIL_HOSTNAME} ({SERVER_IP})", ""]
    for r in recs:
        lines += [f"[{r['type']}] {r['name']}", f"  {r['value']}", f"  ({r['extra']})", ""]
    lines += [
        "QEYD: Cloudflare istifadə olunursa hamısı DNS only (boz bulud) olmalıdır.",
        "QEYD: Köhnə MX qeydlərini silin. Mövcud SPF varsa əvəz etməyin, birləşdirin.",
    ]
    return "\n".join(lines)


@app.get("/api/mailboxes/{domain}")
def list_mailboxes(domain: str):
    resp = mailcow("GET", f"/get/mailbox/all/{domain}")
    if isinstance(resp, dict):
        resp = [resp]
    return [
        {"username": m.get("username"), "quota": m.get("quota"), "active": m.get("active")}
        for m in resp
        if isinstance(m, dict) and m.get("username")
    ]


@app.post("/api/mailboxes")
def add_mailbox(body: MailboxIn):
    pw = genpass()
    expect_success(mailcow("POST", "/add/mailbox", {
        "local_part": body.local_part, "domain": body.domain,
        "name": body.name or body.local_part,
        "password": pw, "password2": pw,
        "quota": body.quota, "active": "1", "force_pw_update": "0",
        "tls_enforce_in": "0", "tls_enforce_out": "0",
    }), "Mailbox yaratma")
    return {"address": f"{body.local_part}@{body.domain}", "password": pw,
            "webmail": f"https://{MAIL_HOSTNAME}/SOGo/"}


@app.post("/api/domain-admins")
def add_domain_admin(body: DomainAdminIn):
    pw = genpass()
    expect_success(mailcow("POST", "/add/domain-admin", {
        "username": body.username, "password": pw, "password2": pw,
        "domains": body.domains, "active": "1",
    }), "Domain admin yaratma")
    return {"username": body.username, "password": pw,
            "domains": body.domains, "login": f"https://{MAIL_HOSTNAME}/"}


@app.get("/")
def index():
    return FileResponse(os.path.join(HERE, "static", "index.html"))


app.mount("/static", StaticFiles(directory=os.path.join(HERE, "static")), name="static")
