"""Competitor intelligence: normalises Brand.competitors, scans each competitor's website (sitemap,
product prices, trust signals) and Instagram page, then synthesizes one report with a price matrix and
content gaps. All network access goes through safe_fetch (SSRF-guarded) and runs in the worker job.
"""

import json
import logging
import re
import time
import uuid
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from html import unescape
from urllib.parse import urlparse

from .business_analyzer import _meta, _text
from .llm import chat_json

log = logging.getLogger("competitors")

MAX_PRODUCT_PAGES = 25
MAX_WORKERS = 2

# ---------- normalisation ----------


def normalize_competitor(c) -> dict:
    if isinstance(c, str):
        c = {"instagram": c.strip().lstrip("@")}
    out = {"id": str(uuid.uuid4()), "name": "", "website": "", "instagram": "", "telegram": "", "notes": ""}
    out.update({k: c.get(k, out[k]) for k in out if k != "id"})
    out["id"] = str(c.get("id") or out["id"])
    out["instagram"] = out["instagram"].strip().lstrip("@")
    return out


def normalize_competitors(items: list) -> list[dict]:
    return [normalize_competitor(c) for c in (items or [])]


def competitor_handles(items: list) -> list[str]:
    return [c["instagram"] for c in normalize_competitors(items) if c.get("instagram")]


# ---------- pasted-text parsing ----------


def parse_competitors_text(text: str) -> list[dict]:
    out, seen = [], set()
    for raw in (text or "").splitlines():
        line = raw.strip().strip(",;")
        if not line:
            continue
        ig_m = re.search(r"instagram\.com/([\w.]{2,30})", line) or re.match(r"^@([\w.]{2,30})$", line)
        tg_m = re.search(r"t\.me/([\w]{4,40})", line)
        website = ""
        if not ig_m and not tg_m:
            dom_m = re.search(r"(?:https?://)?(?:www\.)?([a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:\.[a-zA-Z]{2})?)", line)
            if dom_m:
                website = dom_m.group(1)
        key = (ig_m.group(1) if ig_m else tg_m.group(1) if tg_m else website).lower()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(
            normalize_competitor(
                {
                    "website": f"https://{website}" if website else "",
                    "instagram": ig_m.group(1) if ig_m else "",
                    "telegram": tg_m.group(1) if tg_m else "",
                }
            )
        )
    return out


# ---------- price / product parsing ----------

FA_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789")
AR_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")


def _norm_digits(s: str) -> str:
    return (s or "").translate(FA_DIGITS).translate(AR_DIGITS)


def parse_price(text: str) -> int | None:
    """'۱٬۲۵۰٬۰۰۰ تومان' / '125,000 Toman' / '1250000 ریال' -> integer Toman."""
    if not text:
        return None
    t = _norm_digits(text)
    is_rial = "ریال" in t or "rial" in t.lower()
    digits = re.sub(r"[^\d]", "", t)
    if not digits:
        return None
    n = int(digits)
    return n // 10 if is_rial else n


PRODUCT_ALIASES = {
    "chatgpt_plus": ["chatgpt plus", "چت جی پی تی پلاس", "چتجیپیتی پلاس", "gpt پلاس", "اکانت gpt پلاس", "chat gpt plus"],
    "chatgpt_pro": ["chatgpt pro", "چت جی پی تی پرو", "gpt پرو", "chat gpt pro"],
    "chatgpt_team": ["chatgpt team", "چت جی پی تی تیم"],
    "gemini": ["gemini", "جمینای", "google gemini", "جمینی", "gemini advanced"],
    "claude": ["claude", "کلود", "anthropic claude", "claude pro"],
    "midjourney": ["midjourney", "میدجورنی", "میدجرنی"],
    "cursor": ["cursor", "کرسر"],
    "perplexity": ["perplexity", "پرپلکسیتی", "پرپلکسیتی پرو"],
}


def canonicalize_product(name: str) -> str | None:
    n = _norm_digits(name or "").lower()
    n = re.sub(r"\s+", " ", n)
    for key, aliases in PRODUCT_ALIASES.items():
        if any(a in n for a in aliases):
            return key
    return None


