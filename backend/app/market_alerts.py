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
    "Google Developers": "https://developers.googleblog.com/feeds/posts/default",
    "Hugging Face": "https://huggingface.co/blog/feed.xml",
    "Google DeepMind": "https://deepmind.google/blog/rss.xml",
    "NVIDIA AI": "https://blogs.nvidia.com/blog/category/generative-ai/feed/",
}

QUERIES = (
    'Gemini 4 Argon launch rollout Google',
    'Gemini 4 release official Google latest',
    'next generation OpenAI GPT Anthropic Claude flagship model launch',
    'Claude Pro price plan tier $500 $200',
    'site:anthropic.com/news Claude launch plan pricing',
    'Anthropic Claude pricing plan update',
    'OpenAI ChatGPT pricing plan update',
    'Google Gemini Flow pricing plan update',
    'AI model launch subscription price update',
    'Claude ChatGPT Gemini Cursor new feature release',
    'OpenAI Anthropic Google AI major launch today',
    'AI video model launch Veo Sora Runway latest',
    'AI coding Copilot Cursor Claude Code update latest',
    'Mistral Meta Llama Perplexity model release latest',
    'Adobe Firefly ElevenLabs AI product release latest',
    'AI subscription pricing change latest',
)

MATERIAL = (
    "price", "pricing", "plan", "tier", "subscription", "upgrade", "limit",
    "launch", "launched", "release", "released", "introducing", "available", "new model",
    "unveil", "unveils", "unveiled", "announce", "announces", "announced", "rollout",
    "rolling out", "preview", "early access", "upcoming", "next-generation", "flagship",
    "قیمت", "پلن", "اشتراک", "تعرفه", "عرضه", "رونمایی", "مدل جدید",
)
VENDORS = (
    "claude", "anthropic", "openai", "chatgpt", "gemini", "google flow",
    "cursor", "github", "copilot", "grok", "midjourney", "veo", "sora",
    "mistral", "llama", "meta ai", "perplexity", "runway", "firefly",
    "elevenlabs", "notebooklm", "deepmind", "hugging face", "microsoft ai", "nvidia",
    "کلاد", "چت جی پی تی", "جمینای", "گوگل فلو", "کرسر",
)
URGENT = ("price", "pricing", "plan", "tier", "subscription", "launch", "new model",
          "قیمت", "پلن", "اشتراک", "مدل جدید")
AI_PRODUCT = ("ai", "model", "claude", "chatgpt", "openai", "gemini", "flow", "copilot",
              "agent", "grok", "cursor", "هوش مصنوعی", "کلاد", "مدل")
LOW_TRUST_SOURCES = ("note", "letsdatascience", "startup fortune", "the currency analytics",
                     "finance.biggo", "boing boing", "crypto briefing", "tech times on msn")
TRUSTED_NEWS_SOURCES = ("axios", "reuters", "associated press", "ap news", "the verge",
                        "techcrunch", "wired", "ars technica", "bloomberg", "cnet", "zdnet",
                        "venturebeat", "the information")
MAJOR_MODEL_SIGNALS = (
    "gemini 4", "gpt-6", "claude opus", "claude sonnet", "veo", "sora", "deepseek",
    "frontier model", "next-generation", "flagship model", "major model", "new model",
)


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
    has_vendor = any(v in text for v in VENDORS)
    has_material_change = any(k in text for k in MATERIAL)
    if not has_vendor or (not has_material_change and not (official and title_has_ai_product)):
        return 0
    score = 2 + (2 if official else 0)
    # A major model name must be in the headline; generic summary wording must not
    # promote routine company news above an actual flagship launch.
    major_model = any(k in title_text for k in MAJOR_MODEL_SIGNALS)
    if major_model and has_material_change:
        score += 3
    elif major_model:
        score += 2
    if any(k in text for k in URGENT):
        score += 2
    if re.search(r"(?:\$|usd|دلار)\s?\d|\d+\s?(?:usd|دلار)", text):
        score += 1
    uncertain = not official and any(
        k in text for k in ("reportedly", "rumor", "leak", "testing", "گزارش", "شایعه")
    )
    if uncertain:
        score -= 1
    trusted = any(name in source.casefold() for name in TRUSTED_NEWS_SOURCES)
    return max(0, min(score, 5 if official or trusted else 3 if uncertain else 4))


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
        for row in news_search(query, max_results=10, timelimit="w"):
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
    # Remove previously stored weak or stale stories as the source policy improves.
    stale_before = datetime.now(timezone.utc) - timedelta(days=14)
    for alert in db.scalars(select(MarketAlert)):
        published = alert.published_at
        if published is not None and published.tzinfo is None:
            published = published.replace(tzinfo=timezone.utc)
        if alert.source.casefold() in LOW_TRUST_SOURCES or (
            published is not None and published < stale_before
        ):
            db.delete(alert)

    added = 0
    for row in collect():
        fingerprint = hashlib.sha256((row.get("url") or row["title"]).encode()).hexdigest()
        existing = db.scalar(select(MarketAlert).where(MarketAlert.fingerprint == fingerprint))
        if existing:
            # Re-score stored stories whenever ranking rules improve or the source
            # provides better metadata on a later scan.
            existing.title = row["title"]
            existing.summary = row.get("summary", "")
            existing.source = row.get("source", "")
            existing.url = row.get("url", "")
            existing.importance = row["importance"]
            existing.published_at = row.get("published_at")
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
