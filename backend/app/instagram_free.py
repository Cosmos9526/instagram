"""Instagram without login, via the same public web endpoints the free scrapers use
(`/api/v1/tags/web_info/` for hashtags, `/api/v1/users/web_profile_info/` for profiles).

These are unofficial: they work from clean server IPs, get rate-limited (HTTP 429) from shared/cloud IPs,
and can change without notice. Every function returns [] on failure and records why in `last_errors`."""

import logging
import time

import httpx

log = logging.getLogger("instagram_free")
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/140.0 Safari/537.36",
    "x-ig-app-id": "936619743392459",
    "X-Requested-With": "XMLHttpRequest",
    "Accept-Language": "en-US,en;q=0.9,fa;q=0.8",
    "Referer": "https://www.instagram.com/",
}
last_errors: list[str] = []


def _get(url: str, params: dict) -> dict | None:
    try:
        r = httpx.get(url, params=params, headers=HEADERS, timeout=25, follow_redirects=True)
        if r.status_code != 200:
            last_errors.append(f"{url.rsplit('/', 2)[-2]} {params} -> HTTP {r.status_code}")
            return None
        return r.json()
    except Exception as e:  # noqa: BLE001
        last_errors.append(f"{url} -> {e}")
        return None


def _post(code: str, taken_at: int, user: str, caption: str, likes, comments, views, kind: str, source: str) -> dict:
    likes, comments, views = int(likes or 0), int(comments or 0), int(views or 0)
    return {
        "platform": "instagram", "url": f"https://www.instagram.com/p/{code}/", "code": code,
        "channel": user, "title": (caption or "").strip().replace("\n", " ")[:220],
        "likes": likes, "comments": comments, "views": views, "type": kind,
        "taken_at": taken_at, "engagement": likes + 3 * comments + views // 20, "source": source,
    }


def hashtag_posts(tag: str) -> list[dict]:
    tag = tag.strip().lstrip("#").replace(" ", "_")
    data = _get("https://www.instagram.com/api/v1/tags/web_info/", {"tag_name": tag})
    if not data:
        return []
    out = []
    sections = []
    for key in ("top", "recent"):
        sections += ((data.get("data") or {}).get(key) or {}).get("sections") or []
    for s in sections:
        for m in (s.get("layout_content") or {}).get("medias") or []:
            m = m.get("media") or {}
            if not m.get("code"):
                continue
            kind = {1: "image", 2: "video", 8: "carousel"}.get(m.get("media_type"), "post")
            out.append(_post(
                m["code"], m.get("taken_at") or 0, (m.get("user") or {}).get("username", ""),
                (m.get("caption") or {}).get("text", ""), m.get("like_count"), m.get("comment_count"),
                m.get("play_count") or m.get("view_count"), kind, f"#{tag}",
            ))
    return out


def profile_posts(username: str) -> list[dict]:
    username = username.strip().lstrip("@").split("/")[-1] or username
    data = _get("https://www.instagram.com/api/v1/users/web_profile_info/", {"username": username})
    user = ((data or {}).get("data") or {}).get("user")
    if not user:
        return []
    out = []
    for e in (user.get("edge_owner_to_timeline_media") or {}).get("edges") or []:
        n = e.get("node") or {}
        cap = ((n.get("edge_media_to_caption") or {}).get("edges") or [{}])[0].get("node", {}).get("text", "")
        out.append(_post(
            n.get("shortcode", ""), n.get("taken_at_timestamp") or 0, username, cap,
            (n.get("edge_liked_by") or n.get("edge_media_preview_like") or {}).get("count"),
            (n.get("edge_media_to_comment") or {}).get("count"), n.get("video_view_count"),
            "video" if n.get("is_video") else "image", f"@{username}",
        ))
    return out


def collect(hashtags: list[str], profiles: list[str], days: int = 3, target: int = 100) -> dict:
    """Recent posts for the niche: hashtags + given profiles, last `days` days, best engagement first."""
    last_errors.clear()
    since = time.time() - days * 86400
    posts: dict[str, dict] = {}
    for tag in hashtags[:8]:
        for p in hashtag_posts(tag):
            posts.setdefault(p["code"], p)
        if len(posts) >= target * 2:
            break
        time.sleep(1.0)  # be gentle: avoids the rate limit
    for u in profiles[:6]:
        for p in profile_posts(u):
            posts.setdefault(p["code"], p)
        time.sleep(1.0)
    recent = [p for p in posts.values() if p["taken_at"] >= since]
    recent.sort(key=lambda p: p["engagement"], reverse=True)
    return {"posts": recent[:max(target, 150)], "total_seen": len(posts), "errors": last_errors[:10]}