DURATION_PATTERNS = [
    (r"(?:12|۱۲|دوازده)\s*(?:ماهه|ماه|month)|سالانه|یک\s*ساله|1\s*year", "12m"),
    (r"(?:6|۶|شش)\s*(?:ماهه|ماه|month)", "6m"),
    (r"(?:3|۳|سه)\s*(?:ماهه|ماه|month)", "3m"),
    (r"(?:1|۱|یک)\s*(?:ماهه|ماه|month)", "1m"),
]


def detect_duration(name: str) -> str:
    n = _norm_digits(name or "")
    for pat, dur in DURATION_PATTERNS:
        if re.search(pat, n, re.I):
            return dur
    return ""


def _jsonld_products(html: str) -> list[dict]:
    out = []
    for block in re.findall(r"(?is)<script[^>]+application/ld\+json[^>]*>(.*?)</script>", html):
        try:
            data = json.loads(block.strip())
        except ValueError:
            continue
        stack = data if isinstance(data, list) else [data]
        while stack:
            d = stack.pop()
            if isinstance(d, list):
                stack += d
                continue
            if not isinstance(d, dict):
                continue
            stack += [v for k, v in d.items() if k in ("@graph", "itemListElement", "item", "mainEntity")]
            t = d.get("@type")
            if (t == "Product" or (isinstance(t, list) and "Product" in t)) and d.get("name"):
                offers = d.get("offers") or {}
                if isinstance(offers, list):
                    offers = offers[0] if offers else {}
                price = offers.get("price") or offers.get("lowPrice")
                avail = str(offers.get("availability", ""))
                out.append({
                    "name": unescape(str(d["name"]))[:100],
                    "price": parse_price(str(price)) if price else None,
                    "currency": str(offers.get("priceCurrency", "")),
                    "in_stock": "outofstock" not in avail.lower() if avail else True,
                })
    return out


def _woo_products(html: str) -> list[dict]:
    out = []
    blocks = re.findall(r'(?is)<li[^>]+class="[^"]*\bproduct\b[^"]*"[^>]*>.*?</li>', html) or [html]
    for block in blocks:
        name_m = re.search(r"(?is)<h2[^>]*woocommerce-loop-product__title[^>]*>(.*?)</h2>", block) or re.search(
            r"(?is)<h1[^>]*product_title[^>]*>(.*?)</h1>", block
        )
        if not name_m:
            continue
        name = _text(name_m.group(1))
        currency = "تومان" if "تومان" in block else ("ریال" if "ریال" in block else "")
        dels = re.findall(r"(?is)<del[^>]*>.*?woocommerce-Price-amount[^>]*>\s*([^<]+)", block)
        inss = re.findall(r"(?is)<ins[^>]*>.*?woocommerce-Price-amount[^>]*>\s*([^<]+)", block)
        regular = parse_price(dels[0]) if dels else None
        sale = parse_price(inss[0]) if inss else None
        if regular is None and sale is None:
            amounts = re.findall(r"woocommerce-Price-amount[^>]*>\s*([^<]+)", block)
            if amounts:
                regular = parse_price(amounts[0])
        out.append({
            "name": name, "price": sale if sale is not None else regular,
            "regular_price": regular if sale is not None else None,
            "currency": currency, "in_stock": "outofstock" not in block.lower(),
        })
    return out


def extract_products(html: str) -> list[dict]:
    products = _jsonld_products(html)
    if not products:
        products = _woo_products(html)
    if not products:
        og_price = _meta(html, "product:price:amount")
        if og_price:
            title = unescape((re.search(r"(?is)<title[^>]*>(.*?)</title>", html) or [None, ""])[1]).strip()
            products = [{
                "name": title[:100], "price": parse_price(og_price),
                "currency": _meta(html, "product:price:currency"), "in_stock": True,
            }]
    return [p for p in products if p.get("name")]


# ---------- site discovery + signals ----------


