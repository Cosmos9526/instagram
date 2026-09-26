"""Renders the sample slides used by the demo build (flutter build web --dart-define=DEMO=true).
Usage: cd backend && python ../tools/make_demo_slides.py <out_dir>"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from app.render import render_html, renderer  # noqa: E402

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "demo")
COLORS = {"primary": "#6B3E26", "secondary": "#F2C14E", "bg": "#FFF8F0", "text": "#2B1B12"}
BRAND = "کافه نمونه"

SLIDES = {
    "edu_0": ("car_cover", {"headline": "۳ اشتباه رایج که طعم قهوه‌ی صبحت را خراب می‌کند"}, {}),
    "edu_1": ("car_body", {"headline": "آب جوش نریز", "body": "آب در حال جوش قهوه را تلخ و سوخته می‌کند. بعد از جوشیدن یک دقیقه صبر کن تا دما به ۹۲ تا ۹۶ درجه برسد."}, {"page": "۲/۵", "n": 1}),
    "edu_2": ("car_body", {"headline": "قهوه‌ی ازقبل‌آسیاب‌شده", "body": "عطر قهوه چند ساعت بعد از آسیاب شدن از بین می‌رود. دانه را درست قبل از دم کردن آسیاب کن."}, {"page": "۳/۵", "n": 2}),
    "edu_3": ("car_body", {"headline": "نسبت اشتباه آب و قهوه", "body": "برای بیشتر روش‌ها، یک گرم قهوه به ازای ۱۵ تا ۱۷ گرم آب شروع خوبی است. با ترازو دقیق‌تر می‌شود."}, {"page": "۴/۵", "n": 3}),
    "edu_4": ("car_cta", {"headline": "دانه‌ی تازه‌رُست و مشاوره‌ی دم‌آوری رایگان", "cta": "برای سفارش دایرکت بدید"}, {}),
    "sales_0": ("sales_offer", {"badge": "۲۰٪", "headline": "تخفیف دانه‌ی اسپشیالتی تا پایان هفته", "body": "هر بسته‌ی ۲۵۰ گرمی، تازه‌رُست همین هفته", "cta": "سفارش در دایرکت"}, {}),
    "news_0": ("news_flash", {"kicker": "تازه‌ها", "headline": "دانه‌ی جدید اتیوپی رسید", "body": "طعم‌یادداشت‌ها: توت‌فرنگی، گل یاس و شکلات تلخ. از امروز در کافه و برای سفارش آنلاین."}, {}),
    "promo_0": ("promo_hero", {"headline": "صبح‌ها با یک فنجان واقعی شروع کن", "body": "قهوه‌ی اسپشیالتی، دم‌آوری دستی، فضای آرام", "cta": "آدرس در بیو"}, {}),
}

OUT.mkdir(parents=True, exist_ok=True)
for name, (code, slots, extra) in SLIDES.items():
    html = render_html(code, slots=slots, lang="fa", colors=COLORS, brand_name=BRAND, **extra)
    renderer.screenshot(html, OUT / f"{name}.html", OUT / f"{name}.png")
    (OUT / f"{name}.html").unlink()
renderer.close()
print("rendered", len(SLIDES), "slides into", OUT)
