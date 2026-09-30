"""Read-only diagnostic: how can each competitor site's prices actually be read from THIS server?

    docker compose -p postyar exec -T api python -m app.admin_price_probe --brand "فروشگاه هوش مصنوعی" \
        [--products "ChatGPT Plus,Claude Pro"] [--sites parspremium.ir,cafearz.com]

For every site x product it tries each price strategy (Woo Store API, product sitemap, site search pages,
embedded JSON / markup, and the current price_search.lookup for comparison), records every request, detects
the platform / anti-bot layer, saves the interesting raw pages, prints a per-site table and writes
<out>/price_probe_latest.tgz (default /tmp/probe inside the container; copy out with `docker compose cp`). Writes nothing to the
database; all requests go through safe_fetch."""

import argparse
import json
import re
import sys
import tarfile
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from pathlib import Path
from urllib.parse import quote, unquote, urlencode, urljoin, urlparse

import httpx
from sqlalchemy import select

from . import safe_fetch
from .competitors import extract_products, normalize_competitors
from .price_search import lookup, matches, terms

DEFAULT_PRODUCTS = ["ChatGPT Plus", "Claude Pro", "Claude Max", "Gemini", "Cursor", "Midjourney", "Perplexity"]
SEED_SITES = [
    "parspremium.ir", "cafearz.com", "dicardo.com", "numberland.ir", "license-market.ir", "asangem.com",
    "account4all.ir", "g1verify.ir", "kharidaccount.ir", "licenseyar.ir", "premium24.ir", "codinocard.ir",
    "majazite.com", "giftpin.ir", "khanehlicense.ir", "www.iranicard.ir",
]
CHALLENGE = re.compile(
    r"just a moment|checking your browser|cf-browser-verification|cf-chl|arvancloud|arvan cloud|"
    r"attention required|enable javascript and cookies|ddos protection|access denied|captcha", re.I)
MAX_SAVED_BYTES = 18_000_000
PAGE_CAP = 400_000


class Recorder:
    """Every request of one site: url, status, final url, bytes, seconds, error. Also stores raw pages."""

    def __init__(self, site: str, out_dir: Path) -> None:
        self.site, self.dir, self.requests, self.saved = site, out_dir, [], 0
        out_dir.mkdir(parents=True, exist_ok=True)

    def fetch(self, url: str, label: str, save: bool = False, timeout: float = 12) -> dict:
        t0, rec = time.monotonic(), {"label": label, "url": url, "status": None, "final": url, "bytes": 0,
                                      "seconds": 0.0, "error": "", "blocked": False}
        body = ""
        try:
            r = safe_fetch.get(url, timeout=timeout, connect_timeout=6)
            body = r.text
            rec.update(status=r.status_code, final=str(r.url), bytes=len(r._content), server=r.headers.get("server", ""))
            rec["blocked"] = r.status_code in (401, 403, 429, 503) or bool(
                r.status_code >= 400 and CHALLENGE.search(body[:20000])) or bool(CHALLENGE.search(body[:3000]) and len(body) < 20000)
        except safe_fetch.UnsafeURLError as e:
            rec["error"] = f"unsafe/dns: {e}"
        except httpx.ConnectTimeout:
            rec["error"] = "timeout (connect)"
        except httpx.TimeoutException:
            rec["error"] = "timeout (read)"
        except httpx.ConnectError as e:
            rec["error"] = f"connect: {str(e)[:120]}"
        except httpx.HTTPError as e:
            rec["error"] = f"{type(e).__name__}: {str(e)[:120]}"
        rec["seconds"] = round(time.monotonic() - t0, 2)
        self.requests.append(rec)
        if save and body and self.saved < MAX_SAVED_BYTES:
            name = f"{len(self.requests):02d}_{re.sub(r'[^A-Za-z0-9]+', '_', label)[:40]}.txt"
            data = body[:PAGE_CAP]
            (self.dir / name).write_text(f"<!-- {url} -> {rec['final']} [{rec['status']}] -->\n{data}", encoding="utf-8")
            self.saved += len(data)
        rec["_body"] = body
        return rec


def detect_platform(home: dict) -> tuple[str, bool]:
    body = home.get("_body", "")
    if not body:
        return "unknown", home.get("blocked", False)
    low = body.lower()
    if "__next_data__" in low:
        plat = "nextjs"
    elif "window.__nuxt__" in low or "__nuxt" in low:
        plat = "nuxt"
    elif "woocommerce" in low:
        plat = "woocommerce"
    elif "wp-content" in low or "wp-json" in low:
        plat = "wordpress"
    elif "laravel" in low or "csrf-token" in low:
        plat = "laravel/custom"
    else:
        plat = "custom"
    return plat, home.get("blocked", False)


