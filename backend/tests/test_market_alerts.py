from datetime import datetime, timezone

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
                            url='https://example.test/low', importance=2,
                            published_at=datetime(2026, 9, 29, tzinfo=timezone.utc)),
                MarketAlert(fingerprint='high', title='Claude adds a $500 Pro tier', source='Anthropic',
                            url='https://example.test/high', importance=5,
                            category='pricing', published_at=datetime(2026, 9, 30, tzinfo=timezone.utc)),
            ])
            db.commit()
        rows = client.get(f'/brands/{brand_id}/alerts', headers=headers).json()
        assert [row['importance'] for row in rows[:2]] == [5, 2]
        assert rows[0]['category'] == 'pricing'


def test_refresh_deduplicates(monkeypatch):
    init_db()
    item = {'title': 'Claude Pro pricing changed', 'summary': 'A new plan tier is available',
            'source': 'Anthropic', 'url': 'https://example.test/unique', 'importance': 5,
            'published_at': datetime.now(timezone.utc)}
    monkeypatch.setattr(market_alerts, 'collect', lambda: [item])
    with SessionLocal() as db:
        assert market_alerts.refresh(db) == 1
        item['importance'] = 2
        assert market_alerts.refresh(db) == 0
        stored = db.scalar(select(MarketAlert).where(MarketAlert.fingerprint.is_not(None)))
        assert stored.importance == 2
