"""Deterministic offline responses (LLM_PROVIDER=fake) for tests and UI development."""


def fake_response(system: str, user: str) -> dict:
    common = {
        "caption": "این یک کپشن آزمایشی است.\nبرای مشاوره دایرکت بدید.",
        "hashtags": ["تست", "هشتپا"],
        "alt_text": "تصویر آزمایشی",
        "image_prompt": "a cozy coffee shop counter, warm morning light",
    }
    if "PROMPT PACKAGE" in user:
        return {
            "title": "یک صبح با قهوه", "idea": "ایده‌ی آزمایشی", "total_seconds": 16,
            "bible_text": "A woman in her early 30s with shoulder-length black hair...",
            "keyframe_prompt": "opening frame",
            "clips": [
                {"n": 1, "seconds": 8, "start_state": "A", "action": "pours", "camera": "static",
                 "end_state": "B", "voiceover": "سلام", "caption_text": "سلام"},
                {"n": 2, "seconds": 8, "start_state": "B", "action": "sips", "camera": "push-in",
                 "end_state": "C", "voiceover": "خداحافظ", "caption_text": "پایان"},
            ],
            "music_mood": "warm acoustic", **common,
        }
    if "CAROUSEL" in user:
        return {
            "cover": {"headline": "۳ اشتباه رایج در دم کردن قهوه"},
            "body": [{"headline": f"اشتباه {i}", "body": "توضیح کوتاه و مفید درباره‌ی این اشتباه."}
                     for i in "۱۲۳"],
            "cta": {"headline": "برای انتخاب قهوه‌ی مناسب با ما در تماس باشید", "cta": "دایرکت بدید"},
            **common,
        }
    template = next(c for c in ("edu_list", "news_flash", "promo_hero", "sales_offer") if f'"{c}"' in user)
    slots = {
        "kicker": "خبر تازه", "headline": "قهوه‌ی تازه، صبح بهتر", "body": "متن آزمایشی بدنه.",
        "cta": "همین حالا سفارش بدید", "badge": "ویژه",
        "items": ["آب را جوش نیاورید", "قهوه را تازه آسیاب کنید", "نسبت را رعایت کنید"],
    }
    return {"template": template, "slots": slots, **common}
