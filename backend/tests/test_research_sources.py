import httpx

from app import research
from app.config import settings


class _Resp:
    def __init__(self, data):
        self._data = data

    def raise_for_status(self):
        pass

    def json(self):
        return self._data


def test_youtube_top_videos_sorted_by_views(monkeypatch):
    monkeypatch.setattr(settings, "youtube_api_key", "k")

    def fake_get(url, params, timeout):
        if url.endswith("/search"):
            return _Resp({"items": [{"id": {"videoId": "a"}}, {"id": {"videoId": "b"}}]})
        return _Resp({"items": [
            {"id": vid, "snippet": {"title": vid, "channelTitle": "c", "publishedAt": "2026-09-20T00:00:00Z",
                                     "thumbnails": {}},
             "statistics": {"viewCount": views}, "contentDetails": {"duration": "PT30S"}}
            for vid, views in (("a", "10"), ("b", "500"))
        ]})

    monkeypatch.setattr(httpx, "get", fake_get)
    videos = research.youtube_top_videos(["قهوه"], "fa")
    assert [v["title"] for v in videos] == ["b", "a"]
    assert videos[0]["url"] == "https://www.youtube.com/watch?v=b"


def test_sources_off_without_keys(monkeypatch):
    monkeypatch.setattr(settings, "youtube_api_key", "")
    monkeypatch.setattr(settings, "apify_token", "")
    assert research.youtube_top_videos(["x"], "fa") == []
    assert research.instagram_top_posts(["x"]) == []


def test_relevance_rejects_shared_sales_and_plan_words():
    seeds = ['فروش اکانت و اشتراک ابزارهای هوش مصنوعی', 'کلود مکس']
    for title in ['خرید آیفون پرو مکس', 'فروش اکانت پابجی مکس', 'خرید اشتراک بازی']:
        assert not research._relevant(title, seeds)
    assert research._relevant('راهنمای کلود برای برنامه نویسی', seeds)
    assert research._relevant('ابزارهای هوش مصنوعی برای طراحی', seeds)
    assert not research._relevant('chair sale', ['hair'])
    assert research._relevant('hair care', ['hair'])


def test_instagram_search_filters_unrelated_max_results(monkeypatch):
    import ddgs
    from app import search_sources as ss

    class Search:
        def text(self, *args, **kwargs):
            return [
                {'href': 'https://www.instagram.com/reel/Phone123/', 'title': 'فروش آیفون پرو مکس', 'body': '2 days ago'},
                {'href': 'https://www.instagram.com/reel/Claude123/', 'title': 'آموزش کلود مکس', 'body': '2 days ago'},
            ]
    monkeypatch.setattr(ddgs, 'DDGS', Search)
    monkeypatch.setattr(ss.time, 'sleep', lambda _: None)
    result = ss.instagram_via_search(['کلود مکس'], must=['فروش اکانت', 'کلود مکس'])
    assert [p['code'] for p in result['posts']] == ['Claude123']
