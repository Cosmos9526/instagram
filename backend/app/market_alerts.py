"""Fast, account-free monitoring for material AI product and pricing changes."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
import hashlib
import logging
import re
import xml.etree.ElementTree as ET

import httpx
from sqlalchemy import select

from .models import MarketAlert
from .sources import news_search

log = logging.getLogger("market_alerts")

FEEDS = {
    "OpenAI": "https://openai.com/news/rss.xml",
    "Google AI": "https://blog.google/technology/ai/rss/",
    "GitHub": "https://github.blog/changelog/feed/",
}

QUERIES = (
    'Claude Pro price plan tier $500 $200',
    'site:anthropic.com/news Claude launch plan pricing',
    'Anthropic Claude pricing plan update',
    'OpenAI ChatGPT pricing plan update',
    'Google Gemini Flow pricing plan update',
    'AI model launch subscription price update',
    'Claude ChatGPT Gemini Cursor new feature release',
)

MATERIAL = (
    "price", "pricing", "plan", "tier", "subscription", "upgrade", "limit",
    "launch", "launched", "release", "released", "introducing", "available", "new model",
    "قیمت", "پلن", "اشتراک", "تعرفه", "عرضه", "رونمایی", "مدل جدید",
)
VENDORS = (
    "claude", "anthropic", "openai", "chatgpt", "gemini", "google flow",
    "cursor", "github", "copilot", "grok", "midjourney", "veo", "sora",
    "کلاد", "چت جی پی تی", "جمینای", "گوگل فلو", "کرسر",
)
URGENT = ("price", "pricing", "plan", "tier", "subscription", "launch", "new model",
          "قیمت", "پلن", "اشتراک", "مدل جدید")
AI_PRODUCT = ("ai", "model", "claude", "chatgpt", "openai", "gemini", "flow", "copilot",
              "agent", "grok", "cursor", "هوش مصنوعی", "کلاد", "مدل")
LOW_TRUST_SOURCES = ("note", "letsdatascience", "startup fortune", "the currency analytics",
                     "finance.biggo")


def _text(node: ET.Element, names: tuple[str, ...]) -> str:
    for child in node.iter():
        if child.tag.rsplit("}", 1)[-1].lower() in names and (child.text or "").strip():
            return (child.text or "").strip()
    return ""


def _link(node: ET.Element) -> str:
    for child in node.iter():
        if child.tag.rsplit("}", 1)[-1].lower() == "link":
            return (child.attrib.get("href") or child.text or "").strip()
    return ""


def _date(value: str) -> datetime | None:
    if not value:
        return None
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _score(title: str, summary: str, official: bool = False, source: str = "") -> int:
    text = f"{title} {summary}".casefold()
    title_text = title.casefold()
    if source.casefold() in LOW_TRUST_SOURCES:
        return 0
    title_has_ai_product = bool(re.search(r"\bai\b", title_text)) or any(
        k in title_text for k in AI_PRODUCT if k != "ai"
    )
    if source == "GitHub" and not title_has_ai_product:
        return 0
    if not any(v in text for v in VENDORS) or not any(k in text for k in MATERIAL):
        return 0
    score = 2 + (2 if official else 0)
    if any(k in text for k in URGENT):
        score += 2
    if re.search(r"(?:\$|usd|دلار)\s?\d|\d+\s?(?:usd|دلار)", text):
        score += 1
    uncertain = not official and any(
        k in text for k in ("reportedly", "rumor", "leak", "testing", "گزارش", "شایعه")
    )
    if uncertain:
        score -= 1
    return max(0, min(score, 5 if official else 3 if uncertain else 4))


def _feed(source: str, url: str) -> list[dict]:
    try:
        response = httpx.get(url, timeout=15, follow_redirects=True,
                             headers={"User-Agent": "RahboomRadar/1.0"})
        response.raise_for_status()
        root = ET.fromstring(response.content)
    except Exception as exc:  # one feed must never stop the radar
        log.warning("alert feed %s failed: %s", source, exc)
        return []
    out = []
    entries = [n for n in root.iter() if n.tag.rsplit("}", 1)[-1].lower() in ("item", "entry")]
    for item in entries[:20]:
        title = _text(item, ("title",))
        summary = re.sub(r"<[^>]+>", " ", _text(item, ("description", "summary", "content")))
        importance = _score(title, summary, official=True, source=source)
        if importance:
            out.append({"title": title, "summary": " ".join(summary.split())[:500],
                        "source": source, "url": _link(item), "importance": importance,
                        "published_at": _date(_text(item, ("pubdate", "published", "updated")))})
    return out


def collect() -> list[dict]:
    rows = []
    for source, url in FEEDS.items():
        rows.extend(_feed(source, url))
    for query in QUERIES:
        for row in news_search(query, max_results=8, timelimit="w"):
            score = _score(row.get("title", ""), row.get("snippet", ""))
            if score:
                rows.append({**row, "summary": row.get("snippet", ""), "importance": score,
                             "published_at": _date(row.get("date", ""))})
    unique = {}
    for row in rows:
        key = row.get("url") or row.get("title", "").casefold()
        if key and (key not in unique or row["importance"] > unique[key]["importance"]):
            unique[key] = row
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    return sorted(
        [r for r in unique.values() if not r.get("published_at") or r["published_at"] >= cutoff],
        key=lambda r: (r["importance"], r.get("published_at") or cutoff), reverse=True,
    )[:30]


def refresh(db) -> int:
    added = 0
    for row in collect():
        fingerprint = hashlib.sha256((row.get("url") or row["title"]).encode()).hexdigest()
        if db.scalar(select(MarketAlert.id).where(MarketAlert.fingerprint == fingerprint)):
            continue
        db.add(MarketAlert(
            fingerprint=fingerprint, title=row["title"], summary=row.get("summary", ""),
            source=row.get("source", ""), url=row.get("url", ""),
            category="pricing" if any(k in f"{row['title']} {row.get('summary', '')}".casefold()
                                      for k in ("price", "pricing", "plan", "tier", "قیمت", "پلن")) else "news",
            importance=row["importance"], published_at=row.get("published_at"),
        ))
        added += 1
    db.commit()
    return added


def out(alert: MarketAlert) -> dict:
    verification = (
        "in_product" if alert.source.endswith("in-product screen")
        else "official" if alert.source in FEEDS
        else "reported"
    )
    return {"id": alert.id, "title": alert.title, "summary": alert.summary,
            "source": alert.source, "url": alert.url, "category": alert.category,
            "importance": alert.importance, "published_at": alert.published_at,
            "discovered_at": alert.discovered_at, "verification": verification}
