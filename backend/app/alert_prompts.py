"""Source-bound, reusable news prompt jobs. No fabricated ready fallback."""
import hashlib
import json
from datetime import datetime
from zoneinfo import ZoneInfo
from sqlalchemy import select
from .config import settings
from .models import Post, Brand, MarketAlert, Job
from .weekly_prompts import is_rahboom


def ensure_prompt(db, brand, alert, explicit=False):
    from .worker import enqueue
    signature = hashlib.sha256(json.dumps([alert.title, alert.summary, alert.url], ensure_ascii=False).encode()).hexdigest()
    existing = db.scalar(select(Post).where(Post.brand_id == brand.id,
        Post.content['alert_id'].as_string() == alert.id).order_by(Post.created_at.desc()))
    if existing:
        if existing.status == 'deleted' and not explicit:
            return None
        if explicit and existing.status == 'queued':
            for job in db.scalars(select(Job).where(Job.post_id == existing.id, Job.status == 'queued')):
                job.kind = 'generate'
        if existing.status in ('queued', 'running') or (existing.status not in ('failed', 'deleted') and existing.content.get('alert_signature') == signature):
            return existing
        if not explicit:
            return existing
    purpose = 'trending' if alert.category in ('buzz', 'instagram', 'youtube') else 'news'
    published = alert.published_at.isoformat() if alert.published_at else 'Date unavailable'
    topic = f"""Create a complete Rahboom Google Flow 10-second video prompt: 8-second scene with Raha and Arian speaking concise natural Persian, followed by a silent 2-second logo end card. Include a separate reel cover prompt and caption with the source URL. Preserve the supplied character references and original logo. Explain ONE specific fact from this story; do not substitute a generic AI news-literacy lesson. Do not invent facts, benchmarks, availability, prices or quotes. If the source reports uncertainty, preserve it. Social discoveries are references, not proof of virality.
Title: {alert.title}
Summary: {alert.summary}
Source: {alert.source}
Publication: {published}
URL: {alert.url}"""
    options = {'target_seconds': 10, 'content_label': purpose, 'alert_id': alert.id,
        'alert_signature': signature, 'source_url': alert.url, 'source_title': alert.title, 'source_published': published}
    if existing and existing.status in ('failed', 'deleted'):
        post = existing
        post.status, post.error, post.content, post.topic_hint = 'queued', '', options, topic
    else:
        post = Post(brand_id=brand.id, post_type='video_prompt', mode='video', topic_hint=topic,
            for_date=datetime.now(ZoneInfo(settings.timezone)).date().isoformat(), content=options)
        db.add(post)
        db.flush()
    enqueue(db, post, kind='generate' if explicit else 'alert_auto')
    return post


def prepare_top_alerts(db):
    alerts = list(db.scalars(select(MarketAlert).where(MarketAlert.category.in_(('news', 'pricing')))
        .order_by(MarketAlert.importance.desc(), MarketAlert.published_at.desc().nullslast(), MarketAlert.discovered_at.desc()).limit(3)))
    for brand in db.scalars(select(Brand)):
        if not is_rahboom(brand):
            continue
        for alert in alerts:
            ensure_prompt(db, brand, alert)
    db.commit()
