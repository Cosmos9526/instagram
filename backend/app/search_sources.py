"""Keyless sources built on public search engines:

- Instagram posts through search-engine results (site:instagram.com): link, account, caption, age, and
  likes/comments when the snippet includes them. Search engines index public posts within days.
- Google autocomplete: what people type right now.
- Google Trends rising queries (Iran by default): what is growing.
- Video search (DuckDuckGo videos: YouTube, Aparat, ...).

Every function returns [] on failure; research continues with the other sources."""

import logging
import re
import time
from datetime import datetime, timedelta, timezone

import httpx

log = logging.getLogger("search_sources")
_NUM = r"([\d.,]+\s*[KkMm]?)"


def _num(s: str) -> int:
    s = (s or "").replace(",", "").strip().upper()
    mult = 1_000 if s.endswith("K") else 1_000_000 if s.endswith("M") else 1
    try:
        return int(float(s.rstrip("KM")) * mult)
    except ValueError:
        return 0


def _age_hours(text: str) -> float | None:
    """'3 days ago', '5 hours ago', 'on September 24, 2026' -> hours since posting."""
    m = re.search(r"(\d+)\s+(minute|hour|day|week)s?\s+ago", text)
    if m:
        n, unit = int(m.group(1)), m.group(2)
        return n * {"minute": 1 / 60, "hour": 1, "day": 24, "week": 168}[unit]
    m = re.search(r"on ([A-Z][a-z]+ \d{1,2}, \d{4})", text)
    if m:
        try:
            d = datetime.strptime(m.group(1), "%B %d, %Y").replace(tzinfo=timezone.utc)
            return (datetime.now(timezone.utc) - d).total_seconds() / 3600
        except ValueError:
            return None
    return None


def parse_instagram_result(r: dict) -> dict | None:
    url = r.get("href") or r.get("url") or ""
    m = re.match(r"https://(?:www\.)?instagram\.com/(?:[\w.]+/)?(p|reel|reels|tv)/([\w-]+)", url)
    if not m:
        return None
    title, body = r.get("title", ""), r.get("body", "")
    text = f"{title} {body}"
    likes = re.search(_NUM + r"\s*likes?\b", text)
    comments = re.search(_NUM + r"\s*comments?\b", text)
    user = re.search(r"-\s*([\w.]+)\s+on\s+[A-Z][a-z]+ \d", text) or re.search(r"\(@([\w.]+)\)", text)
    caption = re.sub(r"^.*?\d{4}:\s*", "", body) if re.search(r"on [A-Z][a-z]+ \d{1,2}, \d{4}:", body) else body
    caption = re.sub(r"^\d+\s+\w+\s+ago\s*·\s*", "", caption)
    caption = re.sub(r"^Follow\s+[\d.,KkMm]+\s*likes?\s+[\w.]+\s*", "", caption).strip(' "')
    kind = "video" if m.group(1) in ("reel", "reels", "tv") else "post"
    likes_n, comments_n = _num(likes.group(1)) if likes else 0, _num(comments.group(1)) if comments else 0
    return {
        "platform": "instagram", "url": f"https://www.instagram.com/{'reel' if kind == 'video' else 'p'}/{m.group(2)}/",
        "code": m.group(2), "type": kind,
        "channel": user.group(1) if user else title.split("|")[0].split("on Instagram")[0].strip()[:40],
        "title": caption[:240] or title[:240], "likes": likes_n, "comments": comments_n, "views": 0,
        "age_hours": _age_hours(text), "engagement": likes_n + 3 * comments_n, "source": "search",
    }


def instagram_via_search(keywords: list[str], days: int = 3, target: int = 100, must: list[str] | None = None) -> dict:
    """Recent public Instagram posts for the keywords, found through a search engine.
    `must`: core topics; a post must match a meaningful topic token (defaults to keywords)."""
    from ddgs import DDGS

    from .research import _relevant

    posts: dict[str, dict] = {}
    errors = []
    limit = "w" if days <= 7 else "m"

    topics = must or keywords
    for kw in keywords[:12]:
        for q in (f"site:instagram.com {kw}", f"site:instagram.com/reel {kw}", f"instagram {kw}"):
            try:
                for r in DDGS().text(q, max_results=30, timelimit=limit):
                    p = parse_instagram_result(r)
                    if p and _relevant(r.get("title", "") + " " + r.get("body", ""), topics):
                        p["keyword"] = kw
                        posts.setdefault(p["code"], p)
            except Exception as e:  # noqa: BLE001
                errors.append(f"{q}: {str(e)[:80]}")
            time.sleep(0.8)
        if len(posts) >= target * 1.3:
            break
    fresh = [p for p in posts.values() if p["age_hours"] is None or p["age_hours"] <= days * 24 + 12]
    fresh.sort(key=lambda p: (p["engagement"], -(p["age_hours"] or 999)), reverse=True)
    return {"posts": fresh[:max(target, 150)], "total_seen": len(posts), "errors": errors[:5]}


def google_suggest(query: str, lang: str = "fa") -> list[str]:
    try:
        r = httpx.get("https://suggestqueries.google.com/complete/search",
                      params={"client": "firefox", "hl": lang, "q": query}, timeout=15)
        return [s for s in r.json()[1] if s.strip() != query.strip()]
    except Exception as e:  # noqa: BLE001
        log.warning("suggest failed: %s", e)
        return []


def google_rising(keywords: list[str], geo: str = "IR", timeframe: str = "today 3-m") -> list[dict]:
    """Rising related searches from Google Trends for the requested window."""
    out = []
    try:
        from pytrends.request import TrendReq

        pt = TrendReq(hl="fa", tz=210, timeout=(10, 25))
        for kw in keywords[:3]:
            pt.build_payload([kw], geo=geo, timeframe=timeframe)
            rising = (pt.related_queries().get(kw) or {}).get("rising")
            if rising is not None:
                out += [{"query": q, "growth": str(v), "seed": kw} for q, v in zip(rising["query"], rising["value"])]
            time.sleep(1)
    except Exception as e:  # noqa: BLE001
        log.warning("trends failed: %s", e)
    return out[:25]


def video_search(query: str, days: int = 7) -> list[dict]:
    try:
        from ddgs import DDGS

        rows = DDGS().videos(query, max_results=20, timelimit="d" if days <= 1 else "w" if days <= 7 else "m")
        return [{
            "platform": (r.get("publisher") or "video").lower(), "title": r.get("title", ""),
            "channel": r.get("uploader", ""), "views": int((r.get("statistics") or {}).get("viewCount") or 0),
            "url": r.get("content") or r.get("embed_url", ""), "published": (r.get("published") or "")[:10],
        } for r in rows]
    except Exception as e:  # noqa: BLE001
        log.warning("video search failed: %s", e)
        return []


def since(days: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=days)