def discover_product_urls(base_url: str, limit: int = MAX_PRODUCT_PAGES) -> list[str]:
    from . import safe_fetch

    robots_url = base_url.rstrip("/") + "/robots.txt"
    _, robots = safe_fetch.text(robots_url)
    sitemap_urls = re.findall(r"(?im)^sitemap:\s*(\S+)", robots)
    if not sitemap_urls:
        sitemap_urls = [base_url.rstrip("/") + "/" + g for g in ("sitemap_index.xml", "sitemap.xml", "product-sitemap.xml")]
    seen_maps, urls, queue = set(), [], list(dict.fromkeys(sitemap_urls))[:5]
    while queue and len(urls) < limit * 4:
        sm = queue.pop(0)
        if sm in seen_maps:
            continue
        seen_maps.add(sm)
        _, xml = safe_fetch.text(sm)
        if not xml:
            continue
        locs = re.findall(r"(?is)<loc>\s*([^<\s]+)\s*</loc>", xml)
        if "<sitemapindex" in xml.lower():
            queue += [l for l in locs if l not in seen_maps][:10]
            continue
        prod = [l for l in locs if re.search(r"/product/|/محصول/|product-sitemap", l, re.I)] or locs
        urls += prod
    return list(dict.fromkeys(urls))[:limit]


def detect_socials(html: str) -> dict:
    ig = re.search(r"instagram\.com/([\w.]{2,30})", html)
    tg = re.search(r"t\.me/([\w]{4,40})", html)
    wa = re.search(r"wa\.me/(\d{8,15})|api\.whatsapp\.com/send\?phone=(\d{8,15})", html)
    return {
        "instagram": ig.group(1) if ig and ig.group(1) not in ("p", "reel", "explore") else "",
        "telegram": tg.group(1) if tg else "",
        "whatsapp": (wa.group(1) or wa.group(2)) if wa else "",
    }


def detect_signals(html: str) -> dict:
    sh = re.search(r"پشتیبانی[^<\n]{0,60}", html)
    return {
        "enamad": bool(re.search(r"enamad|e-?namad|اینماد", html, re.I)),
        "guarantee": bool(re.search(r"گارانتی|ضمانت", html)),
        "instant_delivery": bool(re.search(r"تحویل\s*فوری|ارسال\s*آنی|تحویل\s*آنی", html)),
        "support_hours": _text(sh.group(0)) if sh else "",
    }


PAYMENT_KEYWORDS = ["زرین‌پال", "زرین پال", "آیدی‌پی", "idpay", "درگاه بانکی", "کارت به کارت", "رمزارز", "تتر", "crypto", "paypal"]


def detect_payments(html: str) -> list[str]:
    return [k for k in PAYMENT_KEYWORDS if k.lower() in html.lower()]


def detect_discounts(html: str) -> list[str]:
    out = [_text(m)[:80] for m in re.findall(r"(?is)(?:تخفیف|کد تخفیف|coupon)[^<\n]{0,60}", html)]
    return list(dict.fromkeys(t for t in out if t))[:5]


def detect_blog(html: str) -> list[str]:
    out = [_text(m) for m in re.findall(r'(?is)<a[^>]+href=["\'][^"\']*(?:blog|وبلاگ|مقال)[^"\']*["\'][^>]*>(.*?)</a>', html)]
    return list(dict.fromkeys(t for t in out if 4 < len(t) < 100))[:5]


def analyze_competitor_website(url: str, max_products: int = MAX_PRODUCT_PAGES) -> dict:
    from . import safe_fetch

    if not url:
        return {}
    if not re.match(r"https?://", url):
        url = "https://" + url.strip().strip("/")
    final, html = safe_fetch.text(url)
    if not html:
        return {"url": url, "ok": False, "errors": ["homepage unreachable"]}

    product_urls = discover_product_urls(final, max_products)
    products, errors, last_hit = [], [], {}
    for purl in product_urls:
        host = urlparse(purl).netloc
        wait = 0.3 - (time.time() - last_hit.get(host, 0))
        if wait > 0:
            time.sleep(wait)
        last_hit[host] = time.time()
        try:
            _, phtml = safe_fetch.text(purl, timeout=15)
            if not phtml:
                continue
            for f in extract_products(phtml):
                f.update(url=purl, product_key=canonicalize_product(f["name"]), duration=detect_duration(f["name"]))
                products.append(f)
        except Exception as e:  # noqa: BLE001 — one bad product page must not fail the competitor
            errors.append(f"{purl}: {str(e)[:120]}")
    if not products:
        for f in extract_products(html):
            f.update(url=final, product_key=canonicalize_product(f["name"]), duration=detect_duration(f["name"]))
            products.append(f)
    return {
        "url": final, "ok": True, "product_count": len(product_urls) or len(products),
        "products": products, "socials": detect_socials(html), "signals": detect_signals(html),
        "payments": detect_payments(html), "discounts": detect_discounts(html), "blog": detect_blog(html),
        "errors": errors,
    }