def minor(price, unit) -> int | None:
    try:
        return int(price) // (10 ** int(unit or 0))
    except (TypeError, ValueError):
        return None


def store_api(rec: Recorder, base: str, query: str) -> list[dict]:
    out = []
    for path in ("/wp-json/wc/store/v1/products", "/wp-json/wc/store/products"):
        r = rec.fetch(base + path + "?" + urlencode({"search": ' '.join(terms(query)) or query, "per_page": 20}), f"store_api {query}", save=True)
        try:
            data = json.loads(r["_body"])
        except ValueError:
            continue
        if not isinstance(data, list):
            continue
        for p in data:
            pr = p.get("prices") or {}
            cur, unit = pr.get("currency_code", ""), pr.get("currency_minor_unit", 0)
            price = minor(pr.get("price"), unit)
            if price is not None and cur.upper() in ("IRR", "ريال", "ریال"):
                price //= 10
            out.append({"name": re.sub(r"<[^>]+>", "", p.get("name", "")), "raw": f"{pr.get('price')} {cur} (minor={unit})",
                        "price": price, "url": p.get("permalink", ""), "in_stock": p.get("is_in_stock"),
                        "variations": len(p.get("variations") or []), "type": p.get("type")})
        if out:
            break
    return out


def sitemap_candidates(rec: Recorder, base: str, query: str, limit: int = 3) -> list[str]:
    robots = rec.fetch(base + "/robots.txt", "robots")["_body"]
    maps = re.findall(r"(?im)^sitemap:\s*(\S+)", robots) or [base + p for p in ("/sitemap_index.xml", "/sitemap.xml", "/product-sitemap.xml")]
    seen, urls, queue = set(), [], list(dict.fromkeys(maps))[:4]
    while queue and len(seen) < 8:
        sm = queue.pop(0)
        if sm in seen:
            continue
        seen.add(sm)
        xml = rec.fetch(sm, "sitemap", save=len(seen) <= 2)["_body"]
        locs = re.findall(r"(?is)<loc>\s*([^<\s]+)\s*</loc>", xml)
        if "<sitemapindex" in xml.lower():
            queue += [l for l in locs if "product" in l.lower()][:4] or locs[:3]
        else:
            urls += locs
    want = terms(query)
    scored = [(sum(w in unquote(u).lower().replace("-", " ") for w in want), u) for u in urls]
    return [u for s, u in sorted(scored, reverse=True) if s and s == len(want)][:limit]


def page_products(rec: Recorder, url: str, query: str, label: str) -> list[dict]:
    r = rec.fetch(url, label, save=True)
    body = r["_body"]
    out = []
    for p in extract_products(body) if body else []:
        if matches(query, p["name"]):
            out.append({"name": p["name"], "raw": "", "price": p.get("price"), "url": url,
                        "in_stock": p.get("in_stock"), "currency": p.get("currency"), "duration": p.get("duration", "")})
    return out


def probe_site(site: str, products: list[str], root: Path) -> dict:
    base = site if "://" in site else "https://" + site
    base = base.rstrip("/")
    host = (urlparse(base).hostname or site).removeprefix("www.")
    rec = Recorder(host, root / host)
    home = rec.fetch(base + "/", "homepage", save=True)
    platform, blocked = detect_platform(home)
    reachable = home["status"] is not None and not home["error"]
    api_ok = rec.fetch(base + "/wp-json/wc/store/v1/products?per_page=1", "store_api_probe")
    has_api = api_ok["status"] == 200 and api_ok["_body"].lstrip().startswith("[")
    plain_get_blocked = blocked or any(r["blocked"] for r in rec.requests)
    per_product = []
    for q in products:
        found: dict[str, list[dict]] = {}
        if reachable and not (blocked and home["status"] in (403, 503)):
            if has_api:
                found["woo_store_api"] = store_api(rec, base, q)
            for u in sitemap_candidates(rec, base, q):
                found.setdefault("sitemap", []).extend(page_products(rec, u, q, f"sitemap product {q}"))
            for pat in ("/?s={q}&post_type=product", "/search?q={q}", "/products?search={q}", "/shop?s={q}"):
                url = base + pat.format(q=quote(' '.join(terms(q)) or q))
                res = page_products(rec, url, q, f"search {pat[:12]} {q}")
                if res:
                    found.setdefault("search_page", []).extend(res)
                    break
        try:
            cur = lookup({"id": host, "name": host, "website": base}, q)
            found["current_lookup"] = [{"name": m["name"], "raw": "", "price": m["price"], "url": m["url"], "in_stock": m["in_stock"]}
                                       for m in cur["matches"]] or [{"status": cur["status"]}]
        except Exception as e:  # noqa: BLE001
            found["current_lookup"] = [{"status": f"error {e}"}]
        best = next((s for s in ("woo_store_api", "sitemap", "search_page") if any(m.get("price") for m in found.get(s, []))), "")
        per_product.append({"product": q, "strategies": found, "best": best or ("current_lookup" if any(m.get("price") for m in found["current_lookup"]) else "")})
    (rec.dir / "requests.json").write_text(json.dumps(
        [{k: v for k, v in r.items() if k != "_body"} for r in rec.requests], ensure_ascii=False, indent=1), encoding="utf-8")
    (rec.dir / "results.json").write_text(json.dumps(per_product, ensure_ascii=False, indent=1), encoding="utf-8")
    errors = sorted({r["error"] for r in rec.requests if r["error"]} | {f"HTTP {r['status']}" for r in rec.requests if r["status"] and r["status"] >= 400 and r["label"] in ("homepage",)})
    return {"site": host, "reachable": reachable, "platform": platform, "blocked": plain_get_blocked, "store_api": has_api,
            "requests": len(rec.requests), "per_product": per_product, "problem": "; ".join(errors)[:90],
            "home_status": home["status"], "server": home.get("server", "")}


