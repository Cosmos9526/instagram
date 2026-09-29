"""Slot schema per template. Limits are grapheme counts (ZWNJ not counted)."""

import regex

TEMPLATES: dict[str, dict] = {
    # --- single-slide templates ---
    "edu_tip": {"slots": {"kicker": 18, "headline": 60, "body": 220}, "image": False,
                "name_fa": "نکته‌ی آموزشی", "desc_fa": "یک نکته با تیتر و توضیح", "types": ["educational"]},
    "edu_list": {"slots": {"headline": 55}, "items": (3, 5, 70), "image": False,
                 "name_fa": "لیست شماره‌دار", "desc_fa": "۳ تا ۵ نکته‌ی شماره‌دار", "types": ["educational"]},
    "checklist": {"slots": {"headline": 55}, "items": (3, 6, 50), "image": False,
                  "name_fa": "چک‌لیست", "desc_fa": "کارهایی که باید انجام داد، با تیک", "types": ["educational"]},
    "step_guide": {"slots": {"headline": 55}, "items": (3, 5, 80), "image": False,
                   "name_fa": "راهنمای قدم‌به‌قدم", "desc_fa": "مراحل انجام یک کار روی خط زمانی", "types": ["educational"]},
    "myth_fact": {"slots": {"myth": 90, "fact": 170}, "image": False,
                  "name_fa": "باور غلط / واقعیت", "desc_fa": "یک باور رایج و واقعیتش", "types": ["educational"]},
    "faq": {"slots": {"question": 80, "answer": 230}, "image": False,
            "name_fa": "پرسش و پاسخ", "desc_fa": "جواب یک سؤال پرتکرار مشتری‌ها", "types": ["educational", "sales"]},
    "big_stat": {"slots": {"stat": 8, "headline": 60, "body": 140}, "image": False,
                 "name_fa": "عدد بزرگ", "desc_fa": "یک آمار یا عدد چشم‌گیر با توضیح", "types": ["educational", "news"]},
    "news_flash": {"slots": {"kicker": 16, "headline": 70, "body": 160}, "image": True,
                   "name_fa": "خبر فوری", "desc_fa": "عکس بالا و خبر پایین", "types": ["news"]},
    "event_announce": {"slots": {"kicker": 16, "headline": 60, "date_text": 30, "place": 40, "cta": 32}, "image": True,
                       "auto": False, "name_fa": "اعلام رویداد", "desc_fa": "کارگاه، افتتاحیه یا جشنواره با تاریخ و مکان", "types": ["news", "promo"]},
    "promo_hero": {"slots": {"headline": 55, "body": 110, "cta": 32}, "image": True,
                   "name_fa": "معرفی محصول تمام‌صفحه", "desc_fa": "عکس بزرگ محصول با متن روی آن", "types": ["promo"]},
    "before_after": {"slots": {"headline": 50, "before": 90, "after": 90}, "image": False,
                     "name_fa": "قبل و بعد", "desc_fa": "مقایسه‌ی وضعیت قبل و بعد از محصول", "types": ["promo", "educational"]},
    "testimonial": {"slots": {"quote": 180, "author": 30, "role": 40}, "image": False,
                    "auto": False, "name_fa": "نظر مشتری", "desc_fa": "نقل‌قول یک مشتری با امتیاز", "types": ["promo", "sales"]},
    "quote_card": {"slots": {"quote": 150, "author": 30}, "image": False,
                   "name_fa": "جمله‌ی الهام‌بخش", "desc_fa": "یک جمله‌ی کوتاه و ماندگار", "types": ["promo", "educational"]},
    "question_poll": {"slots": {"question": 80, "option_a": 30, "option_b": 30}, "image": False,
                      "name_fa": "سؤال و نظرسنجی", "desc_fa": "یک سؤال دوگزینه‌ای برای کامنت گرفتن", "types": ["promo", "educational"]},
    "sales_offer": {"slots": {"badge": 12, "headline": 55, "body": 110, "cta": 32}, "image": False,
                    "name_fa": "پیشنهاد فروش", "desc_fa": "تخفیف یا پیشنهاد ویژه با دکمه‌ی خرید", "types": ["sales"]},
    # --- carousel family ---
    "car_cover": {"slots": {"headline": 60}, "image": True, "carousel": True,
                  "name_fa": "کاور کاروسل", "desc_fa": "اسلاید اول با قلاب", "types": []},
    "car_body": {"slots": {"headline": 50, "body": 230}, "image": False, "carousel": True,
                 "name_fa": "اسلاید داخلی کاروسل", "desc_fa": "یک ایده در هر اسلاید", "types": []},
    "car_cta": {"slots": {"headline": 70, "cta": 32}, "image": False, "carousel": True,
                "name_fa": "اسلاید پایانی کاروسل", "desc_fa": "دعوت به اقدام", "types": []},
}

