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
    report = radar.collect()
    assert report["keyword_bank_count"] == len(radar.keyword_bank())
    assert report["window"] == "5–24 hours"
    assert report["news"][0]["source_type"] == "news"
    assert report["videos"][0]["source_type"] == "youtube"
    assert report["search_signals"][0]["source"] == "Google Trends"
