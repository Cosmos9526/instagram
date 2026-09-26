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


def run_research(b: Brand, focus: str) -> dict:
    report, sources, mode = web_research(b, focus)
    ran = {"web": mode}
    videos: list[dict] = []
    for name, fn, arg in (
        ("youtube", youtube_top_videos, report.get("keywords", [])),
        ("instagram", instagram_top_posts, report.get("hashtags", [])),
    ):
        try:
            found = fn(arg, b.language) if name == "youtube" else fn(arg)
            ran[name] = "ok" if found else "off"
            videos += found
        except Exception as e:  # noqa: BLE001 — one source failing must not sink the report
            log.warning("%s source failed: %s", name, e)
            ran[name] = "error"
    videos.sort(key=lambda v: v.get("views", 0), reverse=True)
    report["top_videos"] = videos[:15]
    report["video_styles"] = analyze_styles(b, videos)
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
