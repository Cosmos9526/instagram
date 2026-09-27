"""Quick business analysis from just a website and/or an Instagram page.

Reads the site (title, description, headings, products from JSON-LD / shop markup, prices, brand colors) and
the Instagram profile (name, bio, followers, recent posts through search), then proposes a complete project:
name, industry, products, audience, tone, CTA, colors, hashtags, a weekly posting plan and a first week of
post ideas. A text model refines the proposal when one is available; otherwise it is built by rules."""

import json
import logging
import re
from collections import Counter
from html import unescape
from urllib.parse import urljoin, urlparse

import httpx

from .llm import LLMError, chat_json

log = logging.getLogger("business_analyzer")
UA = {"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", "Accept-Language": "fa,en;q=0.8"}

# industry label (same options as the app) -> words that point to it
INDUSTRIES: dict[str, list[str]] = {
    "هوش مصنوعی": ["هوش مصنوعی", "chatgpt", "چت جی پی تی", "gpt", "midjourney", "gemini", "claude", " ai "],
    "زیبایی و آرایشی": ["کلینیک زیبایی", "پوست", "بوتاکس", "فیلر", "لیزر", "آرایش", "مژه", "ناخن", "سالن زیبایی",
                        "کاشت مو", "beauty", "skin", "cosmetic", "lash"],
    "سلامت و پزشکی": ["پزشک", "دکتر", "درمان", "کلینیک", "دندان", "بیمار", "clinic", "dental", "health"],
    "کافه و رستوران": ["کافه", "رستوران", "منو", "قهوه", "پیتزا", "غذا", "cafe", "coffee", "restaurant"],
    "مد و پوشاک": ["پوشاک", "لباس", "مانتو", "کفش", "کیف", "شلوار", "fashion", "clothing"],
    "آموزش و دوره": ["دوره", "آموزش", "کلاس", "آکادمی", "مدرس", "وبینار", "course", "academy"],
    "املاک": ["املاک", "آپارتمان", "ملک", "اجاره", "رهن", "real estate"],
    "فناوری و نرم‌افزار": ["نرم‌افزار", "نرم افزار", "اپلیکیشن", "هاست", "سرور", "طراحی سایت", "software", "saas"],
    "گردشگری": ["تور", "سفر", "هتل", "بلیط", "ویزا", "travel", "tour"],
    "ورزش و تناسب اندام": ["باشگاه", "بدنسازی", "فیتنس", "تناسب اندام", "مربی", "gym", "fitness"],
    "خدمات مالی": ["بیمه", "سرمایه‌گذاری", "حسابداری", "وام", "ارز دیجیتال", "finance"],
    "هنر و صنایع دستی": ["صنایع دستی", "نقاشی", "گالری", "سفال", "handmade", "art"],
    "خودرو": ["خودرو", "ماشین", "لوازم یدکی", "کارواش", "car ", "auto"],
    "خدمات حقوقی": ["وکیل", "حقوقی", "دادگاه", "مشاوره حقوقی", "lawyer"],
    "مواد غذایی": ["شیرینی", "خشکبار", "عسل", "زعفران", "ادویه", "food"],
    "فروشگاه آنلاین": ["فروشگاه", "خرید", "سبد خرید", "ارسال رایگان", "تخفیف", "shop", "store"],
}
PROFILE: dict[str, tuple[list[str], list[str], str]] = {  # audience, tone, cta
    "هوش مصنوعی": (["برنامه‌نویس‌ها", "دانشجوها", "صاحبان کسب‌وکار"], ["تخصصی", "صمیمی"], "برای سفارش دایرکت بدید"),
    "زیبایی و آرایشی": (["خانم‌ها", "۲۵ تا ۳۴ ساله‌ها"], ["صمیمی", "لوکس"], "برای مشاوره‌ی رایگان پیام بدید"),
    "سلامت و پزشکی": (["۲۵ تا ۳۴ ساله‌ها", "۳۵ تا ۴۴ ساله‌ها"], ["تخصصی", "آرام"], "برای مشاوره‌ی رایگان پیام بدید"),
    "کافه و رستوران": (["جوان‌ها (۱۸ تا ۲۴)", "۲۵ تا ۳۴ ساله‌ها"], ["صمیمی", "پرانرژی"], "همین حالا تماس بگیرید"),
    "آموزش و دوره": (["دانشجوها", "کارمندها"], ["آموزشی", "الهام‌بخش"], "لینک خرید در بیو"),
}
FORBIDDEN = {"سلامت و پزشکی": ["سیاست", "مذهب", "ادعای پزشکی"], "زیبایی و آرایشی": ["سیاست", "مذهب", "ادعای پزشکی"]}
# weekly plans (Python weekday keys, 5 = Saturday): selling businesses get more promo/sales, services more education
PLANS = {
    "sell": {"5": ["educational:carousel"], "6": ["promo"], "0": ["sales"], "1": ["educational"],
             "2": ["promo:carousel"], "3": ["video_prompt"], "4": []},
    "service": {"5": ["educational:carousel"], "6": ["news"], "0": ["promo"], "1": ["educational"],
                "2": ["sales"], "3": ["video_prompt"], "4": []},
}
DAYS_FA = {"5": "شنبه", "6": "یکشنبه", "0": "دوشنبه", "1": "سه‌شنبه", "2": "چهارشنبه", "3": "پنجشنبه", "4": "جمعه"}
TYPE_FA = {"educational": "آموزشی", "news": "خبری", "promo": "تبلیغاتی", "sales": "فروش", "video_prompt": "ویدیو"}


