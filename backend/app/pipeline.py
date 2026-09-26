"""Turns one queued Post into finished content (JSON + rendered slides)."""

from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import prompts
from .config import settings
from .images import generate_image
from .llm import chat_json
from .models import Brand, Post
from .render import render_html, renderer
from .template_registry import SINGLE_TEMPLATE, TEMPLATES, enforce, violations

def recent_headlines(db: Session, brand_id: str, limit: int = 15) -> list[str]:
    rows = db.scalars(
        select(Post).where(Post.brand_id == brand_id, Post.status.in_(["ready", "approved"]))
        .order_by(Post.created_at.desc()).limit(limit)
    )
    out = []
    for p in rows:
        c = p.content or {}
        h = (c.get("slots") or {}).get("headline") or (c.get("cover") or {}).get("headline") or c.get("title")
        if h:
            out.append(h)
    return out

def _fit(code: str, slots: dict, whole: dict, sys: str) -> dict:
    """One LLM repair round for over-long slots, then hard truncation."""
    errs = violations(code, slots)
    if errs:
        try:
            fixed = chat_json(sys, prompts.repair_prompt(slots, errs), temperature=0.3)
            slots = fixed.get("slots", fixed)
        except Exception:
            pass
    return enforce(code, slots)

def _media(post: Post) -> Path:
    d = Path(settings.media_dir) / "posts" / post.id
    d.mkdir(parents=True, exist_ok=True)
    return d

def _render(post: Post, brand: Brand, code: str, slots: dict, idx: int, image: str | None,
            page: str = "", n: int = 0) -> str:
    d = _media(post)
    html = render_html(code, slots=slots, lang=brand.language, colors=brand.colors,
                       brand_name=brand.name, image=image, page=page, n=n)
    renderer.screenshot(html, d / f"slide_{idx}.html", d / f"slide_{idx}.png")
    return f"posts/{post.id}/slide_{idx}.png"

def _image(post: Post, prompt: str) -> str | None:
    path = generate_image(prompt, _media(post) / "image.png")
    return path.resolve().as_uri() if path else None

def run_post(db: Session, post: Post) -> None:
    brand = db.get(Brand, post.brand_id)
    sys = prompts.system_prompt(brand)
    recent = recent_headlines(db, brand.id)

    if post.post_type == "video_prompt":
        target = int((post.content or {}).get("target_seconds", 24))
        data = chat_json(sys, prompts.video_prompt(brand, post.topic_hint, target))
        clips = data.get("clips", [])
        for c in clips:
            c["full_prompt"] = prompts.assemble_clip_prompt(data["bible_text"], c, c["n"], len(clips))
        data["target_seconds"] = target
        post.content, post.slides = data, []
        return

    if post.mode == "carousel":
        n_body = int((post.content or {}).get("n_body", 4))
        data = chat_json(sys, prompts.carousel_prompt(brand, post.post_type, post.topic_hint, recent, n_body))
        image = _image(post, data.get("image_prompt", ""))
        cover = _fit("car_cover", data["cover"], data, sys)
        bodies = [_fit("car_body", b, data, sys) for b in data["body"]]
        cta = _fit("car_cta", data["cta"], data, sys)
        total = len(bodies) + 2
        slides = [_render(post, brand, "car_cover", cover, 0, image)]
        for i, b in enumerate(bodies, start=1):
            slides.append(_render(post, brand, "car_body", b, i, None, f"{i + 1}/{total}", n=i))
        slides.append(_render(post, brand, "car_cta", cta, total - 1, None))
        data.update(cover=cover, body=bodies, cta=cta)
    else:
        data = chat_json(sys, prompts.single_post_prompt(brand, post.post_type, post.topic_hint, recent))
        code = SINGLE_TEMPLATE[post.post_type]
        data["template"] = code
        data["slots"] = _fit(code, data.get("slots", {}), data, sys)

        image = _image(post, data.get("image_prompt", "")) if TEMPLATES[code]["image"] else None
        slides = [_render(post, brand, code, data["slots"], 0, image)]

    data["hashtags"] = list(dict.fromkeys((data.get("hashtags") or []) + (brand.hashtags or [])))
    post.content, post.slides = data, slides

def rerender(db: Session, post: Post) -> None:
    """After the user edits text in the panel: re-render only, no model calls."""
    brand = db.get(Brand, post.brand_id)
    c = post.content
    img = _media(post) / "image.png"
    image = img.resolve().as_uri() if img.exists() else None
    if post.mode == "carousel":
        total = len(c["body"]) + 2
        slides = [_render(post, brand, "car_cover", c["cover"], 0, image)]
        for i, b in enumerate(c["body"], start=1):
            slides.append(_render(post, brand, "car_body", b, i, None, f"{i + 1}/{total}", n=i))
        slides.append(_render(post, brand, "car_cta", c["cta"], total - 1, None))
    else:
        slides = [_render(post, brand, c["template"], c["slots"], 0, image)]
    post.slides = slides
