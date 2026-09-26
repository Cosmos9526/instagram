"""Free, keyless data sources (open source): DuckDuckGo web/news search via `ddgs`, YouTube search via `yt-dlp`.
Every function returns [] on any failure so research never crashes because one source is down."""

import logging

log = logging.getLogger("sources")


def web_search(query: str, max_results: int = 8, region: str = "wt-wt") -> list[dict]:
    try:
        from ddgs import DDGS

        rows = DDGS().text(query, max_results=max_results, region=region)
        return [{"title": r.get("title", ""), "snippet": r.get("body", ""), "url": r.get("href", "")} for r in rows]
    except Exception as e:  # noqa: BLE001
        log.warning("web search failed for %r: %s", query, e)
        return []


def news_search(query: str, max_results: int = 8, region: str = "wt-wt") -> list[dict]:
    try:
        from ddgs import DDGS

        rows = DDGS().news(query, max_results=max_results, region=region, timelimit="w")
        return [
            {"title": r.get("title", ""), "snippet": r.get("body", ""), "url": r.get("url", ""),
             "date": (r.get("date") or "")[:10], "source": r.get("source", "")}
            for r in rows
        ]
    except Exception as e:  # noqa: BLE001
        log.warning("news search failed for %r: %s", query, e)
        return []


def youtube_search(query: str, max_results: int = 8) -> list[dict]:
    """Most relevant YouTube results with view counts (no API key)."""
    try:
        from yt_dlp import YoutubeDL

        opts = {"quiet": True, "no_warnings": True, "extract_flat": True, "skip_download": True}
        with YoutubeDL(opts) as ydl:
            info = ydl.extract_info(f"ytsearch{max_results}:{query}", download=False)
        out = []
        for e in info.get("entries") or []:
            vid = e.get("id")
            if not vid:
                continue
            out.append({
                "platform": "youtube",
                "title": e.get("title", ""),
                "channel": e.get("channel") or e.get("uploader") or "",
                "views": int(e.get("view_count") or 0),
                "duration": int(e.get("duration") or 0),
                "url": f"https://www.youtube.com/watch?v={vid}",
            })
        return out
    except Exception as e:  # noqa: BLE001
        log.warning("youtube search failed for %r: %s", query, e)
        return []
