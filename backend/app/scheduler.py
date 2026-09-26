"""Daily batch: every morning, create today's posts for each brand from its weekly plan."""

import logging
from datetime import datetime
from zoneinfo import ZoneInfo

from apscheduler.schedulers.blocking import BlockingScheduler
from sqlalchemy import select

from .config import settings
from .db import SessionLocal, init_db
from .models import Brand, Post
from .worker import enqueue

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


def create_daily_posts(now: datetime | None = None) -> int:
    now = now or datetime.now(ZoneInfo(settings.timezone))
    day, created = now.date().isoformat(), 0
    with SessionLocal() as db:
        for brand in db.scalars(select(Brand)):
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


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    init_db()
    sched = BlockingScheduler(timezone=settings.timezone)
    sched.add_job(create_daily_posts, "cron", hour=settings.daily_run_hour, minute=0,
                  misfire_grace_time=3600, coalesce=True)
    sched.start()


if __name__ == "__main__":
    main()