def _text(html: str) -> str:
    html = re.sub(r"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>", " ", html)
    return re.sub(r"\s+", " ", unescape(re.sub(r"(?s)<[^>]+>", " ", html))).strip()


def _meta(html: str, key: str) -> str:
    for pat in (rf'<meta[^>]+(?:name|property)=["\']{key}["\'][^>]*content=["\']([^"\']*)',
                rf'<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:name|property)=["\']{key}["\']'):
        m = re.search(pat, html, re.I)
        if m:
            return unescape(m.group(1)).strip()
    return ""


def _fetch(url: str, timeout: float = 15) -> tuple[str, str]:
    try:
        r = httpx.get(url, headers=UA, timeout=timeout, follow_redirects=True)
        if r.status_code < 400:
            return str(r.url), r.text[:1_500_000]
    except Exception as e:  # noqa: BLE001
        log.info("fetch %s failed: %s", url, e)
    return url, ""


def _is_neutral(hexc: str) -> bool:
    h = hexc.lower()
    if len(h) == 4:
        h = "#" + "".join(c * 2 for c in h[1:])
    r, g, b = (int(h[i:i + 2], 16) for i in (1, 3, 5))
    return max(r, g, b) - min(r, g, b) < 28  # greys, black, white


def _products_jsonld(html: str) -> list[dict]:
    out = []
    for block in re.findall(r'(?is)<script[^>]+application/ld\+json[^>]*>(.*?)</script>', html):
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
                price = str(offers.get("price") or offers.get("lowPrice") or "")
                out.append({"name": unescape(str(d["name"]))[:80], "desc": unescape(str(d.get("description") or ""))[:160],
                            "price": price, "url": d.get("url", "")})
    return out


def _products_markup(html: str, base: str) -> list[dict]:
    out = []
    for pat in (r'(?is)<h2[^>]*woocommerce-loop-product__title[^>]*>(.*?)</h2>',
                r'(?is)<(?:h2|h3|a|div|span)[^>]*class=["\'][^"\']*product[-_]?(?:title|name)[^"\']*["\'][^>]*>(.*?)</(?:h2|h3|a|div|span)>'):
        for m in re.findall(pat, html):
            name = _text(m)
            if 2 < len(name) < 90:
                out.append({"name": name, "desc": "", "price": "", "url": base})
    return out


