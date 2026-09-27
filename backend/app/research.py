"""Market research for a project.

1. Web research (Gemini + Google Search grounding): facts about the business/products online,
   competitors, what the audience talks about, current trends, keywords and hashtags.
2. Social listening: most-viewed recent videos for the top keywords (YouTube Data API) and,
   when an Apify token is set, top Instagram posts for the top hashtags.
3. Style analysis: what formats/styles the top videos use, mapped to our video-style catalog.

Every source is optional; the report says which ones ran so the app can show it honestly.
"""

import json
import logging
from datetime import datetime, timedelta, timezone

import httpx

from .config import settings
from .llm import chat_json, extract_json
from .models import Brand
from .prompts import brand_block
from .video_styles import VIDEO_STYLES

log = logging.getLogger("research")


def _web_prompt(b: Brand, focus: str) -> str:
    lang = "Persian" if b.language == "fa" else "English"
    return f"""You are a market researcher and social-media strategist. Use Google Search to research
this business and its market as of today ({datetime.now(timezone.utc).date()}).

<brand>
{brand_block(b)}
website: {b.website or 'unknown'}
instagram: {b.instagram or 'unknown'}
</brand>
<focus>{focus or 'the business as a whole and its main products'}</focus>

Find:
1. What is said online about this business and its products (if it has any web presence). Never invent
   facts: if you find nothing, say so.
2. The main competitors or comparable brands and what they post about.
3. What the target audience currently searches for and talks about in this industry, especially on
   Instagram, Telegram and YouTube in the audience's country/language.
4. Trends from roughly the last 7 days that this brand could credibly use (skip politics, religion,
   tragedies and the brand's forbidden topics).
5. High-intent keywords and hashtags in {lang} (and English where commonly used).

Return ONLY a JSON object (no markdown) with this shape. User-facing text in {lang}:
{{
  "summary": "4-6 sentences: the market picture and the biggest content opportunity",
  "business_facts": ["facts found online about this business/products, each with where it was found"],
  "competitors": [{{"name": "...", "what_they_post": "...", "gap_we_can_fill": "..."}}],
  "audience_interests": ["..."],
  "trends": [{{"title": "...", "why_now": "...", "angle_for_brand": "...", "post_type": "educational|news|promo|sales|video_prompt"}}],
  "keywords": ["10-20 search keywords, most valuable first"],
  "hashtags": ["15-30 hashtags without #"],
  "content_ideas": [{{"title": "...", "post_type": "...", "format": "single|carousel|video"}}]
}}"""


def web_research(b: Brand, focus: str) -> tuple[dict, list[dict], str]:
    """Returns (report, sources, mode)."""
    prompt = _web_prompt(b, focus)
    if settings.research_provider == "fake" or settings.llm_provider == "fake":
        from .fake_llm import fake_research

        return fake_research(), [{"title": "example.com", "url": "https://example.com"}], "fake"
    if settings.research_provider == "gemini":
        url = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{settings.gemini_research_model}:generateContent"
        )
        resp = httpx.post(
            url,
            headers={"x-goog-api-key": settings.llm_api_key},
            json={"contents": [{"role": "user", "parts": [{"text": prompt}]}], "tools": [{"google_search": {}}]},
            timeout=180,
        )
        if resp.status_code >= 400:
            raise RuntimeError(f"Gemini research HTTP {resp.status_code}: {resp.text[:300]}")
        cand = resp.json()["candidates"][0]
        text = "".join(p.get("text", "") for p in cand["content"]["parts"])
        chunks = (cand.get("groundingMetadata") or {}).get("groundingChunks") or []
        sources = [{"title": c["web"].get("title", ""), "url": c["web"].get("uri", "")} for c in chunks if "web" in c]
        return extract_json(text), sources, "web"
    # No web access: model knowledge only. The app labels this clearly.
    return chat_json("You are a careful market researcher. Output only JSON.", prompt, 0.4), [], "model_only"


