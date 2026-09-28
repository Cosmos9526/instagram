"""Admin helper: fill a project end to end from the server shell, as the owner's operator.

    docker compose -p postyar exec -T api python -m app.admin_setup --brand "فروشگاه هوش مصنوعی" \\
        --website https://rahboom.com --instagram rahboomshop

1. Reads the business website/Instagram (on the server, which can reach them) and fills the empty parts
   of the profile: description, products, audience, tone, CTA, colors, hashtags, weekly plan.
   Fields the owner already filled are kept. Nothing is invented: products come from the site; if the
   site gives none, the owner's own description is used and prices are left out.
2. Adds the competitor list (no duplicates) and queues a competitor scan.
3. Queues a market research run.
4. Queues starter drafts (carousel, video package, single post) for review in the app.
Queue order: drafts first (fast), then research, then the long competitor scan."""

import argparse
from datetime import datetime
from zoneinfo import ZoneInfo

from sqlalchemy import select

from . import admin_seed
from .business_analyzer import analyze_business
from .config import settings
from .db import SessionLocal, init_db
from .models import Brand, CompetitorScan, Post, Research
from .worker import enqueue, enqueue_competitor_scan, enqueue_research

# Starter drafts; topics only (the model writes the copy with the brand profile and research).
STARTER = [
    {"post_type": "educational", "mode": "carousel",
     "topic_hint": "قبل از خرید اشتراک هوش مصنوعی این ۴ سؤال را بپرس: برای چه کاری؟ نوع دسترسی؟ مدت و پشتیبانی؟ تناسب با بودجه؟"},
    {"post_type": "video_prompt", "mode": "video", "target_seconds": 16,
     "topic_hint": "هدف ویدیو: آموزشی. اول کار را انتخاب کن، بعد ابزار را؛ کاربری که بین چند ابزار هوش مصنوعی مردد است"},
    {"post_type": "promo", "mode": "single",
     "topic_hint": "کدام اشتراک هوش مصنوعی برای کار تو مناسب است؟ راهنمای انتخاب بر اساس نوشتن، طراحی، برنامه‌نویسی و ویدیو"},
]


def _fill(b: Brand, profile: dict, owner_description: str) -> list[str]:
    changed = []

    def put(field, value):
        if value and not getattr(b, field):
            setattr(b, field, value)
            changed.append(field)

    put("website", profile.get("website"))
    put("instagram", profile.get("instagram"))
    put("telegram", profile.get("telegram"))
    put("description", profile.get("description") or owner_description)
    put("audience", profile.get("audience"))
    put("tone", profile.get("tone"))
    put("cta", profile.get("cta"))
    put("hashtags", profile.get("hashtags"))
    put("forbidden_topics", profile.get("forbidden_topics"))
    put("colors", profile.get("colors"))
    put("weekly_plan", profile.get("weekly_plan"))
    site_products = profile.get("products") or []
    if site_products and len(b.products or []) <= 1:  # keep a real catalog the owner entered
        known = {p.get("name") for p in b.products or []}
        b.products = (b.products or []) + [p for p in site_products if p.get("name") not in known]
        changed.append("products")
    if b.industry in ("", None):
        b.industry = profile.get("industry") or b.industry
        changed.append("industry")
    return changed


def setup(db, brand_name: str, website: str, instagram: str, owner_description: str, sites: list[str],
          drafts: bool = True) -> dict:
    brands = db.scalars(select(Brand).where(Brand.name == brand_name)).all()
    if len(brands) != 1:
        names = ", ".join(db.scalars(select(Brand.name)).all())
        raise SystemExit(f"need exactly one project named {brand_name!r} (found {len(brands)}). Projects: {names}")
    b = brands[0]
    report = {"project": b.id}

    analysis = analyze_business(website, instagram)
    report["read"] = analysis.get("evidence", [])
    report["filled"] = _fill(b, analysis["profile"], owner_description)
    db.commit()

    seeded = admin_seed.seed(db, brand_name, sites, scan=False)[b.id]
    report["competitors"] = seeded

    today = datetime.now(ZoneInfo(settings.timezone)).date().isoformat()
    if drafts:
        for d in STARTER:
            opts = {"n_body": 4, "target_seconds": d.get("target_seconds", 24)}
            p = Post(brand_id=b.id, post_type=d["post_type"], mode=d["mode"], topic_hint=d["topic_hint"],
                     content=opts, for_date=today)
            db.add(p)
            db.flush()
            enqueue(db, p)
        report["drafts"] = len(STARTER)

    busy = lambda model: db.scalar(select(model.id).where(model.brand_id == b.id,  # noqa: E731
                                                          model.status.in_(["queued", "running"])))
    if not busy(Research):
        r = Research(brand_id=b.id, focus="فروش اکانت و اشتراک ابزارهای هوش مصنوعی")
        db.add(r)
        db.flush()
        enqueue_research(db, r)
        report["research"] = r.id
    if not busy(CompetitorScan):
        s = CompetitorScan(brand_id=b.id)
        db.add(s)
        db.flush()
        enqueue_competitor_scan(db, s)
        report["scan"] = s.id
    db.commit()
    return report


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--brand", required=True, help="project name exactly as shown in the app")
    ap.add_argument("--website", default="https://rahboom.com")
    ap.add_argument("--instagram", default="rahboomshop")
    ap.add_argument("--description", default="فروش اکانت و اشتراک ابزارهای هوش مصنوعی")
    ap.add_argument("--no-drafts", action="store_true")
    ap.add_argument("sites", nargs="*")
    a = ap.parse_args()
    init_db()
    with SessionLocal() as db:
        r = setup(db, a.brand, a.website, a.instagram, a.description, a.sites or admin_seed.AI_ACCOUNT_SELLERS,
                  drafts=not a.no_drafts)
    print("project:", r["project"])
    for line in r["read"]:
        print("read:", line)
    print("filled:", ", ".join(r["filled"]) or "(nothing empty)")
    print(f"competitors: +{r['competitors']['added']} (total {r['competitors']['total']})")
    print("queued:", ", ".join(k for k in ("drafts", "research", "scan") if r.get(k)))
    print("Open the app in ~2 minutes for drafts; research ~5 min; competitor scan up to ~12 min.")