def analyze_website(url: str) -> dict:
    if not url:
        return {}
    if not re.match(r"https?://", url):
        url = "https://" + url.strip().strip("/")
    final, html = _fetch(url)
    if not html:
        return {"url": url, "ok": False}
    host = urlparse(final).netloc
    title = unescape((re.search(r"(?is)<title[^>]*>(.*?)</title>", html) or [None, ""])[1]).strip()
    site_name = _meta(html, "og:site_name") or (re.split(r"\s[|\-–—]\s", title)[0].strip() if title else "")
    desc = _meta(html, "description") or _meta(html, "og:description")
    heads = [_text(h) for h in re.findall(r"(?is)<h[1-3][^>]*>(.*?)</h[1-3]>", html)]
    heads = [h for h in dict.fromkeys(heads) if 3 < len(h) < 90][:20]
    menu = [_text(a) for a in re.findall(r"(?is)<a[^>]*>(.*?)</a>", html)]
    menu = [m for m in dict.fromkeys(menu) if 2 < len(m) < 30][:40]

    products = _products_jsonld(html) + _products_markup(html, final)
    # follow one shop/category/service page for more products
    if len(products) < 4:
        for href in re.findall(r'href=["\']([^"\'#]+)["\']', html):
            full = urljoin(final, href)
            if urlparse(full).netloc == host and re.search(r"/(shop|store|product|products|services|category|فروشگاه|خدمات)", full, re.I):
                _, page = _fetch(full, 12)
                products += _products_jsonld(page) + _products_markup(page, full)
                break
    seen, uniq = set(), []
    for p in products:
        if p["name"] not in seen:
            seen.add(p["name"])
            uniq.append(p)

    # colors: theme-color first, then the most used saturated hex colors in inline and linked CSS
    css = html
    for href in re.findall(r'<link[^>]+rel=["\']stylesheet["\'][^>]*href=["\']([^"\']+)', html, re.I)[:3]:
        css += _fetch(urljoin(final, href), 10)[1][:400_000]
    counts = Counter(c.lower() for c in re.findall(r"#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b", css))
    colors = [c for c, _ in counts.most_common(40) if not _is_neutral(c)]
    theme = _meta(html, "theme-color")
    if theme and re.match(r"#[0-9a-fA-F]{6}$", theme) and not _is_neutral(theme):
        colors = [theme.lower()] + [c for c in colors if c != theme.lower()]
    colors = [("#" + "".join(ch * 2 for ch in c[1:])) if len(c) == 4 else c for c in colors]
    instagram = re.search(r"instagram\.com/([\w.]{2,30})", html)
    telegram = re.search(r"t\.me/([\w]{4,40})", html)
    phone = re.search(r"(?:\+98|0)9\d{9}|0\d{2,3}[- ]?\d{7,8}", _text(html))
    return {
        "url": final, "ok": True, "title": title, "name": site_name[:60], "description": desc[:400],
        "headings": heads, "menu": menu, "products": uniq[:12], "colors": list(dict.fromkeys(colors))[:4],
        "instagram": instagram.group(1) if instagram and instagram.group(1) not in ("p", "reel", "explore") else "",
        "telegram": telegram.group(1) if telegram else "", "phone": phone.group(0) if phone else "",
        "text": _text(html)[:4000],
    }


def analyze_instagram(username: str) -> dict:
    u = re.sub(r"^(https?://)?(www\.)?instagram\.com/", "", (username or "").strip()).strip("/@ ").split("/")[0]
    if not u:
        return {}
    out: dict = {"username": u, "posts": []}
    # 1) public profile page meta ("12K Followers, 30 Following, 400 Posts - See Instagram photos ... from Name (@u)")
    _, html = _fetch(f"https://www.instagram.com/{u}/", 15)
    desc = _meta(html, "og:description") or _meta(html, "description")
    if desc:
        out["meta"] = desc
        m = re.search(r"([\d.,]+[KkMm]?)\s+Followers", desc)
        out["followers"] = m.group(1) if m else ""
        m = re.search(r"from (.+?) \(@", desc)
        out["name"] = m.group(1).strip() if m else ""
        m = re.search(r'Instagram photos and videos from .*?\)\s*[:\-–]?\s*"?(.*)', desc)
        out["bio"] = (m.group(1) if m else "").strip(' "')
    # 2) login-less API (works from clean IPs)
    try:
        from . import instagram_free

        out["posts"] = instagram_free.profile_posts(u)[:12]
    except Exception:  # noqa: BLE001
        pass
    # 3) search engine: bio snippet and recent posts of this account
    try:
        from ddgs import DDGS

        from .search_sources import parse_instagram_result

        for r in DDGS().text(f"instagram.com/{u}", max_results=20):
            href = r.get("href", "")
            if re.match(rf"https://(www\.)?instagram\.com/{re.escape(u)}/?$", href, re.I):
                out.setdefault("bio", r.get("body", ""))
                if not out.get("name"):
                    out["name"] = re.split(r"\s*\(@|\s*•", r.get("title", ""))[0].strip()
                if not out.get("followers"):
                    m = re.search(r"([\d.,]+[KkMm]?)\s+(?:Followers|دنبال)", r.get("body", ""))
                    out["followers"] = m.group(1) if m else ""
            p = parse_instagram_result(r)
            if p and len(out["posts"]) < 12 and (p["channel"].lower() == u.lower() or u.lower() in href.lower()):
                out["posts"].append(p)
    except Exception as e:  # noqa: BLE001
        log.info("instagram search for %s failed: %s", u, e)
    out["ok"] = bool(out.get("bio") or out.get("name") or out["posts"])
    return out


