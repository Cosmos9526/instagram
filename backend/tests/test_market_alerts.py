from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app import market_alerts
from app.db import SessionLocal, init_db
from app.main import app
from app.models import MarketAlert


def test_score_requires_ai_vendor_and_material_change():
    assert market_alerts._score("Claude adds a new $500 Pro plan", "pricing tier", official=True) == 5
    assert market_alerts._score("Private saved views are available", "GitHub update", official=True,
                                source="GitHub") == 0
    assert market_alerts._score("Claude $500 plan reportedly being tested", "leak") == 3
    assert market_alerts._score("Football results", "new season plan") == 0
    assert market_alerts._score("Claude customer story", "a team explains its workflow") == 0


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
        assert market_alerts.refresh(db) == 0
