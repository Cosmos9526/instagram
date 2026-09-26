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