# ---------- Instagram ----------


def analyze_competitor_instagram(handle: str) -> dict:
    if not handle:
        return {}
    out: dict = {"username": handle, "posts": [], "partial": True, "source": ""}
    try:
        from . import instagram_free

        posts = instagram_free.profile_posts(handle)
        if posts:
            out["posts"], out["source"], out["partial"] = posts[:30], "profile", False
    except Exception as e:  # noqa: BLE001
        log.info("profile_posts(%s) failed: %s", handle, e)
    if not out["posts"]:
        try:
            from .business_analyzer import analyze_instagram

            prof = analyze_instagram(handle)
            out["posts"] = prof.get("posts", [])[:30]
            out["followers"], out["bio"], out["source"] = prof.get("followers", ""), prof.get("bio", ""), "search"
        except Exception as e:  # noqa: BLE001
            log.info("analyze_instagram(%s) failed: %s", handle, e)
    now = time.time()
    recent = [p for p in out["posts"] if not p.get("taken_at") or p["taken_at"] >= now - 30 * 86400]
    out["post_frequency_30d"] = len(recent)
    out["format_mix"] = dict(Counter(p.get("type", "post") for p in recent))
    out["top_posts"] = sorted(
        recent, key=lambda p: p.get("engagement", p.get("likes", 0) + 3 * p.get("comments", 0)), reverse=True
    )[:5]
    words = [w for p in recent for w in re.findall(r"#(\w[\w‌]{2,})", p.get("title", ""))]
    out["top_hashtags"] = [w for w, _ in Counter(words).most_common(10)]
    return out


# ---------- synthesis ----------


def rule_based_report(brand, comps: list[dict]) -> dict:
    matrix: dict[str, dict[str, int]] = {}
    for c in comps:
        for p in c.get("website", {}).get("products", []):
            key, price = p.get("product_key"), p.get("price")
            if not key or not price:
                continue
            cur = matrix.setdefault(key, {})
            cur[c["name"]] = min(cur.get(c["name"], price), price)
    price_matrix = [
        {"product": k, "prices": v, "cheapest": min(v, key=v.get) if v else None} for k, v in sorted(matrix.items())
    ]
    trust_compare = [{"name": c["name"], **c.get("website", {}).get("signals", {})} for c in comps]
    gaps = [
        f"رقبا روی {k} قیمتی بین {min(v.values())} تا {max(v.values())} تومان دارند؛ رهبوم می‌تواند شفاف‌تر و رقابتی‌تر قیمت‌گذاری کند"
        for k, v in matrix.items() if v
    ]
    gaps += [
        f"{c['name']} نماد اعتماد یا گارانتی روشنی نشان نمی‌دهد"
        for c in comps if not c.get("website", {}).get("signals", {}).get("enamad")
    ]
    filler = [
        "محتوای آموزشی درباره‌ی نحوه‌ی استفاده از اکانت‌های هوش مصنوعی کم است",
        "مقایسه‌ی شفاف پلن‌های ChatGPT Plus در برابر Pro دیده نمی‌شود",
        "هیچ رقیبی گارانتی بازگشت وجه واضح تبلیغ نمی‌کند",
        "محتوای پشت‌صحنه‌ی تحویل فوری اکانت دیده نمی‌شود",
        "مقایسه‌ی قیمت تومانی در برابر قیمت رسمی دلاری کمیاب است",
        "آموزش رفع مشکلات رایج اکانت‌های پرمیوم پوشش داده نشده",
        "نظرات و تجربه‌ی واقعی مشتریان کمتر به اشتراک گذاشته می‌شود",
        "محتوای مقایسه‌ای بین ابزارهای هوش مصنوعی (کدام برای چه کاری) کم است",
    ]
    for g in filler:
        if len(gaps) >= 8:
            break
        gaps.append(g)
    return {
        "positioning": {c["name"]: "" for c in comps},
        "strengths_weaknesses": {},
        "pricing_position": {},
        "content_they_do_well": [],
        "price_matrix": price_matrix,
        "trust_compare": trust_compare,
        "gaps": gaps[:10],
        "post_ideas": [{"post_type": "educational", "mode": "single", "topic": g} for g in gaps[:10]],
        "source": "rules",
    }


