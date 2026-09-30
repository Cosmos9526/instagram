"""Fresh, source-backed content signals for Rahboom's daily video desk."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
import xml.etree.ElementTree as ET

import httpx

from .search_sources import google_rising, google_suggest, google_trending_now, video_search
from .sources import news_search


# Forty commercial/educational AI subjects × seven useful search intents = 280
# Persian, English and mixed-language phrases. We keep the full bank for coverage,
# but rotate a small sample each day so a refresh stays fast and respectful.
TOPICS = [
    ("هوش مصنوعی", "artificial intelligence"), ("چت جی پی تی", "ChatGPT"),
    ("کلاد", "Claude AI"), ("کلاد مکس", "Claude Max"), ("جمینای", "Google Gemini"),
    ("گوگل فلو", "Google Flow"), ("ساخت ویدیو با هوش مصنوعی", "AI video generation"),
    ("ساخت عکس با هوش مصنوعی", "AI image generation"), ("پرامپت نویسی", "prompt engineering"),
    ("تولید محتوا با هوش مصنوعی", "AI content creation"), ("کرسر", "Cursor AI"),
    ("گیت هاب کوپایلت", "GitHub Copilot"), ("کدنویسی با هوش مصنوعی", "AI coding"),
    ("ساخت سایت با هوش مصنوعی", "AI website builder"), ("اتوماسیون با هوش مصنوعی", "AI automation"),
    ("عامل هوش مصنوعی", "AI agents"), ("جستجوی هوش مصنوعی", "AI search"),
    ("تحقیق با هوش مصنوعی", "AI research"), ("پایان نامه با هوش مصنوعی", "AI for thesis"),
    ("مقاله نویسی با هوش مصنوعی", "AI writing"), ("ترجمه با هوش مصنوعی", "AI translation"),
    ("یادگیری زبان با هوش مصنوعی", "AI language learning"), ("طراحی با هوش مصنوعی", "AI design"),
    ("ادیت ویدیو با هوش مصنوعی", "AI video editing"), ("تبدیل متن به ویدیو", "text to video"),
    ("تبدیل عکس به ویدیو", "image to video"), ("تبدیل صدا به متن", "speech to text"),
    ("ساخت صدا با هوش مصنوعی", "AI voice generator"), ("ساخت موسیقی با هوش مصنوعی", "AI music"),
    ("ارائه با هوش مصنوعی", "AI presentation"), ("رزومه با هوش مصنوعی", "AI resume"),
    ("مارکتینگ با هوش مصنوعی", "AI marketing"), ("سئو با هوش مصنوعی", "AI SEO"),
    ("اینستاگرام با هوش مصنوعی", "AI for Instagram"), ("یوتیوب با هوش مصنوعی", "AI for YouTube"),
    ("اشتراک هوش مصنوعی", "AI subscription"), ("خرید اکانت هوش مصنوعی", "AI account"),
    ("مقایسه ابزارهای هوش مصنوعی", "AI tools comparison"), ("مدل زبانی", "large language model"),
    ("اخبار هوش مصنوعی", "AI news"),
]

YOUTUBE_CHANNELS = {
    "OpenAI": "UCXZCJLdBC09xxGZ6gcdrc6A",
    "Google for Developers": "UC_x5XG1OV2P6uZZ5FSM9Ttw",
    "Two Minute Papers": "UCbfYPyITQ-7l4upoX8nvctg",
    "Fireship": "UCsBjURrPoezykLs9EqgamOA",
}


def keyword_bank() -> list[str]:
    out = []
    for fa, en in TOPICS:
        out += [fa, f"آموزش {fa}", f"خرید {fa}", f"قیمت {fa}", f"{fa} رایگان", en, f"{en} tutorial"]
    return list(dict.fromkeys(out))


def daily_queries(day: date | None = None, count: int = 18) -> list[str]:
    bank = keyword_bank()
    day = day or date.today()
    offset = day.toordinal() % len(bank)
    rotated = bank[offset:] + bank[:offset]
    priority = ["اخبار هوش مصنوعی", "AI news", "ChatGPT", "Claude AI", "Google Gemini", "AI video generation"]
    return list(dict.fromkeys(priority + rotated))[:count]


def _dedupe(rows: list[dict], limit: int) -> list[dict]:
    seen, out = set(), []
    for row in rows:
        key = row.get("url") or row.get("query") or row.get("title")
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(row)
    return out[:limit]


def youtube_channel_feeds() -> list[dict]:
    """Keyless fallback: recent uploads from authoritative/high-signal AI channels."""
    ns = {"a": "http://www.w3.org/2005/Atom", "yt": "http://www.youtube.com/xml/schemas/2015"}
    out = []
    for channel, channel_id in YOUTUBE_CHANNELS.items():
        try:
            xml = httpx.get(
                "https://www.youtube.com/feeds/videos.xml",
                params={"channel_id": channel_id}, timeout=20,
            ).content
            root = ET.fromstring(xml)
            for entry in root.findall("a:entry", ns)[:5]:
                video_id = entry.findtext("yt:videoId", default="", namespaces=ns)
                out.append({
                    "platform": "youtube", "source_type": "youtube_feed",
                    "title": entry.findtext("a:title", default="", namespaces=ns),
                    "channel": channel, "views": 0,
                    "published": entry.findtext("a:published", default="", namespaces=ns),
                    "url": f"https://www.youtube.com/watch?v={video_id}" if video_id else "",
                })
        except Exception:
            continue
    return sorted(out, key=lambda v: v.get("published", ""), reverse=True)


def collect() -> dict:
    queries = daily_queries()
    news, videos, suggestions = [], [], []
    jobs = {}
    with ThreadPoolExecutor(max_workers=6) as pool:
        for q in queries[:8]:
            jobs[pool.submit(news_search, q, 5, "wt-wt", "d")] = ("news", q)
        for q in queries[8:14]:
            jobs[pool.submit(video_search, q, 1)] = ("video", q)
        for q in queries[:12]:
            jobs[pool.submit(google_suggest, q, "fa")] = ("suggest", q)
        for future in as_completed(jobs):
            kind, q = jobs[future]
            try:
                rows = future.result()
            except Exception:
                rows = []
            if kind == "news":
                news += [r | {"keyword": q, "source_type": "news", "window_hours": 24} for r in rows]
            elif kind == "video":
                videos += [r | {"keyword": q, "source_type": "youtube", "window_hours": 24} for r in rows]
            else:
                suggestions += [{"query": s, "seed": q, "source": "Google autocomplete"} for s in rows]
    if not videos:
        videos = youtube_channel_feeds()
    trending_now = google_trending_now("IR")
    rising = google_rising([fa for fa, _ in TOPICS[:5]], timeframe="now 1-d")
    trends = (
        [r | {"window_hours": 24} for r in trending_now]
        + [r | {"window_hours": 24} for r in rising]
        + suggestions
    )
    return {
        "window": "5–24 hours",
        "keyword_bank_count": len(keyword_bank()),
        "queries_checked": queries,
        "news": _dedupe(news, 20),
        "videos": _dedupe(sorted(videos, key=lambda v: v.get("views", 0), reverse=True), 20),
        "search_signals": _dedupe(trends, 30),
    }
