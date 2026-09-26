"""Offline post generator: used when no text model is reachable. Builds post copy from the brand profile,
its products and the latest research using fixed Persian/English patterns, so a post is never lost."""

import random

from .models import Brand

FA = {
    "educational": {
        "kicker": "نکته‌ی امروز",
        "headline": "{n} نکته درباره‌ی {topic}",
        "items": [
            "قبل از انتخاب {product}، نیاز واقعی‌تان را مشخص کنید",
            "کیفیت را با تجربه‌ی دیگران مقایسه کنید",
            "از متخصص {industry} مشاوره بگیرید",
            "به جزئیات نگهداری و استفاده دقت کنید",
            "{keyword} را جدی بگیرید",
        ],
        "body": "دانستن چند نکته‌ی ساده درباره‌ی {topic} باعث می‌شود انتخاب بهتری داشته باشید.",
    },
    "news": {
        "kicker": "تازه‌ها",
        "headline": "{trend}",
        "body": "این هفته در دنیای {industry} چه خبر است و چه ربطی به شما دارد؟ جزئیات را در کپشن بخوانید.",
    },
    "promo": {
        "headline": "{product}؛ انتخابی که به آن اعتماد می‌کنید",
        "body": "{desc}",
        "cta": "{cta}",
    },
    "sales": {
        "badge": "ویژه",
        "headline": "{product} را همین حالا سفارش دهید",
        "body": "{desc}",
        "cta": "{cta}",
    },
}


def _fill(tpl, ctx):
    if isinstance(tpl, list):
        return [t.format(**ctx) for t in tpl]
    return tpl.format(**ctx)


def context(b: Brand, topic_hint: str, research: dict) -> dict:
    products = b.products or [{"name": b.name, "desc": b.description}]
    p = random.choice(products)
    kws = (research or {}).get("keywords") or [b.industry]
    trends = (research or {}).get("trends") or []
    return {
        "brand": b.name, "industry": b.industry, "product": p.get("name") or b.name,
        "desc": p.get("desc") or b.description or b.industry, "cta": b.cta or "برای اطلاعات بیشتر دایرکت بدهید",
        "keyword": kws[0], "topic": topic_hint or kws[0], "n": "۵",
        "trend": topic_hint or (trends[0]["title"] if trends else f"تازه‌های {b.industry}"),
    }


def single_slots(b: Brand, post_type: str, code: str, topic_hint: str, research: dict) -> dict:
    ctx = context(b, topic_hint, research)
    base = FA.get(post_type, FA["educational"])
    slots = {k: _fill(v, ctx) for k, v in base.items()}
    # generic slots used by other templates
    slots.setdefault("headline", ctx["topic"])
    slots.setdefault("body", FA["educational"]["body"].format(**ctx))
    slots.setdefault("kicker", b.industry[:16])
    slots.setdefault("cta", ctx["cta"])
    slots.setdefault("badge", "ویژه")
    slots.setdefault("items", _fill(FA["educational"]["items"], ctx))
    slots.update({
        "quote": f"{ctx['product']}، انتخاب هوشمندانه برای {ctx['topic']}",
        "author": b.name, "role": b.industry,
        "stat": "۱۰۰٪", "myth": f"{ctx['topic']} فقط برای حرفه‌ای‌هاست",
        "fact": f"با راهنمایی درست، هر کسی می‌تواند از {ctx['product']} بهترین نتیجه را بگیرد.",
        "before": "سردرگمی در انتخاب", "after": f"انتخاب مطمئن با {b.name}",
        "question": f"شما {ctx['topic']} را چطور انتخاب می‌کنید؟", "option_a": "با تحقیق", "option_b": "با توصیه‌ی دوستان",
        "answer": ctx["desc"], "date_text": "به‌زودی", "place": b.name,
    })
    return slots


def caption(b: Brand, research: dict, topic_hint: str) -> tuple[str, list[str]]:
    ctx = context(b, topic_hint, research)
    text = f"{ctx['topic']}\n\n{ctx['desc']}\n\n{ctx['cta']}"
    tags = ((research or {}).get("hashtags") or [])[:10] + [b.industry.replace(" ", "_")]
    return text, tags


def carousel(b: Brand, n_body: int, topic_hint: str, research: dict) -> dict:
    ctx = context(b, topic_hint, research)
    items = _fill(FA["educational"]["items"], ctx)
    body = [{"headline": f"نکته‌ی {i + 1}", "body": items[i % len(items)]} for i in range(n_body)]
    return {
        "cover": {"headline": f"{ctx['topic']}: هر آنچه باید بدانید"},
        "body": body,
        "cta": {"headline": f"برای {ctx['product']} با {b.name} در ارتباط باشید", "cta": ctx["cta"][:26]},
        "image_prompt": "",
    }


def video(b: Brand, target: int, style: dict | None, topic_hint: str, research: dict) -> dict:
    ctx = context(b, topic_hint, research)
    beats = (style or {}).get("beats") or ["establishing shot of the product", "product in use", "happy customer, hold"]
    n = max(1, min(4, round(target / 8)))
    bible = (
        f"A {b.industry} setting for the brand {b.name}. One adult presenter, early 30s, neat dark hair, "
        "wearing a plain navy shirt. Clean modern interior, soft window light from the left, 4500K, gentle contrast. "
        f"The product: {ctx['product']}. 35mm lens at chest height, slow handheld movement, 9:16, photoreal, "
        "natural colors, no text or logos in frame."
    )
    clips = []
    for i in range(n):
        beat = beats[i % len(beats)]
        clips.append({
            "n": i + 1, "seconds": 8, "start_state": "continues from the previous clip's final frame" if i else "opening frame",
            "action": beat, "camera": (style or {}).get("camera", "slow push-in"), "end_state": "near-still hold",
            "voiceover": ctx["desc"] if i == 0 else ctx["cta"], "caption_text": ctx["product"] if i == 0 else b.name,
        })
    return {
        "title": f"ویدیو: {ctx['topic']}", "idea": f"معرفی {ctx['product']} در {n} کلیپ پیوسته",
        "total_seconds": target, "bible_text": bible, "keyframe_prompt": f"{bible} Opening frame.",
        "clips": clips, "music_mood": "warm, modern, 90 bpm",
    }
