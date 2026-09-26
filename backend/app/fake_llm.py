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
    import re

    m = re.search(r'Fill the "(\w+)" template', user)
    template = m.group(1) if m else "edu_list"
    slots = {
        "quote": "قهوه‌ی خوب، روز خوب می‌سازد", "author": "سارا، مشتری همیشگی", "role": "طراح گرافیک",
        "stat": "۸۵٪", "myth": "قهوه‌ی تیره‌تر قوی‌تر است", "fact": "رنگ تیره فقط نشانه‌ی رُست بیشتر است.",
        "before": "قهوه‌ی تلخ و بی‌عطر", "after": "فنجانی خوش‌عطر و متعادل",
        "question": "قهوه‌ی صبحت رو چطور دوست داری؟", "option_a": "اسپرسو", "option_b": "لاته",
        "answer": "بله، همه‌ی دانه‌ها همین هفته رُست شده‌اند.", "date_text": "پنجشنبه ساعت ۱۷", "place": "کافه نمونه",
        "kicker": "خبر تازه", "headline": "قهوه‌ی تازه، صبح بهتر", "body": "متن آزمایشی بدنه.",
        "cta": "همین حالا سفارش بدید", "badge": "ویژه",
        "items": ["آب را جوش نیاورید", "قهوه را تازه آسیاب کنید", "نسبت را رعایت کنید"],
    }
    return {"template": template, "slots": slots, **common}


def fake_research() -> dict:
    return {
        "summary": "بازار قهوه‌ی تخصصی در حال رشد است و مخاطب به آموزش دم‌آوری خانگی علاقه دارد.",
        "business_facts": ["در نقشه‌ها با امتیاز ۴٫۷ ثبت شده است (example.com)"],
        "competitors": [{"name": "کافه رقیب", "what_they_post": "ریلز لاته‌آرت", "gap_we_can_fill": "آموزش خانگی"}],
        "audience_interests": ["دم‌آوری خانگی", "قهوه‌ی سرد"],
        "trends": [{"title": "قهوه‌ی سرد تابستانی", "why_now": "گرمای هوا", "angle_for_brand": "آموزش کلدبرو",
                    "post_type": "educational"}],
        "keywords": ["قهوه تخصصی", "کلدبرو", "دم آوری قهوه"],
        "hashtags": ["قهوه", "کلدبرو", "قهوه_تخصصی"],
        "content_ideas": [{"title": "۳ روش کلدبرو", "post_type": "educational", "format": "carousel"}],
    }
