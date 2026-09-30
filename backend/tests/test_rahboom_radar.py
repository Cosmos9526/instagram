from datetime import date

from app import rahboom_radar as radar


def test_keyword_bank_is_large_mixed_and_daily_rotation_is_bounded():
    bank = radar.keyword_bank()
    assert 200 <= len(bank) <= 300
    assert "پایان نامه با هوش مصنوعی" in bank
    assert "GitHub Copilot tutorial" in bank
    assert "آموزش ساخت ویدیو با هوش مصنوعی" in bank
    first = radar.daily_queries(date(2026, 9, 30))
    next_day = radar.daily_queries(date(2026, 10, 1))
    assert len(first) == 18 and first != next_day
    assert first[:2] == ["اخبار هوش مصنوعی", "AI news"]


def test_collect_labels_sources_and_freshness(monkeypatch):
    monkeypatch.setattr(radar, "news_search", lambda q, *a: [
        {"title": f"news {q}", "url": f"https://news.test/{q}", "date": "2026-09-30", "source": "Test"}
    ])
    monkeypatch.setattr(radar, "video_search", lambda q, *a: [
        {"title": f"video {q}", "url": f"https://youtube.test/{q}", "channel": "Test", "views": 10}
    ])
    monkeypatch.setattr(radar, "google_suggest", lambda q, *a: [q + " today"])
    monkeypatch.setattr(radar, "google_rising", lambda *a, **k: [{"query": "Claude trend", "growth": "Breakout"}])
    monkeypatch.setattr(radar, "google_trending_now", lambda *a, **k: [
        {"query": "AI search", "search_volume": "2000+", "search_volume_min": 2000,
         "source": "Google Trends Trending Now"}
    ])
    report = radar.collect()
    assert report["keyword_bank_count"] == len(radar.keyword_bank())
    assert report["window"] == "5–24 hours"
    assert report["news"][0]["source_type"] == "news"
    assert report["videos"][0]["source_type"] == "youtube"
    assert report["search_signals"][0]["source"] == "Google Trends Trending Now"
    assert report["search_signals"][0]["search_volume_min"] == 2000


def test_youtube_feed_fallback_is_used(monkeypatch):
    monkeypatch.setattr(radar, "news_search", lambda *a, **k: [])
    monkeypatch.setattr(radar, "video_search", lambda *a, **k: [])
    monkeypatch.setattr(radar, "google_suggest", lambda *a, **k: [])
    monkeypatch.setattr(radar, "google_rising", lambda *a, **k: [])
    monkeypatch.setattr(radar, "google_trending_now", lambda *a, **k: [])
    monkeypatch.setattr(radar, "youtube_channel_feeds", lambda: [{
        "title": "Official update", "url": "https://youtube.test/1",
        "channel": "Official", "views": 0, "source_type": "youtube_feed",
    }])
    assert radar.collect()["videos"][0]["source_type"] == "youtube_feed"
