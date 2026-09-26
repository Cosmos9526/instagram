"""Slot schema per template. Limits are grapheme counts (ZWNJ not counted)."""

import regex

TEMPLATES: dict[str, dict] = {
    "edu_tip": {"slots": {"kicker": 18, "headline": 60, "body": 220}, "image": False},
    "edu_list": {"slots": {"headline": 55}, "items": (3, 5, 70), "image": False},
    "news_flash": {"slots": {"kicker": 16, "headline": 70, "body": 160}, "image": True},
    "promo_hero": {"slots": {"headline": 55, "body": 110, "cta": 24}, "image": True},
    "sales_offer": {"slots": {"badge": 12, "headline": 55, "body": 110, "cta": 24}, "image": False},
    "car_cover": {"slots": {"headline": 60}, "image": True},
    "car_body": {"slots": {"headline": 50, "body": 230}, "image": False},
    "car_cta": {"slots": {"headline": 70, "cta": 26}, "image": False},
}

# Which template each post type uses in single mode.
SINGLE_TEMPLATE = {
    "educational": "edu_list",
    "news": "news_flash",
    "promo": "promo_hero",
    "sales": "sales_offer",
}

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
