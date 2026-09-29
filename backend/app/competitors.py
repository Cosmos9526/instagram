"""Competitor intelligence: normalises Brand.competitors, scans each competitor's website (sitemap,
product prices, trust signals) and Instagram page, then synthesizes one report with a price matrix and
evidence-backed content gaps. All network access goes through safe_fetch (SSRF-guarded) and runs in the
worker job, bounded by a per-competitor and a whole-scan time budget.
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
from urllib.parse import unquote, urlparse

from .business_analyzer import _meta, _text
from .config import settings
from .llm import chat_json

log = logging.getLogger("competitors")

MAX_PRODUCT_PAGES = 25
MAX_WORKERS = 2
MIN_SANE_PRICE = 10_000
MAX_SANE_PRICE = 500_000_000

# ---------- normalisation ----------

_COMPETITOR_FIELDS = (
    "name", "website", "instagram", "telegram", "notes",
    "instagram_status", "instagram_evidence", "telegram_status", "telegram_evidence",
)


def normalize_competitor(c) -> dict:
    if isinstance(c, str):
        c = {"instagram": c.strip().lstrip("@")}
    out = {"id": str(uuid.uuid4()), **{k: "" for k in _COMPETITOR_FIELDS}}
    out.update({k: c.get(k, out[k]) for k in _COMPETITOR_FIELDS})
    out["id"] = str(c.get("id") or out["id"])
    out["instagram"] = out["instagram"].strip().lstrip("@")
    out["telegram"] = out["telegram"].strip().lstrip("@")
    return out


def normalize_competitors(items: list) -> list[dict]:
    """Drops entries with nothing to scan (e.g. a blank legacy string)."""
    out = [normalize_competitor(c) for c in (items or []) if isinstance(c, (str, dict))]
    return [c for c in out if c["name"].strip() or c["website"].strip() or c["instagram"] or c["telegram"]]


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
AR_LETTERS = str.maketrans({"ي": "ی", "ك": "ک"})
ZWNJ = "‌"


def _norm_digits(s: str) -> str:
    return (s or "").translate(FA_DIGITS).translate(AR_DIGITS)


def _norm_text(s: str) -> str:
    """Normalises a product/brand name for matching: digits, ي/ك -> ی/ک, drops ZWNJ, collapses spaces."""
    s = _norm_digits(s or "").translate(AR_LETTERS).replace(ZWNJ, " ")
    return re.sub(r"\s+", " ", s).strip().lower()


RANGE_SEP = re.compile(r"\s*(?:–|—|-|تا)\s*")


def parse_price(text: str, currency: str = "") -> int | None:
    """'۱٬۲۵۰٬۰۰۰ تومان' / '125,000.00' / '1250000 ریال' -> integer Toman (no sanity check here)."""
    if not text:
        return None
    t = _norm_digits(text)
    cur = (currency or "").strip().upper()
    is_rial = "ریال" in t or "rial" in t.lower() or cur == "IRR"
    is_toman = "تومان" in t or "toman" in t.lower() or cur in ("IRT", "TOMAN")
    # a '.' or '٫' followed by 1-2 digits at the very end is a decimal fraction, not a thousands separator
    t = re.sub(r"[.٫]\d{1,2}\s*$", "", t.strip())
    digits = re.sub(r"[^\d]", "", t)
    if not digits:
        return None
    n = int(digits)
    return n // 10 if (is_rial and not is_toman) else n


def parse_price_range(text: str, currency: str = "") -> tuple[int | None, int | None]:
    """Returns (min, max); both equal for a single price."""
    t = _norm_digits(text or "")
    parts = [p for p in RANGE_SEP.split(t) if p.strip()]
    if len(parts) >= 2:
        lo, hi = parse_price(parts[0], currency), parse_price(parts[-1], currency)
        if lo is not None and hi is not None:
            return (lo, hi) if lo <= hi else (hi, lo)
    single = parse_price(text, currency)
    return single, single


def _sane(n: int | None) -> int | None:
    return n if n is not None and MIN_SANE_PRICE <= n <= MAX_SANE_PRICE else None


PRODUCT_ALIASES = {
    "chatgpt_plus": ["chatgpt plus", "چت جی پی تی پلاس", "چتجیپیتی پلاس", "gpt پلاس", "اکانت gpt پلاس", "chat gpt plus"],
    "chatgpt_pro": ["chatgpt pro", "چت جی پی تی پرو", "gpt پرو", "chat gpt pro"],
    "chatgpt_team": ["chatgpt team", "چت جی پی تی تیم"],
    "chatgpt": ["chatgpt", "چت جی پی تی", "چت جی بی تی", "gpt-4", "gpt4", "chat gpt", "gpt"],
    "gemini": ["gemini", "جمینای", "google gemini", "جمینی", "gemini advanced"],
    "claude": ["claude", "کلود", "anthropic claude", "claude pro"],
    "midjourney": ["midjourney", "میدجورنی", "میدجرنی"],
    "cursor": ["cursor", "کرسر"],
    "perplexity": ["perplexity", "پرپلکسیتی", "پرپلکسیتی پرو"],
    "grok": ["grok", "سوپر گروک", "گروک"],
    "copilot": ["copilot", "کوپایلوت", "کاپایلوت"],
    "canva": ["canva pro", "canva", "کانوا"],
    "capcut": ["capcut pro", "capcut", "کپ کات"],
    "spotify": ["spotify", "اسپاتیفای"],
    "youtube_premium": ["youtube premium", "یوتیوب پرمیوم"],
    "netflix": ["netflix", "نتفلیکس"],
    "adobe": ["adobe", "ادوبی"],
    "windows": ["windows license", "لایسنس ویندوز", "ویندوز اورجینال", "windows key"],
    "office": ["office license", "لایسنس آفیس", "مایکروسافت آفیس", "office 365", "microsoft office"],
}


def canonicalize_product(name: str) -> str | None:
    n = _norm_text(name)
    for key, aliases in PRODUCT_ALIASES.items():
        if any(_norm_text(a) in n for a in aliases):
            return key
    return None


DURATION_PATTERNS = [
    (r"(?:12|۱۲|دوازده)\s*(?:ماهه|ماه|month)|سالانه|یک\s*ساله|1\s*year", "12m"),
    (r"(?:6|۶|شش)\s*(?:ماهه|ماه|month)", "6m"),
    (r"(?:3|۳|سه)\s*(?:ماهه|ماه|month)", "3m"),
    (r"(?:1|۱|یک)\s*(?:ماهه|ماه|month)", "1m"),
]

DURATION_LABELS = {"1m": "یک ماهه", "3m": "سه ماهه", "6m": "شش ماهه", "12m": "یک ساله", "": ""}


def detect_duration(name: str) -> str:
    n = _norm_text(name)
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
                currency = str(offers.get("priceCurrency", ""))
                low, high = offers.get("lowPrice"), offers.get("highPrice")
                if low and high:
                    price, price_max = parse_price(str(low), currency), parse_price(str(high), currency)
                else:
                    price_raw = offers.get("price")
                    price = parse_price(str(price_raw), currency) if price_raw else None
                    price_max = price
                avail = str(offers.get("availability", ""))
                out.append({
                    "name": unescape(str(d["name"]))[:100], "price": price, "price_max": price_max,
                    "currency": currency, "in_stock": "outofstock" not in avail.lower() if avail else True,
                })
    return out


def _woo_currency(block: str) -> str:
    m = re.search(r'woocommerce-Price-currencySymbol[^>]*>([^<]*)<', block)
    sym = m.group(1) if m else block
    if "ریال" in sym or "rial" in sym.lower():
        return "IRR"
    if "تومان" in sym or "toman" in sym.lower():
        return "IRT"
    return ""


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
        currency = _woo_currency(block)
        dels = re.findall(r"(?is)<del[^>]*>.*?woocommerce-Price-amount[^>]*>\s*([^<]+)", block)
        inss = re.findall(r"(?is)<ins[^>]*>.*?woocommerce-Price-amount[^>]*>\s*([^<]+)", block)
        regular = parse_price(dels[0], currency) if dels else None
        sale = parse_price(inss[0], currency) if inss else None
        if regular is None and sale is None:
            amounts = re.findall(r"woocommerce-Price-amount[^>]*>\s*([^<]+)", block)
            if amounts:
                regular = parse_price(amounts[0], currency)
        out.append({
            "name": name, "price": sale if sale is not None else regular,
            "price_max": sale if sale is not None else regular,
            "regular_price": regular if sale is not None else None,
            "currency": currency, "in_stock": "outofstock" not in block.lower(),
        })
    return out


def _woo_variations(html: str) -> list[dict]:
    """WooCommerce variable products: form.variations_form[data-product_variations] holds one JSON
    entry per variation (attributes, display_price, display_regular_price, is_in_stock)."""
    out = []
    name_m = re.search(r"(?is)<h1[^>]*product_title[^>]*>(.*?)</h1>", html)
    base_name = _text(name_m.group(1)) if name_m else ""
    for m in re.finditer(r'data-product_variations=(["\'])(.*?)\1', html, re.S):
        try:
            variations = json.loads(unescape(m.group(2)))
        except ValueError:
            continue
        if not isinstance(variations, list):
            continue
        for v in variations:
            if not isinstance(v, dict):
                continue
            attrs = v.get("attributes") or {}
            attr_text = " ".join(unquote(str(x)).replace("-", " ") for x in attrs.values() if x)
            price = v.get("display_price")
            regular = v.get("display_regular_price")
            duration = detect_duration(attr_text) or detect_duration(base_name)
            out.append({
                "name": f"{base_name} {attr_text}".strip() or base_name,
                "price": int(price) if isinstance(price, (int, float)) else None,
                "price_max": int(price) if isinstance(price, (int, float)) else None,
                "regular_price": int(regular) if isinstance(regular, (int, float)) and regular != price else None,
                "currency": "", "in_stock": bool(v.get("is_in_stock", True)), "duration": duration,
            })
    return out


def extract_products(html: str) -> list[dict]:
    products = _woo_variations(html)
    if not products:
        products = _jsonld_products(html)
    if not products:
        products = _woo_products(html)
    if not products:
        og_price = _meta(html, "product:price:amount")
        if og_price:
            title = unescape((re.search(r"(?is)<title[^>]*>(.*?)</title>", html) or [None, ""])[1]).strip()
            currency = _meta(html, "product:price:currency")
            products = [{
                "name": title[:100], "price": parse_price(og_price, currency),
                "price_max": parse_price(og_price, currency), "currency": currency, "in_stock": True,
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


IG_EXCLUDE = {"accounts", "p", "reel", "reels", "tv", "stories", "explore", "share", "direct", "about", "developer", "legal"}
TG_EXCLUDE = {"joinchat", "share", "s"}


def _pick_handle(html: str, pattern: str, exclude: set[str]) -> str:
    """Prefers a handle linked from the header/footer; else the most frequent handle on the page."""
    header = re.search(r"(?is)<header[^>]*>.*?</header>", html)
    footer = re.search(r"(?is)<footer[^>]*>.*?</footer>", html)
    priority = (header.group(0) if header else "") + (footer.group(0) if footer else "")
    for source in (priority, html):
        handles = [h.lower() for h in re.findall(pattern, source) if h.lower() not in exclude]
        if handles:
            return Counter(handles).most_common(1)[0][0]
    return ""


def detect_socials(html: str) -> dict:
    ig = _pick_handle(html, r"instagram\.com/([\w.]{2,30})", IG_EXCLUDE)
    tg = _pick_handle(html, r"t\.me/([\w]{4,40})", TG_EXCLUDE)
    wa = re.search(r"wa\.me/(\d{8,15})|api\.whatsapp\.com/send\?phone=(\d{8,15})", html)
    return {"instagram": ig, "telegram": tg, "whatsapp": (wa.group(1) or wa.group(2)) if wa else ""}


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


def _apply_price_sanity(products: list[dict], errors: list[str], url: str) -> list[dict]:
    out = []
    for p in products:
        p = dict(p)
        for key in ("price", "price_max"):
            raw = p.get(key)
            if raw is not None and _sane(raw) is None:
                errors.append(f"{url}: unrealistic price {raw} for {p.get('name', '')!r}")
                p[key] = None
        out.append(p)
    return out


def analyze_competitor_website(url: str, max_products: int = MAX_PRODUCT_PAGES, deadline: float | None = None) -> dict:
    from . import safe_fetch

    if not url:
        return {}
    if not re.match(r"https?://", url):
        url = "https://" + url.strip().strip("/")
    if deadline is not None and time.time() > deadline:
        return {"url": url, "ok": False, "partial": True, "errors": ["scan time budget exhausted before this competitor"]}
    final, html = safe_fetch.text(url, timeout=10)
    if not html:
        return {"url": url, "ok": False, "errors": ["homepage unreachable"]}

    product_urls = discover_product_urls(final, max_products)
    products, errors, last_hit = [], [], {}
    consecutive_failures, partial = 0, False
    for purl in product_urls:
        if deadline is not None and time.time() > deadline:
            partial = True
            errors.append("stopped: time budget exhausted")
            break
        if consecutive_failures >= 3:
            partial = True
            errors.append(f"stopped after 3 consecutive failures on {urlparse(purl).netloc}")
            break
        host = urlparse(purl).netloc
        wait = 0.3 - (time.time() - last_hit.get(host, 0))
        if wait > 0:
            time.sleep(wait)
        last_hit[host] = time.time()
        try:
            _, phtml = safe_fetch.text(purl, timeout=10)
            if not phtml:
                consecutive_failures += 1
                continue
            consecutive_failures = 0
            for f in extract_products(phtml):
                f["url"] = purl
                f["product_key"] = canonicalize_product(f["name"])
                if not f.get("duration"):
                    f["duration"] = detect_duration(f["name"])
                products.append(f)
        except Exception as e:  # noqa: BLE001 — one bad product page must not fail the competitor
            consecutive_failures += 1
            errors.append(f"{purl}: {str(e)[:120]}")
    if not products:
        for f in extract_products(html):
            f["url"] = final
            f["product_key"] = canonicalize_product(f["name"])
            if not f.get("duration"):
                f["duration"] = detect_duration(f["name"])
            products.append(f)
    products = _apply_price_sanity(products, errors, final)
    return {
        "url": final, "ok": True, "partial": partial, "product_count": len(product_urls) or len(products),
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


# ---------- social handle status ----------


def _social_status(manual: str, site_handle: str, site_ok: bool, site_url: str) -> tuple[str, str, str]:
    """(handle, status, evidence). Never derives a handle from the domain name."""
    if manual:
        return manual, "manual", ""
    if site_handle:
        return site_handle, "verified", site_url
    return "", ("not_found" if site_ok else "inaccessible"), ""


# ---------- synthesis ----------

GENERIC_SUGGESTIONS = [
    "محتوای آموزشی درباره‌ی نحوه‌ی استفاده از اکانت‌های هوش مصنوعی",
    "مقایسه‌ی شفاف پلن‌های ChatGPT Plus در برابر Pro",
    "گارانتی بازگشت وجه به‌صورت شفاف",
    "محتوای پشت‌صحنه‌ی تحویل فوری اکانت",
    "مقایسه‌ی قیمت تومانی در برابر قیمت رسمی دلاری",
    "آموزش رفع مشکلات رایج اکانت‌های پرمیوم",
    "نظرات و تجربه‌ی واقعی مشتریان",
    "مقایسه‌ی ابزارهای هوش مصنوعی برای کاربردهای مختلف",
]


def _price_matrix(comps: list[dict]) -> list[dict]:
    matrix: dict[tuple[str, str], dict[str, int]] = {}
    for c in comps:
        for p in c.get("website", {}).get("products", []):
            key, price, dur = p.get("product_key"), p.get("price"), p.get("duration") or ""
            if not key or not price:
                continue
            row = matrix.setdefault((key, dur), {})
            row[c["name"]] = min(row.get(c["name"], price), price)
    return [
        {"product": k, "duration": d, "prices": v, "cheapest": min(v, key=v.get) if v else None}
        for (k, d), v in sorted(matrix.items())
    ]


def rule_based_report(brand, comps: list[dict]) -> dict:
    price_matrix = _price_matrix(comps)
    trust_compare = []
    gaps = []
    for c in comps:
        website = c.get("website") or {}
        if not website.get("ok"):
            trust_compare.append({"name": c["name"], "reachable": False})
            continue
        signals = website.get("signals", {})
        trust_compare.append({"name": c["name"], "reachable": True, **signals})
    for row in price_matrix:
        names = list(row["prices"])
        label = row["product"] + (f" ({DURATION_LABELS.get(row['duration'], row['duration'])})" if row["duration"] else "")
        prices = list(row["prices"].values())
        gaps.append({
            "text": f"روی {label}، رقبا ({', '.join(names)}) قیمتی بین {min(prices)} تا {max(prices)} تومان دارند",
            "evidence": names,
        })
    return {
        "positioning": {c["name"]: "" for c in comps},
        "strengths_weaknesses": {},
        "pricing_position": {},
        "content_they_do_well": [],
        "price_matrix": price_matrix,
        "trust_compare": trust_compare,
        "gaps": gaps,
        "suggestions": GENERIC_SUGGESTIONS,
        "post_ideas": (
            [{"post_type": "educational", "mode": "single", "topic": g["text"]} for g in gaps[:6]]
            + [{"post_type": "educational", "mode": "single", "topic": s} for s in GENERIC_SUGGESTIONS[:4]]
        ),
        "source": "rules",
    }


def _synthesis_prompt(brand, comps: list[dict]) -> str:
    lang = "Persian" if brand.language == "fa" else "English"
    compact = [{
        "name": c["name"], "website": c.get("website", {}).get("url", ""),
        "reachable": bool(c.get("website", {}).get("ok")),
        "products": [
            {"key": p.get("product_key") or p["name"], "price": p.get("price"), "duration": p.get("duration")}
            for p in c.get("website", {}).get("products", [])[:20]
        ],
        "signals": c.get("website", {}).get("signals") if c.get("website", {}).get("ok") else None,
        "discounts": c.get("website", {}).get("discounts", []),
        "ig_frequency_30d": c.get("instagram", {}).get("post_frequency_30d"),
        "ig_format_mix": c.get("instagram", {}).get("format_mix"),
        "ig_top_hashtags": c.get("instagram", {}).get("top_hashtags"),
    } for c in comps]
    return f"""You are a competitive-intelligence analyst for {brand.name}, which sells: {json.dumps(brand.products, ensure_ascii=False)}.
