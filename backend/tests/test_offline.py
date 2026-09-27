"""No text model reachable: posts are still produced (offline generator) and research falls back to
the keyless sources, summarised heuristically."""

from fastapi.testclient import TestClient

from app import research, sources
from app.config import settings
from app.main import app
from app.worker import process_one

BRAND = {"name": "کلاد مکس", "industry": "هوش مصنوعی", "language": "fa",
         "products": [{"name": "دستیار کدنویسی", "desc": "کد را سریع‌تر و تمیزتر بنویسید"}]}


def _drain():
    while process_one():
        pass


def test_posts_are_built_offline_when_no_model(monkeypatch):
    monkeypatch.setattr(settings, "llm_provider", "openai_compat")
    monkeypatch.setattr(settings, "llm_api_key", "")
    monkeypatch.setattr(settings, "llm_fallback_url", "")
    monkeypatch.setattr(settings, "research_provider", "free")
    from app import instagram_free

    monkeypatch.setattr(instagram_free, "collect", lambda *a, **k: {"posts": [], "total_seen": 0, "errors": []})
    from app import search_sources as ss

    monkeypatch.setattr(ss, "google_suggest", lambda q, lang="fa": [q + " تهران"])
    monkeypatch.setattr(ss, "google_rising", lambda kws, geo="IR": [{"query": "دستیار کدنویسی رایگان", "growth": "+250%", "seed": kws[0]}])
    monkeypatch.setattr(ss, "video_search", lambda q, days=7: [])
    monkeypatch.setattr(ss, "instagram_via_search", lambda kws, days=3, target=100, must=None: {"posts": [
        {"platform": "instagram", "url": "https://www.instagram.com/reel/X1/", "code": "X1", "type": "video",
         "channel": "rival", "title": "آموزش هوش مصنوعی", "likes": 900, "comments": 20, "views": 0,
         "age_hours": 30, "engagement": 960, "source": "search"}], "total_seen": 1, "errors": []})
    monkeypatch.setattr(sources, "web_search", lambda q, n=8, region="wt-wt": [
        {"title": "هوش مصنوعی در برنامه نویسی", "snippet": "دستیار کدنویسی هوش مصنوعی محبوب شده", "url": f"https://x/{q}"}])
    monkeypatch.setattr(sources, "news_search", lambda q, n=8, region="wt-wt": [
        {"title": "مدل جدید هوش مصنوعی منتشر شد", "snippet": "", "url": "https://n/1", "date": "2026-09-25", "source": "خبر"}])
    monkeypatch.setattr(sources, "youtube_search", lambda q, n=8: [
        {"platform": "youtube", "title": "آموزش هوش مصنوعی برای برنامه نویسی", "channel": "c", "views": 5000,
         "duration": 60, "url": "https://y/1"}])
    with TestClient(app) as c:
        h = {"Authorization": "Bearer " + c.post("/auth/register", json={
            "email": "offline@example.com", "password": "secret123"}).json()["token"]}
        bid = c.post("/brands", json=BRAND, headers=h).json()["id"]
        c.post(f"/brands/{bid}/research", json={}, headers=h)
        _drain()
        rep = c.get(f"/brands/{bid}/research", headers=h).json()[0]
        assert rep["status"] == "ready", rep["error"]
        assert rep["report"]["ran"]["web"] == "search_only"
        assert "هوش مصنوعی" in " ".join(rep["report"]["keywords"])
        assert rep["report"]["top_videos"][0]["url"] == "https://y/1"
        assert rep["report"]["instagram_posts"][0]["code"] == "X1"
        assert rep["report"]["trends"][0]["title"] == "دستیار کدنویسی رایگان"
        ids = [c.post(f"/brands/{bid}/generate", json=b, headers=h).json()["id"] for b in (
            {"post_type": "educational"}, {"post_type": "sales", "template": "sales_offer"},
            {"post_type": "promo", "mode": "carousel", "n_body": 3},
            {"post_type": "video_prompt", "video_style": "pov", "target_seconds": 16})]
        _drain()
        for i in ids:
            p = c.get(f"/posts/{i}", headers=h).json()
            assert p["status"] == "ready", p["error"]
            assert p["content"]["source"] == "offline"
            assert p["content"]["caption"]
        video = c.get(f"/posts/{ids[3]}", headers=h).json()["content"]
        assert len(video["clips"]) == 2 and all(cl["full_prompt"].startswith(video["bible_text"]) for cl in video["clips"])


def test_keywords_prefer_repeated_phrases():
    kws = research._keywords(["قهوه تخصصی خوب", "قهوه تخصصی ارزان", "قهوه تخصصی ایرانی", "دم آوری قهوه"])
    assert kws[0] == "قهوه تخصصی"


def test_sensitive_news_is_not_a_trend():
    from app.models import Brand

    b = Brand(name="x", industry="y", forbidden_topics=["رقبا"], products=[])
    data = {"web": [], "videos": [], "news": [
        {"title": "هشدار پاپ درباره هوش مصنوعی", "snippet": "", "url": "1"},
        {"title": "رقبا ارزان کردند", "snippet": "", "url": "2"},
        {"title": "ابزار جدید هوش مصنوعی", "snippet": "", "url": "3"}]}
    assert [t["title"] for t in research.heuristic_report(b, "", data)["trends"]] == ["ابزار جدید هوش مصنوعی"]


def test_offline_copy_never_starts_with_empty_names_and_skips_fact_templates():
    from app import offline
    from app.models import Brand
    from app.pipeline import pick_template

    b = Brand(name="فروشگاه هوش مصنوعی", industry="هوش مصنوعی", products=[{"name": "", "desc": ""}])
    slots = offline.single_slots(b, "promo", "promo_hero", "", {})
    assert slots["headline"].startswith("فروشگاه هوش مصنوعی")
    assert "artificial intelligence" in offline.image_prompt(b)

    class _DB:  # no previous posts
        def scalars(self, *_a, **_k):
            return []

    assert pick_template(_DB(), "x", "promo") not in ("event_announce", "testimonial")