def youtube_top_videos(keywords: list[str], lang: str, per_keyword: int = 5) -> list[dict]:
    if not settings.youtube_api_key or not keywords:
        return []
    after = (datetime.now(timezone.utc) - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
    ids: list[str] = []
    for kw in keywords[:3]:
        r = httpx.get(
            "https://www.googleapis.com/youtube/v3/search",
            params={
                "key": settings.youtube_api_key, "q": kw, "part": "id", "type": "video",
                "order": "viewCount", "publishedAfter": after, "maxResults": per_keyword,
                "relevanceLanguage": lang,
            },
            timeout=30,
        )
        r.raise_for_status()
        ids += [i["id"]["videoId"] for i in r.json().get("items", []) if i["id"].get("videoId")]
    if not ids:
        return []
    r = httpx.get(
        "https://www.googleapis.com/youtube/v3/videos",
        params={"key": settings.youtube_api_key, "id": ",".join(dict.fromkeys(ids)),
                "part": "snippet,statistics,contentDetails"},
        timeout=30,
    )
    r.raise_for_status()
    videos = [
        {
            "platform": "youtube",
            "title": v["snippet"]["title"],
            "channel": v["snippet"]["channelTitle"],
            "views": int(v["statistics"].get("viewCount", 0)),
            "likes": int(v["statistics"].get("likeCount", 0)),
            "duration": v["contentDetails"]["duration"],
            "published": v["snippet"]["publishedAt"][:10],
            "url": f"https://www.youtube.com/watch?v={v['id']}",
            "thumbnail": v["snippet"]["thumbnails"].get("medium", {}).get("url", ""),
        }
        for v in r.json().get("items", [])
    ]
    return sorted(videos, key=lambda v: v["views"], reverse=True)[:12]


def instagram_top_posts(hashtags: list[str]) -> list[dict]:
    """Uses the Apify Instagram hashtag scraper when APIFY_TOKEN is set (a paid third-party service)."""
    if not settings.apify_token or not hashtags:
        return []
    r = httpx.post(
        "https://api.apify.com/v2/acts/apify~instagram-hashtag-scraper/run-sync-get-dataset-items",
        params={"token": settings.apify_token},
        json={"hashtags": hashtags[:3], "resultsLimit": 20, "resultsType": "posts"},
        timeout=300,
    )
    r.raise_for_status()
    posts = [
        {
            "platform": "instagram",
            "title": (p.get("caption") or "")[:120],
            "channel": p.get("ownerUsername", ""),
            "views": int(p.get("videoViewCount") or p.get("videoPlayCount") or 0),
            "likes": int(p.get("likesCount") or 0),
            "type": p.get("type", ""),
            "url": p.get("url", ""),
            "published": (p.get("timestamp") or "")[:10],
        }
        for p in r.json()
    ]
    return sorted(posts, key=lambda p: (p["views"], p["likes"]), reverse=True)[:12]


def analyze_styles(b: Brand, videos: list[dict]) -> list[dict]:
    if not videos:
        return []
    catalog = [{"id": s["id"], "name": s["name_en"], "desc": s["description_en"]} for s in VIDEO_STYLES]
    lang = "Persian" if b.language == "fa" else "English"
    prompt = f"""These are the most-viewed recent videos in this brand's niche:
{json.dumps([{k: v[k] for k in ('title', 'views', 'duration', 'platform') if k in v} for v in videos], ensure_ascii=False)}

Our video-style catalog: {json.dumps(catalog)}

Infer from titles, durations and view counts which video styles are working right now. For each pattern,
pick the closest catalog style id. Return ONLY JSON:
{{"styles": [{{"style_id": "...", "pattern": "what these videos do ({lang})", "why_it_works": "({lang})",
  "hook_example": "a hook line for OUR brand in {lang}", "evidence": ["video titles"]}}]}}
Max 4 styles, strongest evidence first."""
    return chat_json("You analyse short-form video trends. Output only JSON.", prompt, 0.4).get("styles", [])


FA_STOP = set("""و در به از که این آن با برای را تا یا هم نیز بر اما اگر چه چرا چطور چگونه کرد کند کنید کنیم شد شود
است هست بود باشد می‌شود میشود های ها ای یک دو سه همه هر خود ما شما آنها ولی پس روی زیر بین بعد قبل بیشتر کمتر
the a an and or of to in on for with how what why is are best top new vs from by at your you this that
سال ماه روز امروز بهترین جدید دانلود آهنگ ساخته شده کامل رایگان قسمت ویدیو ویدئو فیلم آموزش خرید قیمت
ago weeks days months year years views video watch free download full part official""".split())


def _tokens(text: str) -> list[str]:
    import regex

    return [w for w in regex.findall(r"[\p{L}\u200c]{3,}", (text or "").lower()) if w not in FA_STOP]


def _keywords(texts: list[str], n: int = 15) -> list[str]:
    from collections import Counter

    uni, bi = Counter(), Counter()
    for t in texts:
        toks = _tokens(t)
        uni.update(set(toks))
        bi.update({f"{a} {b}" for a, b in zip(toks, toks[1:])})
    phrases, used = [], set()
    for p, c in bi.most_common(n * 3):
        a, b = p.split(" ")
        if c >= 3 and a not in used and b not in used:  # skip overlapping, accidental word pairs
            phrases.append(p)
            used.update((a, b))
    words = [w for w, _ in uni.most_common(n * 2) if w not in used]
    return (phrases + words)[:n]


SENSITIVE = ["سیاست", "سیاسی", "انتخابات", "جنگ", "حمله", "کشته", "اعتراض", "مذهب", "مذهبی", "پاپ", "دولت",
             "تحریم", "زلزله", "پنتاگون", "نظامی", "ارتش", "military", "pentagon", "politic", "election", "war ", "attack", "killed", "pope", "religio"]


def _safe(text: str, b: Brand) -> bool:
    t = (text or "").lower()
    return not any(w.lower() in t for w in SENSITIVE + list(b.forbidden_topics or []))


def collect_free(b: Brand, focus: str) -> dict:
    """Keyless open-source sources: DuckDuckGo web + news (ddgs) and YouTube (yt-dlp)."""
    from .sources import news_search, web_search, youtube_search

    topic = focus or (b.products[0]["name"] if b.products else b.industry)
    queries = [q for q in (f"{b.name} {b.industry}", f"{topic} {b.industry}", f"ترند {b.industry}") if q.strip()]
    web, seen = [], set()
    for q in queries:
        for r in web_search(q, 6):
            if r["url"] not in seen:
                seen.add(r["url"])
                web.append(r)
    news = news_search(f"{b.industry} {focus}".strip(), 8)
    videos = []
    for q in (f"آموزش {topic}", f"{b.industry}"):
        videos += youtube_search(q, 6)
    uniq = {v["url"]: v for v in videos}
    videos = sorted(uniq.values(), key=lambda v: v["views"], reverse=True)
    return {"web": web, "news": news, "videos": videos, "queries": queries}


def _free_prompt(b: Brand, focus: str, data: dict) -> str:
    lang = "Persian" if b.language == "fa" else "English"
    web = [{k: r[k] for k in ("title", "snippet", "url")} for r in data["web"][:15]]
    news = [{k: r[k] for k in ("title", "snippet", "date", "url")} for r in data["news"][:8]]
    vids = [{k: v[k] for k in ("title", "views")} for v in data["videos"][:10]]
    return f"""You are a market researcher. Using ONLY the search results below (collected today), write a market
report for this brand. Do not invent facts that are not supported by the results.

<brand>
{brand_block(b)}
</brand>
<focus>{focus or 'the business as a whole'}</focus>
<web_results>{json.dumps(web, ensure_ascii=False)}</web_results>
<news_this_week>{json.dumps(news, ensure_ascii=False)}</news_this_week>
<top_youtube_videos>{json.dumps(vids, ensure_ascii=False)}</top_youtube_videos>

Return ONLY JSON, user-facing text in {lang}:
{{"summary": "...", "business_facts": ["..."], "competitors": [{{"name": "...", "what_they_post": "...", "gap_we_can_fill": "..."}}],
 "audience_interests": ["..."], "trends": [{{"title": "...", "why_now": "...", "angle_for_brand": "...", "post_type": "educational|news|promo|sales|video_prompt"}}],
 "keywords": ["10-20"], "hashtags": ["15-30 without #"], "content_ideas": [{{"title": "...", "post_type": "...", "format": "single|carousel|video"}}]}}"""


def heuristic_report(b: Brand, focus: str, data: dict) -> dict:
    """Report built only from the search results, for when no text model is available."""
    texts = [r["title"] + " " + r["snippet"] for r in data["web"] + data["news"] if _safe(r["title"], b)]
    texts += [v["title"] for v in data["videos"]]
    kws = _keywords(texts)
    product = b.products[0]["name"] if b.products else b.industry
    trends = [
        {"title": n["title"], "why_now": f"خبر این هفته از {n.get('source') or 'اخبار'}",
         "angle_for_brand": f"ربط دادن این خبر به {product}", "post_type": "news"}
        for n in [n for n in data["news"] if _safe(n["title"] + " " + n["snippet"], b)][:5]
    ]
    ideas = [{"title": v["title"], "post_type": "educational", "format": "carousel"} for v in data["videos"][:3]]
    ideas += [{"title": f"{k} از نگاه {b.name}", "post_type": "educational", "format": "single"} for k in kws[:3]]
    summary = (
        f"{len(data['web'])} نتیجه‌ی وب، {len(data['news'])} خبر این هفته و {len(data['videos'])} ویدیو بررسی شد. "
        f"پرتکرارترین موضوع‌ها: {'، '.join(kws[:6]) or '—'}."
    )
    return {
        "summary": summary,
        "business_facts": [f"{r['title']} ({r['url']})" for r in data["web"] if b.name and b.name in r["title"]][:5],
        "competitors": [],
        "audience_interests": kws[:6],
        "trends": trends,
        "keywords": kws,
        "hashtags": [k.replace(" ", "_") for k in kws],
        "content_ideas": ideas,
    }


def run_research(b: Brand, focus: str) -> dict:
    ran: dict = {}
    report = None
    sources: list[dict] = []
    videos: list[dict] = []
    if settings.research_provider == "gemini" and settings.llm_provider != "fake":
        try:
            report, sources, mode = web_research(b, focus)
            ran["web"] = mode
        except Exception as e:  # noqa: BLE001 — fall back to free sources
            log.warning("gemini research failed, using free sources: %s", e)
    if report is None and (settings.research_provider == "fake" or settings.llm_provider == "fake"):
        report, sources, ran["web"] = web_research(b, focus)
        report["instagram_posts"] = []
        report["top_videos"], report["video_styles"], report["sources"], report["ran"] = [], [], sources, ran
        report["created"] = datetime.now(timezone.utc).isoformat()
        return report
    if report is None:
        data = collect_free(b, focus)
        videos += data["videos"]
        sources = [{"title": r["title"], "url": r["url"]} for r in data["web"] + data["news"]]
        try:
            report = chat_json("You are a careful market researcher. Output only JSON.", _free_prompt(b, focus, data), 0.4)
            ran["web"] = "search"
        except Exception as e:  # noqa: BLE001 — no model available: build from the raw results
            log.warning("summary model failed, heuristic report: %s", e)
            report = heuristic_report(b, focus, data)
            ran["web"] = "search_only"
        ran["youtube"] = "ok" if data["videos"] else "off"
    for name, fn, arg in (
        ("youtube_api", youtube_top_videos, report.get("keywords", [])),
        ("instagram", instagram_top_posts, report.get("hashtags", [])),
    ):
        try:
            found = fn(arg, b.language) if name == "youtube_api" else fn(arg)
            if found:
                ran[name] = "ok"
            videos += found
        except Exception as e:  # noqa: BLE001 — one source failing must not sink the report
            log.warning("%s source failed: %s", name, e)
            ran[name] = "error"
    # Instagram without login: niche hashtags + the brand's and competitors' pages, last 3 days
    try:
        from . import instagram_free

        tags = [h for h in (list(b.hashtags or []) + list(report.get("hashtags", []))) if h][:8]
        profiles = [p for p in [b.instagram, *(getattr(b, "competitors", None) or [])] if p]
        ig = instagram_free.collect(tags, profiles, days=3, target=100)
        report["instagram_posts"] = ig["posts"]
        ran["instagram_free"] = f"{len(ig['posts'])} posts" if ig["posts"] else ("blocked" if ig["errors"] else "none")
        report["instagram_errors"] = ig["errors"]
        videos += [p for p in ig["posts"] if p["type"] == "video"][:10]
    except Exception as e:  # noqa: BLE001
        log.warning("instagram free failed: %s", e)
        ran["instagram_free"] = "error"
    uniq = {v["url"]: v for v in videos}
    report["top_videos"] = sorted(uniq.values(), key=lambda v: v.get("views", 0), reverse=True)[:15]
    try:
        report["video_styles"] = analyze_styles(b, report["top_videos"])
    except Exception as e:  # noqa: BLE001
        log.warning("style analysis failed: %s", e)
        report["video_styles"] = []
    report["sources"] = sources
    report["ran"] = ran
    report["created"] = datetime.now(timezone.utc).isoformat()
    return report


def research_brief(report: dict) -> str:
    """Compact research context injected into generation prompts."""
    if not report:
        return ""
    trends = [f"- {t.get('title')}: {t.get('angle_for_brand', '')}" for t in report.get("trends", [])[:5]]
    return (
        f"Market summary: {report.get('summary', '')}\n"
        f"Current trends:\n" + "\n".join(trends) + "\n"
        f"Keywords: {', '.join(report.get('keywords', [])[:12])}\n"
        f"Audience interests: {', '.join(report.get('audience_interests', [])[:8])}"
    )
