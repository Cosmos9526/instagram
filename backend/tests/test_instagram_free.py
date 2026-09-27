import time

from app import instagram_free as ig

NOW = int(time.time())
TAG_JSON = {"data": {"top": {"sections": [{"layout_content": {"medias": [
    {"media": {"code": "AAA111", "taken_at": NOW - 3600, "media_type": 2, "user": {"username": "clinic_a"},
               "caption": {"text": "کاشت مو بدون تراشیدن"}, "like_count": 900, "comment_count": 40, "play_count": 120000}},
    {"media": {"code": "OLD999", "taken_at": NOW - 10 * 86400, "media_type": 1, "user": {"username": "clinic_b"},
               "caption": {"text": "old"}, "like_count": 5000, "comment_count": 1}},
]}}]}, "recent": {"sections": [{"layout_content": {"medias": [
    {"media": {"code": "BBB222", "taken_at": NOW - 7200, "media_type": 8, "user": {"username": "clinic_c"},
               "caption": {"text": "مراقبت بعد از کاشت"}, "like_count": 50, "comment_count": 2}},
]}}]}}}
PROFILE_JSON = {"data": {"user": {"edge_owner_to_timeline_media": {"edges": [
    {"node": {"shortcode": "CCC333", "taken_at_timestamp": NOW - 100, "is_video": True, "video_view_count": 4000,
              "edge_liked_by": {"count": 70}, "edge_media_to_comment": {"count": 3},
              "edge_media_to_caption": {"edges": [{"node": {"text": "reel"}}]}}},
]}}}}


def test_collect_parses_filters_and_ranks(monkeypatch):
    monkeypatch.setattr(ig.time, "sleep", lambda s: None)
    monkeypatch.setattr(ig, "_get", lambda url, params: TAG_JSON if "tags" in url else PROFILE_JSON)
    res = ig.collect(["کاشت مو"], ["@competitor"], days=3)
    codes = [p["code"] for p in res["posts"]]
    assert codes == ["AAA111", "CCC333", "BBB222"]  # ranked by engagement, 10-day-old post dropped
    top = res["posts"][0]
    assert top["views"] == 120000 and top["type"] == "video" and top["channel"] == "clinic_a"
    assert top["url"] == "https://www.instagram.com/p/AAA111/"


def test_blocked_returns_empty_with_reason(monkeypatch):
    class R:
        status_code = 429

    monkeypatch.setattr(ig.httpx, "get", lambda *a, **k: R())
    ig.last_errors.clear()
    assert ig.hashtag_posts("x") == []
    assert "429" in ig.last_errors[0]