# English catalog labels are UI metadata; Persian generation templates remain unchanged.
_TEMPLATE_EN = {
    "edu_tip": ("Quick tip", "One useful tip with a headline and explanation"),
    "edu_list": ("Numbered list", "Three to five concise points"),
    "checklist": ("Checklist", "Actionable steps with check marks"),
    "step_guide": ("Step-by-step guide", "Walk through a process"),
    "myth_fact": ("Myth vs. fact", "A common belief and the evidence"),
    "faq": ("Question and answer", "Answer a customer question"),
    "big_stat": ("Key statistic", "Highlight a verified number"),
    "news_flash": ("News flash", "An image with a short news update"),
    "event_announce": ("Event announcement", "An event with a date and location"),
    "promo_hero": ("Product showcase", "A product image with a short message"),
    "before_after": ("Before and after", "Compare two states"),
    "testimonial": ("Customer testimonial", "An approved customer quote"),
    "quote_card": ("Quote", "A memorable statement"),
    "question_poll": ("Question or poll", "Start a conversation"),
    "sales_offer": ("Sales offer", "A verified offer and call to action"),
    "car_cover": ("Carousel cover", "An opening slide with a hook"),
    "car_body": ("Carousel body", "One idea per slide"),
    "car_cta": ("Carousel closing slide", "Finish with a call to action"),
}
for _code, (_name, _description) in _TEMPLATE_EN.items():
    TEMPLATES[_code].update(name_en=_name, desc_en=_description)

# Default template per post type; the daily batch rotates through templates_for() for variety.
SINGLE_TEMPLATE = {
    "educational": "edu_list",
    "news": "news_flash",
    "promo": "promo_hero",
    "sales": "sales_offer",
}


def templates_for(post_type: str, auto_only: bool = False) -> list[str]:
    """Templates for a post type. auto_only skips ones that need real facts (event date, customer quote)."""
    return [c for c, s in TEMPLATES.items() if post_type in s["types"] and (s.get("auto", True) or not auto_only)]


ZWNJ = "‌"


def length(text: str) -> int:
    return len(regex.findall(r"\X", (text or "").replace(ZWNJ, "")))


def truncate(text: str, limit: int) -> str:
    if length(text) <= limit:
        return text
    words, out = text.split(), ""
    for w in words:
        cand = f"{out} {w}".strip()
        if length(cand) + 1 > limit:
            break
        out = cand
    return out + "…"


def slot_spec_text(code: str) -> str:
    spec = TEMPLATES[code]
    parts = [f'"{k}": max {v} chars' for k, v in spec["slots"].items()]
    if "items" in spec:
        lo, hi, each = spec["items"]
        parts.append(f'"items": list of {lo}-{hi} strings, each max {each} chars')
    return "; ".join(parts)


def violations(code: str, slots: dict) -> list[str]:
    spec, errs = TEMPLATES[code], []
    for key, lim in spec["slots"].items():
        n = length(slots.get(key, ""))
        if n > lim:
            errs.append(f"{key} {n}/{lim}")
    if "items" in spec:
        lo, hi, each = spec["items"]
        items = slots.get("items") or []
        if not lo <= len(items) <= hi:
            errs.append(f"items count {len(items)} (need {lo}-{hi})")
        errs += [f"items[{i}] {length(t)}/{each}" for i, t in enumerate(items) if length(t) > each]
    return errs


def enforce(code: str, slots: dict) -> dict:
    """Last-resort hard fit after the LLM repair attempt."""
    spec, out = TEMPLATES[code], dict(slots)
    for key, lim in spec["slots"].items():
        out[key] = truncate(out.get(key, "") or "", lim)
    if "items" in spec:
        lo, hi, each = spec["items"]
        out["items"] = [truncate(t, each) for t in (out.get("items") or [])[:hi]]
    return out
