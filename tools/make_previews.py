"""Renders a small preview PNG for every slide template into backend/app/previews/ (served at /previews).
Usage: cd backend && python ../tools/make_previews.py"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from playwright.sync_api import sync_playwright  # noqa: E402

from app.config import settings  # noqa: E402
from app.fake_llm import fake_response  # noqa: E402
from app.render import AUTOFIT_JS, render_html  # noqa: E402
from app.template_registry import TEMPLATES  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "backend" / "app" / "previews"
COLORS = {"primary": "#0E7C66", "secondary": "#F4B400", "bg": "#FFFFFF", "text": "#16241F"}
SAMPLE = fake_response("", 'Fill the "x" template')["slots"] | {
    "headline": "تیتر نمونه‌ی این قالب", "body": "اینجا متن اصلی پست قرار می‌گیرد؛ کوتاه، مفید و خوانا.",
    "kicker": "برچسب", "cta": "دایرکت بدید", "badge": "۲۰٪",
    "items": ["نکته‌ی اول", "نکته‌ی دوم", "نکته‌ی سوم", "نکته‌ی چهارم"],
}

OUT.mkdir(parents=True, exist_ok=True)
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=settings.chromium_path or None,
                                 args=["--allow-file-access-from-files"])
    page = browser.new_page(viewport={"width": 1080, "height": 1350}, device_scale_factor=0.3)
    for code in TEMPLATES:
        html = render_html(code, slots=SAMPLE, lang="fa", colors=COLORS, brand_name="نام برند",
                           page="۲/۵" if code == "car_body" else "", n=1)
        tmp = OUT / f"{code}.html"
        tmp.write_text(html, encoding="utf-8")
        page.goto(tmp.as_uri(), wait_until="networkidle")
        page.evaluate("document.fonts.ready")
        page.evaluate(AUTOFIT_JS)
        page.screenshot(path=str(OUT / f"{code}.png"))
        tmp.unlink()
    browser.close()
print("previews:", len(TEMPLATES))