def _industry(text: str) -> str:
    t = f" {text.lower()} "
    scores = {k: sum(t.count(w) for w in words) for k, words in INDUSTRIES.items()}
    best = max(scores, key=scores.get)
    return best if scores[best] else "فروشگاه آنلاین"


def _hashtags(name: str, industry: str, products: list[dict]) -> list[str]:
    tags = [industry] + [p["name"] for p in products[:4]] + [name]
    out = []
    for t in tags:
        t = re.sub(r"[^\w‌ ]", "", t or "").strip().replace(" ", "_")
        if 2 < len(t) < 26 and t.count("_") < 3:
            out.append("#" + t)
    return list(dict.fromkeys(out))[:8]


def _ideas(profile: dict) -> list[dict]:
    """One concrete idea per plan day for the first week."""
    prods = [p["name"] for p in profile["products"]] or [profile["industry"]]
    name, ind = profile["name"] or "ما", profile["industry"]
    pat = {
        "educational": ["۵ نکته که قبل از انتخاب {p} باید بدانید", "اشتباه‌های رایج درباره‌ی {p}", "{p} چطور کار می‌کند؟ ساده و کوتاه"],
        "news": ["تازه‌ترین خبرها و ترندهای {ind} این هفته"],
        "promo": ["چرا {p} را از {n} بگیرید؟", "پشت صحنه‌ی {n}: {p} چطور آماده می‌شود"],
        "sales": ["پیشنهاد ویژه‌ی این هفته روی {p}", "{p} با شرایط ویژه، فقط تا آخر هفته"],
        "video_prompt": ["ریلز ۲۰ ثانیه‌ای: قبل و بعد از {p}", "ریلز: سه سؤال پرتکرار مشتری‌ها درباره‌ی {p}"],
    }
    out, i = [], 0
    for day in ("5", "6", "0", "1", "2", "3", "4"):
        for entry in profile["weekly_plan"].get(day, []):
            kind, _, mode = entry.partition(":")
            options = pat.get(kind, ["{p}"])
            idea = options[i % len(options)].format(p=prods[i % len(prods)], n=name, ind=ind)
            out.append({"day": DAYS_FA[day], "type": kind, "type_fa": TYPE_FA.get(kind, kind),
                        "mode": mode or ("video" if kind == "video_prompt" else "single"), "idea": idea})
            i += 1
    return out


def _refine_with_model(profile: dict, site: dict, ig: dict) -> dict:
    facts = {
        "website": {k: site.get(k) for k in ("title", "description", "headings", "menu", "products")} if site else {},
        "instagram": {k: ig.get(k) for k in ("name", "bio", "followers")} | {"captions": [p["title"] for p in ig.get("posts", [])[:8]]}
        if ig else {},
        "draft": {k: profile[k] for k in ("name", "industry", "products", "audience", "tone", "cta")},
    }
    system = ("You are a Persian social-media strategist. From the facts about a business, return JSON with keys: "
              "name, industry (one of: " + "، ".join(INDUSTRIES) + "), description (2 Persian sentences), "
              "products (list of {name, desc} max 8, real products/services only), audience (Persian, short), "
              "tone (Persian, short), cta (Persian), strengths (3 Persian bullet strings), "
              "ideas (7 Persian post ideas, specific to the products). No invented facts.")
    data = chat_json(system, json.dumps(facts, ensure_ascii=False)[:9000], temperature=0.4)
    for k in ("name", "description", "audience", "tone", "cta"):
        if isinstance(data.get(k), str) and data[k].strip():
            profile[k] = data[k].strip()
    if data.get("industry") in INDUSTRIES:
        profile["industry"] = data["industry"]
    if isinstance(data.get("products"), list) and data["products"]:
        profile["products"] = [{"name": str(p.get("name", ""))[:80], "desc": str(p.get("desc", ""))[:160]}
                               for p in data["products"] if isinstance(p, dict) and p.get("name")][:8]
    if isinstance(data.get("strengths"), list):
        profile["strengths"] = [str(s) for s in data["strengths"]][:5]
    profile["source"] = "model"
    ideas = [str(s) for s in data.get("ideas") or [] if s]
    return {"ideas": ideas}


