from datetime import datetime, timezone, timedelta

from fastapi.testclient import TestClient
from sqlalchemy import select

from app import market_alerts
from app.db import SessionLocal, init_db
from app.main import app
from app.models import MarketAlert


def test_score_requires_ai_vendor_and_material_change():
    assert market_alerts._score("Claude adds a new $500 Pro plan", "pricing tier", official=True) == 5
    assert market_alerts._score("Private saved views are available", "GitHub update", official=True,
                                source="GitHub") == 0
    assert market_alerts._score("Claude $500 plan reportedly being tested", "leak") == 3
    assert market_alerts._score("ChatGPT launches a $500 plan", "", source="note") == 0
    assert market_alerts._score(
        "ChatGPT launches a $500 plan", "", source="Boing Boing · via Yahoo"
    ) == 0
    assert market_alerts._score("Football results", "new season plan") == 0
    assert market_alerts._score("Claude customer story", "a team explains its workflow") == 0
    assert market_alerts._score(
        "Hugging Face adds faster AI inference", "A product update for developers",
        official=True, source="Hugging Face",
    ) >= 2
    assert market_alerts._score(
        "Google unveils long-awaited Gemini 4",
        "The next-generation flagship model is rolling out to selected partners",
        source="Axios",
    ) == 5
    assert market_alerts._category(
        "Jev decision model beats Pokémon", "TypeSafe AI's new System One model"
    ) == "buzz"
    assert market_alerts._category(
        "OpenAI introduces Dots", "Always-on agents in ChatGPT"
    ) == "buzz"
    assert market_alerts._score(
        "Developer says Jev decision model beat Pokémon Red",
        "TypeSafe AI released the model this month",
        source="Tom's Hardware",
    ) >= 4


def test_alert_endpoint_returns_important_first():
    with TestClient(app) as client:
        registered = client.post('/auth/register', json={
            'email': 'alerts@example.com', 'password': 'secret123', 'name': 'Alerts',
        }).json()
        headers = {'Authorization': f"Bearer {registered['token']}"}
        brand_id = client.post('/brands', headers=headers, json={
            'name': 'Rahboom', 'industry': 'AI', 'website': 'https://rahboom.com',
        }).json()['id']
        with SessionLocal() as db:
            db.add_all([
                MarketAlert(fingerprint='low', title='Routine Claude release', source='Anthropic',
                            url='https://anthropic.com/news/low', importance=2,
                            published_at=datetime.now(timezone.utc) - timedelta(hours=2)),
                MarketAlert(fingerprint='high', title='Claude adds a $500 Pro tier', source='Anthropic',
                            url='https://anthropic.com/news/high', importance=5,
                            category='pricing', published_at=datetime.now(timezone.utc) - timedelta(hours=1)),
            ])
            db.add_all([
                MarketAlert(fingerprint='old', title='Old', source='Reuters',
                            url='https://reuters.com/old', importance=5,
                            published_at=datetime.now(timezone.utc) - timedelta(hours=25)),
                MarketAlert(fingerprint='undated', title='Undated', source='OpenAI',
                            url='https://openai.com/news/undated', importance=5),
                MarketAlert(fingerprint='unapproved', title='Unapproved', source='Reuters',
                            url='https://scmp.com/ai', importance=5,
                            published_at=datetime.now(timezone.utc)),
            ])
            db.commit()
        rows = client.get(f'/brands/{brand_id}/alerts', headers=headers).json()
        assert [row['importance'] for row in rows] == [5, 2]
        assert rows[0]['category'] == 'pricing'


def test_refresh_deduplicates(monkeypatch):
    from app import social_trends
    monkeypatch.setattr(social_trends, "collect", lambda: [])
    init_db()
    item = {'title': 'Claude Pro pricing changed', 'summary': 'A new plan tier is available',
            'source': 'Anthropic', 'url': 'https://anthropic.com/news/unique', 'importance': 5,
            'published_at': datetime.now(timezone.utc)}
    monkeypatch.setattr(market_alerts, 'collect', lambda: [item])
    with SessionLocal() as db:
        assert market_alerts.refresh(db) == 1
        item['importance'] = 2
        assert market_alerts.refresh(db) == 0
        stored = db.scalar(select(MarketAlert).where(MarketAlert.fingerprint.is_not(None)))
        assert stored.importance == 2


def test_news_policy_checks_actual_host_and_rolling_window():
    now = datetime(2026, 10, 2, 12, tzinfo=timezone.utc)
    assert market_alerts._date("2026-10-02") is None
    recent = now - timedelta(hours=1)
    assert market_alerts.eligible_news("https://www.reuters.com/technology/ai", recent, now)
    assert market_alerts.eligible_news("https://blog.google/ai", now - timedelta(hours=24), now)
    for url in ("https://scmp.com/ai", "https://example.cn/ai", "https://reuters.com.evil.test/ai",
                "https://unknown.com/ai", "https://note.com/ai", "file://reuters.com/ai"):
        assert not market_alerts.eligible_news(url, recent, now)
    for published in (None, now - timedelta(hours=24, seconds=1), now + timedelta(seconds=1)):
        assert not market_alerts.eligible_news("https://openai.com/news/ai", published, now)


def test_collect_excludes_unknown_old_and_unapproved_news(monkeypatch):
    now = datetime.now(timezone.utc)
    monkeypatch.setattr(market_alerts, "FEEDS", {})
    monkeypatch.setattr(market_alerts, "QUERIES", ("AI",))
    def search(query, max_results, timelimit):
        assert timelimit == "d"
        return [
            {"title": "Claude launches new model", "source": "Reuters", "url": url,
             "date": date, "snippet": "Anthropic release"}
            for url, date in (
                ("https://reuters.com/recent", (now - timedelta(hours=1)).isoformat()),
                ("https://reuters.com/old", (now - timedelta(hours=25)).isoformat()),
                ("https://reuters.com/unknown", ""),
                ("https://scmp.com/recent", now.isoformat()),
            )
        ]
    monkeypatch.setattr(market_alerts, "news_search", search)
    assert [r["url"] for r in market_alerts.collect()] == ["https://reuters.com/recent"]
