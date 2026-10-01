from datetime import datetime, timezone
from app.social_trends import normalize, youtube_url, collect

NOW = datetime(2026, 10, 1, 12, tzinfo=timezone.utc)


def test_social_filters_stale_and_unrelated_results():
    row = {'title': 'New AI video tools', 'content': 'https://youtu.be/abcdefghijk',
           'published': '2026-10-01T08:00:00Z', 'statistics': {'viewCount': 9000}}
    found = normalize('youtube', row, NOW)
    assert found['category'] == 'youtube'
    assert '9,000 views' in found['summary']
    assert found['importance'] == 3
    assert normalize('youtube', {**row, 'title': 'Football highlights', 'description': 'Watch other AI tools videos'}, NOW) is None
    assert normalize('youtube', {**row, 'published': '2025-10-01'}, NOW) is None
    assert normalize('youtube', {**row, 'published': '2027-10-01'}, NOW) is None
    assert normalize('youtube', {**row, 'content': 'https://youtube.com.evil.test/watch?v=abcdefghijk'}, NOW) is None


def test_unknown_metrics_or_date_never_claim_virality():
    row = {'title': 'ChatGPT video tutorial', 'href': 'https://www.instagram.com/reel/ABC123/',
           'body': 'ChatGPT AI workflows'}
    found = normalize('instagram', row, NOW)
    assert found['published_at'] is None
    assert found['importance'] == 1
    assert 'Publication date unverified' in found['summary']
    assert 'Engagement unavailable' in found['summary']
    row['body'] += ' 5 hours ago · 12K likes 30 comments'
    found = normalize('instagram', row, NOW)
    assert found['published_at'].hour == 7
    assert '12,000 likes' in found['summary']
    assert 'virality are not verified' in found['summary']


def test_canonical_video_urls():
    assert youtube_url('https://youtube.com/shorts/abcdefghijk?feature=share') == 'https://www.youtube.com/watch?v=abcdefghijk'
    assert youtube_url('https://youtube.com/@channel') is None


def test_collection_deduplicates_platforms(monkeypatch):
    from app import social_trends
    def fake_search(job):
        platform, _ = job
        return [{'url': platform, 'category': platform, 'importance': 2, '_engagement': 2}]
    monkeypatch.setattr(social_trends, '_search', fake_search)
    assert len(collect()) == 2


def test_video_search_failure_uses_public_web_fallback(monkeypatch):
    import ddgs
    from app.social_trends import _search
    class Search:
        def __init__(self, **kwargs): pass
        def videos(self, *args, **kwargs): raise RuntimeError('unavailable')
        def text(self, *args, **kwargs):
            return [{'title': 'AI tools tutorial', 'body': '2 hours ago 12K views',
                     'href': 'https://youtube.com/watch?v=abcdefghijk'}]
    monkeypatch.setattr(ddgs, 'DDGS', Search)
    result = _search(('youtube', 'AI tools'))
    assert len(result) == 1
    assert '12,000 views' in result[0]['summary']
