"""Public AI social discovery. Engagement snapshots are not proof of virality."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import logging
import re
from urllib.parse import urlparse, parse_qs

from .search_sources import parse_instagram_result, _age_hours, _num

log = logging.getLogger(__name__)
QUERIES = (
    'AI tools artificial intelligence', 'Claude ChatGPT Gemini AI',
    'AI agents coding video generation', 'هوش مصنوعی ابزار آموزش',
)
AI = re.compile(r'\b(ai|chatgpt|claude|gemini|midjourney|openai|anthropic|veo|sora|llm|jev)\b|artificial intelligence|هوش مصنوعی|چت جی پی تی|کلاد|جمینای', re.I)


def youtube_url(value: str) -> str | None:
    parsed = urlparse(value)
    host = (parsed.hostname or '').lower()
    parts = parsed.path.strip('/').split('/')
    video_id = None
    if host == 'youtu.be':
        video_id = parts[0]
    elif host in ('youtube.com', 'www.youtube.com', 'm.youtube.com'):
        if parsed.path == '/watch':
            video_id = (parse_qs(parsed.query).get('v') or [None])[0]
        elif len(parts) == 2 and parts[0] in ('shorts', 'embed'):
            video_id = parts[1]
    if video_id and re.fullmatch(r'[\w-]{11}', video_id):
        return f'https://www.youtube.com/watch?v={video_id}'
    return None


def normalize(platform: str, row: dict, now: datetime) -> dict | None:
    title = row.get('title') or ''
    text = title + ' ' + (row.get('body') or row.get('description') or '')
    if not AI.search(title if platform == 'youtube' else text):
        return None
    published = None
    if platform == 'instagram':
        post = parse_instagram_result(row)
        if not post:
            return None
        url, title = post['url'], post['title']
        age = post['age_hours']
        if age is not None:
            published = now - timedelta(hours=age)
        metrics = []
        for key in ('likes', 'comments'):
            if post[key] > 0:
                metrics.append(f"{post[key]:,} {key}")
        count = post['engagement']
        channel = post['channel']
    else:
        url = youtube_url(row.get('content') or row.get('url') or '')
        if not url:
            return None
        try:
            published = datetime.fromisoformat((row.get('published') or '').replace('Z', '+00:00'))
            if published.tzinfo is None:
                published = published.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
        try:
            count = max(0, int((row.get('statistics') or {}).get('viewCount') or 0))
        except (ValueError, TypeError):
            count = 0
        metrics = [f'{count:,} views'] if count else []
        channel = row.get('uploader') or ''
    # Search date filters are not a reliable publication timestamp. Unknown dates
    # remain explicitly unverified candidates, never "last 24h" results.
    if published and not now - timedelta(hours=72) <= published <= now:
        return None
    evidence = ', '.join(metrics) or 'Engagement unavailable'
    freshness = 'Search-reported publication within 72 hours' if published else 'Publication date unverified'
    summary = f'{channel}. {evidence}. {freshness}. Public search snapshot; growth and virality are not verified.'
    return {'title': title[:400], 'summary': summary, 'source': ('YouTube' if platform == 'youtube' else 'Instagram') + ' · public search',
            'url': url, 'category': platform, 'published_at': published,
            'importance': 3 if published and count else 2 if published else 1,
            '_engagement': count}


def _search(job: tuple[str, str]) -> list[dict]:
    from ddgs import DDGS
    platform, query = job
    try:
        search = DDGS(timeout=8)
        if platform == 'youtube':
            try:
                rows = search.videos(query, max_results=12, timelimit='w')
            except Exception:
                rows = []
            # Video search is often unavailable on a server IP. Public web
            # indexing supplies a second independent discovery route.
            try:
                web_rows = search.text('site:youtube.com/watch ' + query, max_results=12, timelimit='w')
            except Exception:
                web_rows = []
            for result in web_rows:
                snippet = (result.get('title') or '') + ' ' + (result.get('body') or '')
                age = _age_hours(snippet)
                views = re.search(r'([\d.,]+\s*[KkMm]?)\s*views?\b', snippet)
                rows.append({**result, 'content': result.get('href'),
                             'published': (datetime.now(timezone.utc) - timedelta(hours=age)).isoformat() if age is not None else '',
                             'statistics': {'viewCount': _num(views.group(1)) if views else 0}})
        else:
            rows = search.text('site:instagram.com/reel/ ' + query, max_results=12, timelimit='w')
        now = datetime.now(timezone.utc)
        return [item for row in rows if (item := normalize(platform, row, now))]
    except Exception as exc:
        log.warning('social discovery %s failed: %s', platform, exc)
        return []


def collect() -> list[dict]:
    jobs = [(platform, query) for platform in ('instagram', 'youtube') for query in QUERIES]
    unique = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        for rows in pool.map(_search, jobs):
            for row in rows:
                old = unique.get(row['url'])
                if not old or (row['importance'], row['_engagement']) > (old['importance'], old['_engagement']):
                    unique[row['url']] = row
    ranked = sorted(unique.values(), key=lambda r: (r['importance'], r['_engagement']), reverse=True)
    return [r for platform in ('instagram', 'youtube') for r in
            [r for r in ranked if r['category'] == platform][:15]]
