"""Single worker loop: claims one job at a time (FOR UPDATE SKIP LOCKED on Postgres).
Concurrency is deliberately 1 — the host is shared and Chromium is the heaviest thing we run."""

import logging
import time
from datetime import datetime, timezone

from sqlalchemy import select

from .db import SessionLocal, init_db
from .models import Brand, Job, Post, Research
from .pipeline import rerender, run_post
from .research import run_research

log = logging.getLogger("worker")
MAX_ATTEMPTS = 2


def enqueue(db, post: Post, kind: str = "generate") -> None:
    db.add(Job(post_id=post.id, kind=kind))


def enqueue_research(db, research: Research) -> None:
    db.add(Job(research_id=research.id, kind="research"))


def _run_research_job(db, job: Job) -> None:
    res = db.get(Research, job.research_id)
    res.status = "running"
    db.commit()
    try:
        res.report = run_research(db.get(Brand, res.brand_id), res.focus)
        res.status, res.error, job.status = "ready", "", "done"
    except Exception as e:  # noqa: BLE001
        log.exception("research %s failed", res.id)
        res.error = str(e)[:2000]
        res.status = job.status = "failed"
    db.commit()


def claim(db) -> Job | None:
    q = select(Job).where(Job.status == "queued").order_by(Job.id).limit(1)
    if db.bind.dialect.name == "postgresql":
        q = q.with_for_update(skip_locked=True)
    job = db.scalars(q).first()
    if job:
        job.status, job.attempts = "running", job.attempts + 1
        db.commit()
    return job


def process_one() -> bool:
    with SessionLocal() as db:
        job = claim(db)
        if not job:
            return False
        if job.kind == "research":
            _run_research_job(db, job)
            return True
        post = db.get(Post, job.post_id)
        post.status = "running"
        db.commit()
        try:
            (rerender if job.kind == "rerender" else run_post)(db, post)
            post.status, post.error, job.status = "ready", "", "done"
        except Exception as e:  # noqa: BLE001 — record any failure on the post
            log.exception("post %s failed", post.id)
            post.error = str(e)[:2000]
            if job.attempts < MAX_ATTEMPTS:
                job.status, post.status = "queued", "queued"
            else:
                job.status, post.status = "failed", "failed"
        post.updated_at = datetime.now(timezone.utc)
        db.commit()
        return True


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    init_db()
    while True:
        if not process_one():
            time.sleep(3)


if __name__ == "__main__":
    main()
