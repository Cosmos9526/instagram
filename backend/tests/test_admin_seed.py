import pytest

from app import admin_seed
from app.db import SessionLocal, init_db
from app.models import Brand, CompetitorScan, Job


def test_seed_adds_competitors_once_and_queues_one_scan():
    init_db()
    with SessionLocal() as db:
        b = Brand(name="فروشگاه تست سید", industry="هوش مصنوعی", competitors=["", "rival_ig", {"website": "https://parspremium.ir"}])
        db.add(b)
        db.commit()
        r = admin_seed.seed(db, "فروشگاه تست سید", ["parspremium.ir", "https://www.cafearz.com/", "dicardo.com"])[b.id]
        assert r["added"] == 2 and r["total"] == 4 and r["scan"]
        again = admin_seed.seed(db, "فروشگاه تست سید", ["cafearz.com"])[b.id]
        assert again["added"] == 0 and "scan" not in again  # scan already queued
        db.refresh(b)
        assert sorted(c["website"] for c in b.competitors if c["website"]) == [
            "https://cafearz.com", "https://dicardo.com", "https://parspremium.ir"]
        assert db.query(CompetitorScan).filter_by(brand_id=b.id).count() == 1
        assert db.query(Job).filter_by(competitor_scan_id=r["scan"], kind="compete").count() == 1
        with pytest.raises(SystemExit):
            admin_seed.seed(db, "no such project", [])