def table(rows: list[dict]) -> str:
    head = ["site", "reachable", "platform", "blocked?", "best strategy", "products found", "example price", "problem"]
    lines = [" | ".join(head)]
    for r in rows:
        priced = [p for p in r["per_product"] if p["best"]]
        ex = ""
        for p in priced:
            m = next((m for s in ("woo_store_api", "sitemap", "search_page", "current_lookup") for m in p["strategies"].get(s, []) if m.get("price")), None)
            if m:
                ex = f"{p['product']}: {m['price']:,}"
                break
        best = max({p["best"] for p in priced}, key=lambda s: sum(p["best"] == s for p in priced), default="-") if priced else "-"
        lines.append(" | ".join([r["site"], "yes" if r["reachable"] else "NO", r["platform"] + ("+wcapi" if r["store_api"] else ""),
                                 "BLOCKED" if r["blocked"] else "no", best, f"{len(priced)}/{len(r['per_product'])}", ex or "-", r["problem"] or "-"]))
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--brand", default="", help="project name; its competitor websites are probed")
    ap.add_argument("--products", default=",".join(DEFAULT_PRODUCTS))
    ap.add_argument("--sites", default="", help="comma-separated site filter or explicit list when --brand is absent")
    ap.add_argument("--out", default="/tmp/probe", help="inside the container; copy out with docker compose cp")
    a = ap.parse_args(argv)
    products = [p.strip() for p in a.products.split(",") if p.strip()]
    sites = [s.strip() for s in a.sites.split(",") if s.strip()]
    if a.brand:
        from .db import SessionLocal

        with SessionLocal() as db:  # read-only
            from .models import Brand

            brands = db.scalars(select(Brand).where(Brand.name == a.brand)).all()
            if not brands:
                raise SystemExit(f"no project named {a.brand!r}")
            listed = [c["website"] for b in brands for c in normalize_competitors(b.competitors) if c["website"]]
        sites = [s for s in listed if not sites or any(f in s for f in sites)] or listed
    sites = sites or SEED_SITES
    root = Path(a.out) / date.today().isoformat()
    root.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(lambda s: probe_site(s, products, root), dict.fromkeys(sites)))
    (root / "summary.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    print(table(rows))
    print("\nPer product (site | product | strategy | name | price | in_stock | url):")
    for r in rows:
        for p in r["per_product"]:
            for s, ms in p["strategies"].items():
                for m in ms[:3]:
                    print(f"{r['site']} | {p['product']} | {s} | {m.get('name') or m.get('status')} | {m.get('price')} | {m.get('in_stock')} | {m.get('url', '')}")
    tgz = Path(a.out) / f"price_probe_{date.today().isoformat()}.tgz"
    with tarfile.open(tgz, "w:gz") as t:
        t.add(root, arcname=root.name)
    latest = Path(a.out) / "price_probe_latest.tgz"
    latest.write_bytes(tgz.read_bytes())
    print(f"\nsaved: {latest.resolve()} ({tgz.stat().st_size // 1024} KB)", file=sys.stderr)


if __name__ == "__main__":
    main()
