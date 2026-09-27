"""Admin helper: add competitors to a project and start a scan, from the server shell.

    docker compose -p postyar exec -T api python -m app.admin_seed --brand "فروشگاه هوش مصنوعی" parspremium.ir ...
    (no sites given = the built-in list of Iranian AI-account sellers)

Existing competitors are kept; the same website or Instagram handle is never added twice."""

import argparse

from sqlalchemy import select

from .competitors import normalize_competitors, parse_competitors_text
from .db import SessionLocal, init_db
from .models import Brand, CompetitorScan
from .worker import enqueue_competitor_scan

AI_ACCOUNT_SELLERS = [
    "parspremium.ir", "cafearz.com", "dicardo.com", "numberland.ir", "license-market.ir", "asangem.com",
    "account4all.ir", "g1verify.ir", "kharidaccount.ir", "licenseyar.ir", "premium24.ir", "codinocard.ir",
    "majazite.com", "giftpin.ir", "khanehlicense.ir", "iranicard.ir",
]


def _key(c: dict) -> str:
    site = c["website"].lower().replace("https://", "").replace("http://", "").removeprefix("www.").strip("/")
    if site:
        return site
    return f"@{c['instagram'].lower()}" if c["instagram"] else f"t:{c['telegram'].lower()}"


def seed(db, brand_name: str, sites: list[str], scan: bool = True) -> dict:
    brands = db.scalars(select(Brand).where(Brand.name == brand_name)).all()
    if not brands:
        names = ", ".join(db.scalars(select(Brand.name)).all())
        raise SystemExit(f"no project named {brand_name!r}. Projects: {names or '(none)'}")
    out = {}
    for b in brands:
        current = normalize_competitors(b.competitors)
        seen = {_key(c) for c in current}
        added = [c for c in parse_competitors_text("\n".join(sites)) if _key(c) not in seen]
        b.competitors = current + added
        out[b.id] = {"added": len(added), "total": len(b.competitors)}
        busy = db.scalar(select(CompetitorScan.id).where(
            CompetitorScan.brand_id == b.id, CompetitorScan.status.in_(["queued", "running"])))
        if scan and not busy:
            s = CompetitorScan(brand_id=b.id)
            db.add(s)
            db.flush()
            enqueue_competitor_scan(db, s)
            out[b.id]["scan"] = s.id
    db.commit()
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--brand", required=True, help="project name exactly as shown in the app")
    ap.add_argument("--no-scan", action="store_true")
    ap.add_argument("sites", nargs="*")
    a = ap.parse_args()
    init_db()
    with SessionLocal() as db:
        for bid, r in seed(db, a.brand, a.sites or AI_ACCOUNT_SELLERS, scan=not a.no_scan).items():
            print(f"project {bid}: +{r['added']} competitors (total {r['total']})"
                  + (f", scan {r['scan']} queued" if r.get("scan") else ", no new scan (one is already running)"
                     if not a.no_scan else ""))