def analyze_business(website: str = "", instagram: str = "") -> dict:
    site = analyze_website(website) if website else {}
    ig_user = instagram or (site.get("instagram") if site else "")
    ig = analyze_instagram(ig_user) if ig_user else {}

    corpus = " ".join([site.get("title", ""), site.get("description", ""), " ".join(site.get("headings", [])),
                       " ".join(site.get("menu", [])), site.get("text", "")[:2000], ig.get("bio", ""),
                       " ".join(p["title"] for p in ig.get("posts", []))])
    industry = _industry(corpus)
    products = [{"name": p["name"], "desc": p.get("desc", "")} for p in site.get("products", [])]
    if not products:  # services: take short headings that are not generic
        generic = re.compile(r"درباره|تماس|وبلاگ|مقالات|سوالات|ورود|سبد|صفحه|about|contact|blog|login|home", re.I)
        products = [{"name": h, "desc": ""} for h in site.get("headings", []) if len(h) < 45 and not generic.search(h)][:5]
    name = (site.get("name") or ig.get("name") or ig_user or "").strip()
    audience, tone, cta = PROFILE.get(industry, (["۲۵ تا ۳۴ ساله‌ها", "صاحبان کسب‌وکار"], ["صمیمی"], "برای سفارش دایرکت بدید"))
    colors = site.get("colors", [])
    selling = bool(site.get("products")) or industry in ("فروشگاه آنلاین", "مد و پوشاک", "مواد غذایی", "هوش مصنوعی")
    profile = {
        "name": name, "industry": industry,
        "description": site.get("description") or ig.get("bio", ""),
        "website": site.get("url", website), "instagram": ig_user, "telegram": site.get("telegram", ""),
        "products": products[:8], "audience": "، ".join(audience), "tone": "، ".join(tone), "cta": cta,
        "forbidden_topics": FORBIDDEN.get(industry, ["سیاست", "مذهب"]),
        "colors": {"primary": colors[0], "secondary": colors[1] if len(colors) > 1 else "#FFB23F",
                   "bg": "#FFFFFF", "text": "#0B1B22"} if colors else {},
        "weekly_plan": PLANS["sell" if selling else "service"], "strengths": [], "source": "rules",
    }
    model_ideas: list[str] = []
    try:
        if not (site.get("ok") or ig.get("ok")):
            raise LLMError("nothing found to analyse")
        model_ideas = _refine_with_model(profile, site, ig)["ideas"]
    except (LLMError, Exception) as e:  # noqa: BLE001
        log.info("model refinement skipped: %s", e)
    profile["hashtags"] = _hashtags(profile["name"], profile["industry"], profile["products"])
    ideas = _ideas(profile)
    for i, text in enumerate(model_ideas[:len(ideas)]):
        ideas[i]["idea"] = text
    evidence = []
    if site.get("ok"):
        evidence.append(f"سایت خوانده شد: {len(site.get('products', []))} محصول، {len(site.get('headings', []))} سرتیتر")
    elif website:
        evidence.append("سایت در دسترس نبود")
    if ig.get("ok"):
        f = f"، {ig['followers']} دنبال‌کننده" if ig.get("followers") else ""
        evidence.append(f"اینستاگرام @{ig['username']}{f}، {len(ig.get('posts', []))} پست پیدا شد")
    elif ig_user:
        evidence.append(f"اطلاعات کمی از اینستاگرام @{ig_user} در دسترس بود")
    top = sorted(ig.get("posts", []), key=lambda p: p.get("engagement", 0), reverse=True)[:5]
    return {"profile": profile, "plan": ideas, "evidence": evidence, "top_posts": top,
            "found": {"website": bool(site.get("ok")), "instagram": bool(ig.get("ok"))}}

