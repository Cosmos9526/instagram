"""Daily batch: every morning, create today's posts for each brand from its weekly plan."""

import logging
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

from apscheduler.schedulers.blocking import BlockingScheduler
from sqlalchemy import select

from .config import settings
from .db import SessionLocal, init_db
from .models import Brand, Post, Research
from .worker import enqueue, enqueue_research

log = logging.getLogger("scheduler")

# Default plan if a brand has none: Python weekday numbers (0=Monday).
DEFAULT_PLAN = {
    "5": ["educational:carousel"],  # Saturday
    "6": ["news"],                  # Sunday
    "0": ["promo"],                 # Monday
    "1": ["educational"],           # Tuesday
    "2": ["sales"],                 # Wednesday
    "3": ["video_prompt"],          # Thursday
    "4": [],                        # Friday
}


def parse_entry(entry: str) -> tuple[str, str]:
    post_type, _, mode = entry.partition(":")
    if post_type == "video_prompt":
        return post_type, "video"
    return post_type, mode or "single"


def _refresh_research(db, brand: Brand) -> None:
    """Queue fresh market research before today's posts when the last one is stale.
    Jobs run in order, so today's posts are written with the new research."""
    last = db.scalar(select(Research.created_at).where(Research.brand_id == brand.id).order_by(Research.created_at.desc()))
    if last and last.tzinfo is None:
        last = last.replace(tzinfo=timezone.utc)
    host = (urlparse(brand.website or "").hostname or "").removeprefix("www.")
    # News and fast-trend inputs for Rahboom are daily inventory. Twenty hours
    # keeps the morning run fresh without queueing duplicates after a restart.
    max_age = timedelta(hours=20) if host == "rahboom.com" else timedelta(days=settings.research_max_age_days)
    if last and datetime.now(timezone.utc) - last < max_age:
        return
    res = Research(brand_id=brand.id)
    db.add(res)
    db.flush()
    enqueue_research(db, res)


def create_daily_posts(now: datetime | None = None) -> int:
    now = now or datetime.now(ZoneInfo(settings.timezone))
    day, created = now.date().isoformat(), 0
    with SessionLocal() as db:
        for brand in db.scalars(select(Brand)):
            # Refresh research independently of content creation. A prepared
            # weekly post must not prevent today's news/trend radar from updating.
            _refresh_research(db, brand)
            from .weekly_prompts import is_rahboom, prepare_week
            if is_rahboom(brand):
                # Keep the rolling seven-day plan filled independently of news jobs.
                prepare_week(db, brand, now.date())
                continue
            exists = db.scalar(select(Post.id).where(Post.brand_id == brand.id, Post.for_date == day))
            if exists:
                continue
            plan = brand.weekly_plan or DEFAULT_PLAN
            for entry in plan.get(str(now.weekday()), []):
                post_type, mode = parse_entry(entry)
                post = Post(brand_id=brand.id, post_type=post_type, mode=mode, for_date=day)
                db.add(post)
                db.flush()
                enqueue(db, post)
                created += 1
        db.commit()
    log.info("daily batch %s: %d posts queued", day, created)
    return created


def refresh_market_alerts() -> int:
    """Small keyless scan; independent from the heavier daily research job."""
    from .market_alerts import refresh
    with SessionLocal() as db:
        added = refresh(db)
        from .alert_prompts import prepare_top_alerts
        prepare_top_alerts(db)
        return added


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    init_db()
    sched = BlockingScheduler(timezone=settings.timezone)
    sched.add_job(create_daily_posts, "cron", hour=settings.daily_run_hour, minute=0,
                  misfire_grace_time=3600, coalesce=True)
    sched.add_job(refresh_market_alerts, "interval", hours=1,
                  next_run_time=datetime.now(ZoneInfo(settings.timezone)),
                  misfire_grace_time=1800, coalesce=True, max_instances=1)
    sched.start()


if __name__ == "__main__":
    main()