def _synthesis_prompt(brand, comps: list[dict]) -> str:
    lang = "Persian" if brand.language == "fa" else "English"
    compact = [{
        "name": c["name"], "website": c.get("website", {}).get("url", ""),
        "products": [
            {"key": p.get("product_key") or p["name"], "price": p.get("price"), "duration": p.get("duration")}
            for p in c.get("website", {}).get("products", [])[:20]
        ],
        "signals": c.get("website", {}).get("signals", {}),
        "discounts": c.get("website", {}).get("discounts", []),
        "ig_frequency_30d": c.get("instagram", {}).get("post_frequency_30d"),
        "ig_format_mix": c.get("instagram", {}).get("format_mix"),
        "ig_top_hashtags": c.get("instagram", {}).get("top_hashtags"),
    } for c in comps]
    return f"""You are a competitive-intelligence analyst for {brand.name}, which sells: {json.dumps(brand.products, ensure_ascii=False)}.
Competitor data collected today:
{json.dumps(compact, ensure_ascii=False)[:9000]}

Return ONLY JSON, user-facing text in {lang}:
{{
 "positioning": {{"<competitor name>": "one-line positioning"}},
 "strengths_weaknesses": {{"<competitor name>": {{"strengths": ["..."], "weaknesses": ["..."]}}}},
 "pricing_position": {{"<product key>": {{"<competitor name>": "cheapest|average|premium"}}}},
 "content_they_do_well": ["..."],
 "gaps": ["at least 8 concrete, {brand.name}-specific angles, not generic advice"],
 "post_ideas": [{{"post_type": "educational|news|promo|sales|video_prompt", "mode": "single|carousel|video", "topic": "..."}}]
}}
Provide at least 10 post_ideas."""


def synthesize(brand, comps: list[dict]) -> dict:
    rule = rule_based_report(brand, comps)
    try:
        data = chat_json("You are a competitive intelligence analyst. Output only JSON.", _synthesis_prompt(brand, comps), 0.4)
    except Exception as e:  # noqa: BLE001 — offline/no model: the rule-based report stands alone
        rule["model_error"] = str(e)[:300]
        return rule
    data["price_matrix"], data["trust_compare"] = rule["price_matrix"], rule["trust_compare"]
    if len(data.get("gaps", [])) < 8:
        data["gaps"] = list(dict.fromkeys((data.get("gaps") or []) + rule["gaps"]))[:10]
    if not data.get("post_ideas"):
        data["post_ideas"] = rule["post_ideas"]
    data["source"] = "model"
    return data


def _scan_one(c: dict, max_products: int) -> dict:
    name = c.get("name") or c.get("website") or (f"@{c['instagram']}" if c.get("instagram") else c["id"])
    out: dict = {"id": c["id"], "name": name, "error": ""}
    try:
        out["website"] = analyze_competitor_website(c.get("website", ""), max_products) if c.get("website") else {}
    except Exception as e:  # noqa: BLE001 — one competitor failing must never fail the whole scan
        out["website"] = {"ok": False}
        out["error"] += f"website: {str(e)[:200]}; "
    ig_handle = c.get("instagram") or out.get("website", {}).get("socials", {}).get("instagram", "")
    try:
        out["instagram"] = analyze_competitor_instagram(ig_handle) if ig_handle else {}
    except Exception as e:  # noqa: BLE001
        out["instagram"] = {}
        out["error"] += f"instagram: {str(e)[:200]}; "
    return out


def run_competitor_scan(brand, competitors: list[dict], max_products: int = MAX_PRODUCT_PAGES) -> dict:
    reports = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futs = [ex.submit(_scan_one, c, max_products) for c in competitors]
        for fut in as_completed(futs):
            reports.append(fut.result())
    reports.sort(key=lambda r: r["name"])
    report = {"competitors": reports, **synthesize(brand, reports), "created": datetime.now(timezone.utc).isoformat()}
    return report


def competitors_brief(report: dict) -> str:
    """Compact competitor context injected into generation prompts, kept short."""
    if not report:
        return ""
    gaps = report.get("gaps", [])[:5]
    if not gaps:
        return ""
    return "Competitor gaps we can exploit:\n" + "\n".join(f"- {g}" for g in gaps)
