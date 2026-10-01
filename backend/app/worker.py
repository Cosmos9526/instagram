"""Single worker loop: claims one job at a time (FOR UPDATE SKIP LOCKED on Postgres).
Concurrency is deliberately 1 — the host is shared and Chromium is the heaviest thing we run."""

import logging
import time
from datetime import datetime, timezone

from sqlalchemy import select, case

from .competitors import normalize_competitors, run_competitor_scan, write_back_handles
from .db import SessionLocal, init_db
from .models import Brand, CompetitorScan, Job, Post, Research
from .pipeline import rerender, run_post
from .research import run_research

log = logging.getLogger("worker")
MAX_ATTEMPTS = 2


class _ScanCancelled(Exception):
    pass


def enqueue(db, post: Post, kind: str = "generate") -> None:
    db.add(Job(post_id=post.id, kind=kind))


def enqueue_research(db, research: Research) -> None:
    db.add(Job(research_id=research.id, kind="research"))


def enqueue_competitor_scan(db, scan: CompetitorScan) -> None:
    db.add(Job(competitor_scan_id=scan.id, kind="compete"))


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


def _run_competitor_scan_job(db, job: Job) -> None:
    scan = db.get(CompetitorScan, job.competitor_scan_id)
    if scan.status == "cancelled":
        job.status = "cancelled"
        db.commit()
        return
    scan.status = "running"
    db.commit()
    try:
        brand = db.get(Brand, scan.brand_id)
        comps = normalize_competitors(brand.competitors)
        if scan.only:
            comps = [c for c in comps if c["id"] in scan.only]

        if (scan.report or {}).get("kind") == "price_search":
            from .price_search import run_price_search, preserve_verified, EXTRACTOR_VERSION
            query = scan.report["query"]
            previous_reports=[s.report or {} for s in db.scalars(select(CompetitorScan).where(
                CompetitorScan.brand_id == scan.brand_id, CompetitorScan.id != scan.id,
                CompetitorScan.status == 'ready').order_by(CompetitorScan.created_at.desc()).limit(10))]
            def price_progress(rows, total):
                db.refresh(scan)
                if scan.status == "cancelled":
                    raise _ScanCancelled()
                scan.report = {"kind": "price_search", "extractor_version": EXTRACTOR_VERSION, "query": query, "results": preserve_verified(rows,previous_reports,query), "progress": {"done": len(rows), "total": total}}
                db.commit()
            scan.report = run_price_search(comps, query, price_progress)
            db.refresh(scan)
            if scan.status == "cancelled":
                raise _ScanCancelled()
            scan.report = scan.report | {'results':preserve_verified(scan.report['results'],previous_reports,query)}
            scan.status, scan.error, job.status = "ready", "", "done"
            db.commit()
            return

        def _progress(done: int, total: int) -> None:
            scan.report = {**(scan.report or {}), "progress": {"done": done, "total": total}}
            db.commit()

        scan.report = run_competitor_scan(brand, comps, on_progress=_progress)
        write_back_handles(brand, scan.report)
        scan.status, scan.error, job.status = "ready", "", "done"
    except _ScanCancelled:
        scan.status = job.status = "cancelled"
        scan.error = scan.error or "Replaced by a newer price search"
    except Exception as e:  # noqa: BLE001
        log.exception("competitor scan %s failed", scan.id)
        scan.error = str(e)[:2000]
        scan.status = job.status = "failed"
    scan.updated_at = datetime.now(timezone.utc)
    db.commit()


def _prune_scans(db, brand_id: str, keep: int = 10) -> None:
    old = db.scalars(
        select(CompetitorScan).where(CompetitorScan.brand_id == brand_id)
        .order_by(CompetitorScan.created_at.desc()).offset(keep)
    )
    for scan in old:
        db.delete(scan)
    db.commit()


def claim(db) -> Job | None:
    q = select(Job).where(Job.status == "queued").order_by(
        case((Job.kind == "generate", 0), (Job.kind == "alert_auto", 2), else_=1), Job.id).limit(1)
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
        if job.kind == "compete":
            _run_competitor_scan_job(db, job)
            _prune_scans(db, db.get(CompetitorScan, job.competitor_scan_id).brand_id)
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
