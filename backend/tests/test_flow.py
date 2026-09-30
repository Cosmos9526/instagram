from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.template_registry import TEMPLATES, enforce, length, violations
from app.worker import process_one

BRAND = {
    "name": "کافه نمونه", "industry": "کافه و قهوه", "language": "fa",
    "products": [{"name": "قهوه‌ی اسپشیالتی", "desc": "دانه‌ی تازه رُست"}],
    "audience": "۲۲ تا ۳۵ ساله‌های تهران", "tone": "صمیمی و مؤدب",
    "colors": {"primary": "#6B3E26", "secondary": "#F2C14E", "bg": "#FFF8F0", "text": "#2B1B12"},
    "forbidden_topics": ["سیاست"], "cta": "دایرکت بدید", "hashtags": ["کافه_نمونه"],
}
_n = 0


def _drain():
    while process_one():
        pass


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


def _user(c) -> dict:
    global _n
    _n += 1
    r = c.post("/auth/register", json={"email": f"u{_n}@example.com", "password": "secret123", "name": "میلاد"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _png(path: str) -> bytes:
    return (Path(settings.media_dir) / path.removeprefix("/media/")).read_bytes()


def test_limits_ignore_zwnj_and_truncate():
    assert length("می‌خواهم") == 7
    assert violations("car_cta", {"headline": "x" * 80, "cta": "ok"}) == ["headline 80/70"]
    assert length(enforce("car_cta", {"headline": "کلمه " * 30, "cta": "ok"})["headline"]) <= 70


def test_auth(client):
    h = _user(client)
    assert client.get("/auth/me", headers=h).json()["name"] == "میلاد"
    assert client.post("/auth/login", json={"email": f"u{_n}@example.com", "password": "wrong-pass"}).status_code == 401
    assert client.post("/auth/login", json={"email": f"U{_n}@example.com", "password": "secret123"}).status_code == 200
    assert client.get("/brands").status_code == 401
    assert client.get("/brands", headers={"Authorization": "Bearer forged.123.abc"}).status_code == 401


def test_projects_are_private(client):
    a, b = _user(client), _user(client)
    bid = client.post("/brands", json=BRAND, headers=a).json()["id"]
    client.post("/brands", json=BRAND | {"name": "پروژه‌ی دوم"}, headers=a)
    assert len(client.get("/brands", headers=a).json()) == 2
    assert client.get("/brands", headers=b).json() == []
    assert client.get(f"/brands/{bid}", headers=b).status_code == 404
    assert client.post(f"/brands/{bid}/generate", json={"post_type": "news"}, headers=b).status_code == 404


def test_end_to_end_all_post_types(client):
    h = _user(client)
    bid = client.post("/brands", json=BRAND, headers=h).json()["id"]
    ids = [
        client.post(f"/brands/{bid}/generate", json=body, headers=h).json()["id"]
        for body in (
            {"post_type": "educational"},
            {"post_type": "news", "topic_hint": "افزایش قیمت دانه‌ی قهوه"},
            {"post_type": "promo", "template": "testimonial"},
            {"post_type": "sales"},
            {"post_type": "educational", "mode": "carousel", "n_body": 3},
            {"post_type": "video_prompt", "target_seconds": 16, "video_style": "pov"},
        )
    ]
    _drain()
    posts = {i: client.get(f"/posts/{i}", headers=h).json() for i in ids}
    for p in posts.values():
        assert p["status"] == "ready", p["error"]
    assert posts[ids[2]]["content"]["template"] == "testimonial"
    carousel = posts[ids[4]]
    assert len(carousel["slides"]) == 5
    assert all(_png(s)[:4] == b"\x89PNG" for s in carousel["slides"])
    video = posts[ids[5]]["content"]
    assert video["video_style"] == "pov"
    assert all(clip["full_prompt"].startswith(video["bible_text"]) for clip in video["clips"])
    assert "کافه_نمونه" in posts[ids[0]]["content"]["hashtags"]

    edited = posts[ids[0]]["content"] | {"slots": posts[ids[0]]["content"]["slots"] | {"headline": "تیتر جدید"}}
    assert client.put(f"/posts/{ids[0]}", json={"content": edited}, headers=h).status_code == 200
    _drain()
    r = client.get(f"/posts/{ids[0]}", headers=h).json()
    assert r["status"] == "ready" and r["content"]["slots"]["headline"] == "تیتر جدید"
    assert client.post(f"/posts/{ids[0]}/approve", headers=h).json()["status"] == "approved"


def test_template_rotation(client):
    h = _user(client)
    bid = client.post("/brands", json=BRAND, headers=h).json()["id"]
    for _ in range(3):
        client.post(f"/brands/{bid}/generate", json={"post_type": "educational"}, headers=h)
        _drain()
    used = [p["content"]["template"] for p in client.get(f"/brands/{bid}/posts", headers=h).json()]
    assert len(set(used)) == 3


@pytest.mark.parametrize("code", [c for c, s in TEMPLATES.items() if not s.get("carousel")])
def test_every_single_template_renders(client, code):
    h = _user(client)
    bid = client.post("/brands", json=BRAND, headers=h).json()["id"]
    post_type = TEMPLATES[code]["types"][0]
    pid = client.post(f"/brands/{bid}/generate", json={"post_type": post_type, "template": code}, headers=h).json()["id"]
    _drain()
    p = client.get(f"/posts/{pid}", headers=h).json()
    assert p["status"] == "ready", p["error"]
    assert _png(p["slides"][0])[:4] == b"\x89PNG"


def test_research_feeds_generation(client):
    h = _user(client)
    bid = client.post("/brands", json=BRAND, headers=h).json()["id"]
    r = client.post(f"/brands/{bid}/research", json={"focus": "کلدبرو"}, headers=h).json()
    assert client.post(f"/brands/{bid}/research", json={}, headers=h).status_code == 409
    _drain()
    rep = client.get(f"/brands/{bid}/research", headers=h).json()[0]
    assert rep["id"] == r["id"] and rep["status"] == "ready", rep["error"]
    assert rep["report"]["keywords"] and rep["report"]["ran"]["web"] == "fake"

    from app import llm

    seen = []
    orig = llm.chat_json

    def spy(system, user, temperature=0.8):
        seen.append(user)
        return orig(system, user, temperature)

    import app.pipeline as pipeline

    pipeline.chat_json = spy
    try:
        client.post(f"/brands/{bid}/generate", json={"post_type": "educational"}, headers=h)
        _drain()
    finally:
        pipeline.chat_json = orig
    assert any("<market_research>" in u and "کلدبرو" in u for u in seen)


def test_catalog(client):
    cat = client.get("/catalog").json()
    assert len(cat["templates"]) == len(TEMPLATES) >= 18
    assert len(cat["video_styles"]) >= 12


def test_daily_batch_uses_weekly_plan_and_refreshes_research(client):
    from datetime import datetime

    from app.scheduler import create_daily_posts

    h = _user(client)
    bid = client.post("/brands", json=BRAND | {"weekly_plan": {"5": ["news", "educational:carousel"]}},
                      headers=h).json()["id"]
    saturday = datetime(2026, 9, 26)
    create_daily_posts(saturday)
    assert create_daily_posts(saturday) == 0  # idempotent per day
    posts = client.get(f"/brands/{bid}/posts", params={"date": "2026-09-26"}, headers=h).json()
    assert sorted((p["post_type"], p["mode"]) for p in posts) == [("educational", "carousel"), ("news", "single")]
    assert len(client.get(f"/brands/{bid}/research", headers=h).json()) == 1


def test_rahboom_research_refreshes_even_when_today_has_content(client):
    from datetime import datetime, timedelta, timezone
    from app.db import SessionLocal
    from app.models import Post, Research
    from app.scheduler import create_daily_posts

    h = _user(client)
    bid = client.post('/brands', headers=h, json=BRAND | {
        'website': 'https://rahboom.com', 'weekly_plan': {},
    }).json()['id']
    with SessionLocal() as db:
        db.add(Research(brand_id=bid, status='ready', created_at=datetime.now(timezone.utc) - timedelta(hours=21)))
        db.add(Post(brand_id=bid, post_type='video_prompt', mode='video', for_date='2026-09-30'))
        db.commit()
    create_daily_posts(datetime(2026, 9, 30))
    rows = client.get(f'/brands/{bid}/research', headers=h).json()
    assert len(rows) == 2 and rows[0]['status'] == 'queued'


def test_legacy_project_without_name_still_lists(client):
    from app.db import SessionLocal
    from app.models import Brand

    h = _user(client)
    uid = client.get("/auth/me", headers=h).json()["id"]
    with SessionLocal() as db:
        db.add(Brand(owner_id=uid, name="", industry="کافه و رستوران"))
        db.commit()
    r = client.get("/brands", headers=h)
    assert r.status_code == 200 and r.json()[0]["name"] == ""
    assert client.post("/brands", json=BRAND | {"name": "  "}, headers=h).status_code == 422


def test_delete_restore_and_price_search_ownership(client, monkeypatch):
    from app.db import SessionLocal
    from app.models import CompetitorScan, Post
    from app import price_search
    monkeypatch.setattr(price_search, "run_price_search", lambda *a, **kw: {"kind": "price_search", "results": []})
    a,b=_user(client),_user(client)
    bid=client.post('/brands',headers=a,json=BRAND | {'competitors':[{'website':'https://example.com'}]}).json()['id']
    with SessionLocal() as db:
        p=Post(brand_id=bid,post_type='video_prompt',mode='video',status='ready',content={'title':'Keep me'})
        db.add(p);db.commit();pid=p.id
    assert client.delete(f'/posts/{pid}',headers=b).status_code==404
    assert client.delete(f'/posts/{pid}',headers=a).status_code==200
    assert client.get(f'/brands/{bid}/posts',headers=a).json()==[]
    assert client.post(f'/posts/{pid}/regenerate',headers=a).status_code==409
    assert client.post(f'/posts/{pid}/restore',headers=a).json()['status']=='ready'
    assert len(client.get(f'/brands/{bid}/posts',headers=a).json())==1
    assert client.post(f'/brands/{bid}/competitors/prices',headers=b,json={'query':'Claude Max'}).status_code==404
    assert client.post(f'/brands/{bid}/competitors/prices',headers=a,json={'query':'قیمت'}).status_code==422
    r=client.post(f'/brands/{bid}/competitors/prices',headers=a,json={'query':'Claude Max'})
    assert r.status_code==200 and r.json()['report']['kind']=='price_search'
    second=client.post(f'/brands/{bid}/competitors/prices',headers=a,json={'query':'Cursor'})
    assert second.status_code==200
    assert second.json()['report']['query']=='Cursor'
    with SessionLocal() as db:
        first=db.get(CompetitorScan,r.json()['id'])
        assert first.status=='cancelled'
    stopped=client.post(f"/competitor-scans/{second.json()['id']}/cancel",headers=a)
    assert stopped.status_code==200 and stopped.json()['status']=='cancelled'
    assert stopped.json()['error']=='Stopped by user'
    assert client.post(f"/competitor-scans/{second.json()['id']}/cancel",headers=b).status_code==404


def test_video_content_label_is_saved(client):
    h = _user(client)
    bid = client.post('/brands', headers=h, json=BRAND).json()['id']
    post = client.post(f'/brands/{bid}/generate', headers=h, json={
        'post_type': 'video_prompt', 'mode': 'video',
        'topic_hint': 'A sourced AI news story', 'content_label': 'news',
    })
    assert post.status_code == 200
    assert post.json()['content']['content_label'] == 'news'
    assert client.post(f'/brands/{bid}/generate', headers=h, json={
        'post_type': 'video_prompt', 'content_label': 'unknown',
    }).status_code == 422

    _drain()
