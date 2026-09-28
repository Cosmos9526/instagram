import pytest

from app import admin_setup
from app.db import SessionLocal, init_db
from app.models import Brand, CompetitorScan, Job, Post, Research


def test_setup_fills_empty_fields_and_queues_work(monkeypatch):
    init_db()
    monkeypatch.setattr(admin_setup, "analyze_business", lambda w, i: {
        "profile": {"website": w, "instagram": i, "description": "", "audience": "برنامه‌نویس‌ها",
                    "tone": "صمیمی", "cta": "دایرکت بدید", "hashtags": ["هوش_مصنوعی"], "colors": {"primary": "#123456"},
                    "weekly_plan": {"0": ["promo"]}, "products": [{"name": "ChatGPT Plus", "desc": ""}],
                    "forbidden_topics": ["سیاست"], "industry": "هوش مصنوعی"},
        "evidence": ["سایت خوانده شد"]})
    with SessionLocal() as db:
        b = Brand(name="راه بوم تست", industry="هوش مصنوعی", tone="رسمی", products=[{"name": "قدیمی"}])
        db.add(b)
        db.commit()
        r = admin_setup.setup(db, "راه بوم تست", "https://rahboom.com", "rahboomshop", "فروش اکانت", ["parspremium.ir"])
        db.refresh(b)
        assert b.tone == "رسمی"  # owner's value kept
        assert b.description == "فروش اکانت" and b.audience == "برنامه‌نویس‌ها"
        assert [p["name"] for p in b.products] == ["قدیمی", "ChatGPT Plus"]
        assert r["competitors"]["added"] == 1 and r["drafts"] == 3 and r["research"] and r["scan"]
        kinds = [j.kind for j in db.query(Job).order_by(Job.id).all() if j.post_id in {p.id for p in db.query(Post).filter_by(brand_id=b.id)}
                 or j.research_id == r["research"] or j.competitor_scan_id == r["scan"]]
        assert kinds == ["generate"] * 3 + ["research", "compete"]  # drafts first, long scan last
        again = admin_setup.setup(db, "راه بوم تست", "https://rahboom.com", "rahboomshop", "", ["parspremium.ir"], drafts=False)
        assert "research" not in again and "scan" not in again  # nothing queued twice
        assert db.query(CompetitorScan).filter_by(brand_id=b.id).count() == 1
        assert db.query(Research).filter_by(brand_id=b.id).count() == 1
        with pytest.raises(SystemExit):
            admin_setup.setup(db, "نیست", "", "", "", [])