Competitor data collected today (a "signals" of null means that site could not be fetched — treat it as
UNKNOWN, never as a negative finding):
{json.dumps(compact, ensure_ascii=False)[:9000]}

Return ONLY JSON, user-facing text in {lang}:
{{
 "positioning": {{"<competitor name>": "one-line positioning"}},
 "strengths_weaknesses": {{"<competitor name>": {{"strengths": ["..."], "weaknesses": ["..."]}}}},
 "pricing_position": {{"<product key>": {{"<competitor name>": "cheapest|average|premium"}}}},
 "content_they_do_well": ["..."],
 "gaps": [{{"text": "a specific claim about a real gap", "evidence": ["competitor name(s) the data above supports this with"]}}],
 "suggestions": ["generic content angles, not necessarily backed by the data above"],
 "post_ideas": [{{"post_type": "educational|news|promo|sales|video_prompt", "mode": "single|carousel|video", "topic": "..."}}]
}}
Every "gaps" entry MUST cite at least one competitor name in "evidence" that the data above actually supports;
drop any claim you cannot back with the data. Provide at least 10 post_ideas."""


def synthesize(brand, comps: list[dict]) -> dict:
    rule = rule_based_report(brand, comps)
    try:
        data = chat_json("You are a competitive intelligence analyst. Output only JSON.", _synthesis_prompt(brand, comps), 0.4)
    except Exception as e:  # noqa: BLE001 — offline/no model: the rule-based report stands alone
        rule["model_error"] = str(e)[:300]
        return rule
    data["price_matrix"], data["trust_compare"] = rule["price_matrix"], rule["trust_compare"]
    model_gaps = [g for g in (data.get("gaps") or []) if isinstance(g, dict) and g.get("text") and g.get("evidence")]
    data["gaps"] = model_gaps or rule["gaps"]
    data["suggestions"] = list(dict.fromkeys((data.get("suggestions") or []) + rule["suggestions"]))[:10]
    if not data.get("post_ideas"):
        data["post_ideas"] = rule["post_ideas"]
    data["source"] = "model"
    return data


def _resolve_unmatched_products(comps: list[dict]) -> None:
    """One LLM call per scan (not per competitor) to map unmatched product names to an existing key."""
    unmatched: dict[str, list[dict]] = {}
    for c in comps:
        for p in c.get("website", {}).get("products", []):
            if not p.get("product_key") and p.get("name"):
                unmatched.setdefault(p["name"], []).append(p)
    if not unmatched:
        return
    names = list(unmatched.keys())[:60]
    prompt = (
        f"Existing product keys: {', '.join(PRODUCT_ALIASES)}.\n"
        "For each product name below, return the closest matching key, or null if none fits well.\n"
        f"Names: {json.dumps(names, ensure_ascii=False)}\n"
        'Return ONLY JSON: {"matches": {"<name>": "<key or null>", ...}}'
    )
    try:
        data = chat_json("You classify e-commerce product names into a fixed catalog. Output only JSON.", prompt, 0.1)
    except Exception as e:  # noqa: BLE001 — offline/no model: unmatched names stay uncategorised
        log.info("unmatched product resolution skipped: %s", e)
        return
    for name, key in (data.get("matches") or {}).items():
        if key in PRODUCT_ALIASES:
            for p in unmatched.get(name, []):
                p["product_key"] = key


def _scan_one(c: dict, max_products: int, deadline: float | None) -> dict:
    name = c.get("name") or c.get("website") or (f"@{c['instagram']}" if c.get("instagram") else c["id"])
    out: dict = {"id": c["id"], "name": name, "error": ""}
    try:
        out["website"] = analyze_competitor_website(c.get("website", ""), max_products, deadline) if c.get("website") else {}
    except Exception as e:  # noqa: BLE001 — one competitor failing must never fail the whole scan
        out["website"] = {"ok": False}
        out["error"] += f"website: {str(e)[:200]}; "
    website = out.get("website") or {}
    ig_handle, ig_status, ig_evidence = _social_status(
        c.get("instagram", ""), website.get("socials", {}).get("instagram", ""), bool(website.get("ok")), website.get("url", "")
    )
    tg_handle, tg_status, tg_evidence = _social_status(
        c.get("telegram", ""), website.get("socials", {}).get("telegram", ""), bool(website.get("ok")), website.get("url", "")
    )
    out["instagram_status"], out["instagram_evidence"] = ig_status, ig_evidence
    out["telegram_status"], out["telegram_evidence"] = tg_status, tg_evidence
    try:
        out["instagram"] = analyze_competitor_instagram(ig_handle) if ig_handle else {}
    except Exception as e:  # noqa: BLE001
        out["instagram"] = {}
        out["error"] += f"instagram: {str(e)[:200]}; "
    return out


def run_competitor_scan(brand, competitors: list[dict], max_products: int = MAX_PRODUCT_PAGES,
                         budget_seconds: int | None = None, on_progress=None) -> dict:
    budget_seconds = budget_seconds if budget_seconds is not None else settings.competitor_scan_budget_seconds
    global_deadline = time.time() + budget_seconds
    reports, done = [], 0
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futs = {
            ex.submit(_scan_one, c, max_products, min(global_deadline, time.time() + settings.competitor_site_budget_seconds)): c
            for c in competitors
        }
        for fut in as_completed(futs):
            reports.append(fut.result())
            done += 1
            if on_progress:
                on_progress(done, len(competitors))
    reports.sort(key=lambda r: r["name"])
    _resolve_unmatched_products(reports)
    report = {
        "competitors": reports, "progress": {"done": len(reports), "total": len(competitors)},
        "partial": time.time() > global_deadline or any((r.get("website") or {}).get("partial") for r in reports),
        **synthesize(brand, reports), "created": datetime.now(timezone.utc).isoformat(),
    }
    return report


def write_back_handles(brand, report: dict) -> None:
    """After a scan, save a verified handle found on the competitor's own site when the field was empty."""
    comps = normalize_competitors(brand.competitors)
    by_id = {c["id"]: c for c in comps}
    changed = False
    for r in report.get("competitors", []):
        c = by_id.get(r["id"])
        if not c:
            continue
        if not c["instagram"] and r.get("instagram_status") == "verified":
            handle = (r.get("website") or {}).get("socials", {}).get("instagram", "")
            if handle:
                c["instagram"], c["instagram_status"], c["instagram_evidence"] = handle, "verified", r.get("instagram_evidence", "")
                changed = True
        if not c["telegram"] and r.get("telegram_status") == "verified":
            handle = (r.get("website") or {}).get("socials", {}).get("telegram", "")
            if handle:
                c["telegram"], c["telegram_status"], c["telegram_evidence"] = handle, "verified", r.get("telegram_evidence", "")
                changed = True
    if changed:
        brand.competitors = comps


def competitors_brief(report: dict) -> str:
    """Compact competitor context injected into generation prompts, kept short."""
    if not report:
        return ""
    gaps = report.get("gaps", [])[:5]
    if not gaps:
        return ""
    lines = [f"- {g['text'] if isinstance(g, dict) else g}" for g in gaps]
    return "Competitor gaps we can exploit:\n" + "\n".join(lines)
