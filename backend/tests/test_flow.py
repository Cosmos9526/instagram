from pathlib import Path

from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from app.template_registry import enforce, length, violations
from app.worker import process_one

H = {"Authorization": "Bearer t"}
BRAND = {
    "name": "کافه نمونه", "industry": "کافه و قهوه", "language": "fa",
    "products": [{"name": "قهوه‌ی اسپشیالتی", "desc": "دانه‌ی تازه رُست"}],
    "audience": "۲۲ تا ۳۵ ساله‌های تهران", "tone": "صمیمی و مؤدب",
    "colors": {"primary": "#6B3E26", "secondary": "#F2C14E", "bg": "#FFF8F0", "text": "#2B1B12"},
    "forbidden_topics": ["سیاست"], "cta": "دایرکت بدید", "hashtags": ["کافه_نمونه"],
}


def _drain():
    while process_one():
        pass


def test_limits_ignore_zwnj_and_truncate():
    assert length("می‌خواهم") == 7
    assert violations("car_cta", {"headline": "x" * 80, "cta": "ok"}) == ["headline 80/70"]
    assert length(enforce("car_cta", {"headline": "کلمه " * 30, "cta": "ok"})["headline"]) <= 70


def test_end_to_end_all_post_types():
    with TestClient(app) as c:
        assert c.post("/brands", json=BRAND).status_code == 401
        bid = c.post("/brands", json=BRAND, headers=H).json()["id"]
        ids = [
            c.post(f"/brands/{bid}/generate", json=body, headers=H).json()["id"]
            for body in (
                {"post_type": "educational"},
                {"post_type": "news", "topic_hint": "افزایش قیمت دانه‌ی قهوه"},
                {"post_type": "promo"},
                {"post_type": "sales"},
                {"post_type": "educational", "mode": "carousel", "n_body": 3},
                {"post_type": "video_prompt", "target_seconds": 16},
            )
        ]
        _drain()
        posts = {i: c.get(f"/posts/{i}", headers=H).json() for i in ids}
        for p in posts.values():
            assert p["status"] == "ready", p["error"]
        carousel = posts[ids[4]]
        assert len(carousel["slides"]) == 5
        for s in carousel["slides"]:
            png = Path(settings.media_dir) / s.removeprefix("/media/")
            assert png.read_bytes()[:4] == b"\x89PNG"
        video = posts[ids[5]]["content"]
        bible = video["bible_text"]
        assert all(clip["full_prompt"].startswith(bible) for clip in video["clips"])
        assert "کافه_نمونه" in posts[ids[0]]["content"]["hashtags"]

        edited = posts[ids[0]]["content"] | {"slots": posts[ids[0]]["content"]["slots"] | {"headline": "تیتر جدید"}}
        assert c.put(f"/posts/{ids[0]}", json={"content": edited}, headers=H).status_code == 200
        _drain()
        r = c.get(f"/posts/{ids[0]}", headers=H).json()
        assert r["status"] == "ready" and r["content"]["slots"]["headline"] == "تیتر جدید"
        assert c.post(f"/posts/{ids[0]}/approve", headers=H).json()["status"] == "approved"


def test_daily_batch_uses_weekly_plan():
    from datetime import datetime

    from app.scheduler import create_daily_posts

    with TestClient(app) as c:
        bid = c.post("/brands", json=BRAND | {"weekly_plan": {"5": ["news", "educational:carousel"]}},
                     headers=H).json()["id"]
        saturday = datetime(2026, 9, 26)
        create_daily_posts(saturday)
        assert create_daily_posts(saturday) == 0  # idempotent per day
        posts = c.get(f"/brands/{bid}/posts", params={"date": "2026-09-26"}, headers=H).json()
        assert sorted((p["post_type"], p["mode"]) for p in posts) == [("educational", "carousel"), ("news", "single")]
