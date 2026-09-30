"""Turns one queued Post into finished content (JSON + rendered slides)."""

from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import offline, prompts
from .competitors import competitors_brief
from .config import settings
from .images import generate_image
from .llm import LLMError, chat_json
from .video_styles import STYLE_BY_ID
from .models import Brand, CompetitorScan, Post, Research
from .research import research_brief
from .render import render_html, renderer
from .template_registry import SINGLE_TEMPLATE, TEMPLATES, enforce, templates_for, violations

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

def latest_research(db: Session, brand_id: str) -> Research | None:
    return db.scalars(
        select(Research).where(Research.brand_id == brand_id, Research.status == "ready")
        .order_by(Research.created_at.desc()).limit(1)
    ).first()

def latest_competitor_scan(db: Session, brand_id: str) -> CompetitorScan | None:
    return db.scalars(
        select(CompetitorScan).where(CompetitorScan.brand_id == brand_id, CompetitorScan.status == "ready")
        .order_by(CompetitorScan.created_at.desc()).limit(1)
    ).first()


def pick_template(db: Session, brand_id: str, post_type: str) -> str:
    """Least-recently-used template for this post type, so daily posts don't all look the same."""
    options = templates_for(post_type, auto_only=True) or [SINGLE_TEMPLATE[post_type]]
    used = db.scalars(
        select(Post).where(Post.brand_id == brand_id, Post.post_type == post_type, Post.mode == "single")
        .order_by(Post.created_at.desc()).limit(len(options) * 2)
    )
    recent = [(p.content or {}).get("template") for p in used]  # newest first
    unused = [c for c in options if c not in recent]
    if unused:
        return unused[0]
    return max(options, key=recent.index)  # the one used longest ago


def _fit(code: str, slots: dict, whole: dict, sys: str) -> dict:
    """One LLM repair round for over-long slots, then hard truncation."""
    errs = violations(code, slots)
    if errs and whole.get("source") != "offline":
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
    if settings.prompt_only:
        from .prompt_package import generate_package
        post.content = generate_package(brand, post)
        post.slides = []
        return
    sys = prompts.system_prompt(brand)
    recent = recent_headlines(db, brand.id)
    res = latest_research(db, brand.id)
    research = research_brief(res.report) if res else ""
    scan = latest_competitor_scan(db, brand.id)
    if scan:
        comp_brief = competitors_brief(scan.report)
        if comp_brief:
            research = f"{research}\n\n{comp_brief}" if research else comp_brief
    report = res.report if res else {}
    opts = post.content or {}

    def ask(user_prompt: str, fallback):
        """Model first; if no model is reachable, the offline generator (the post is marked source=offline)."""
        try:
            return chat_json(sys, user_prompt)
        except LLMError as e:
            data = fallback()
            data["source"] = "offline"
            data["model_error"] = str(e)[:300]
            return data

    if post.post_type == "video_prompt":
        target = int(opts.get("target_seconds", 24))
        style_id = opts.get("video_style", "")
        data = ask(
            prompts.video_prompt(brand, post.topic_hint, target, style_id, research),
            lambda: offline.video(brand, target, STYLE_BY_ID.get(style_id), post.topic_hint, report),
        )
        data["video_style"] = style_id
        clips = data.get("clips", [])
        for c in clips:
            c["full_prompt"] = prompts.assemble_clip_prompt(data["bible_text"], c, c["n"], len(clips))
        data["target_seconds"] = target
        if data.get("source") == "offline":
            data["caption"], data["hashtags"] = offline.caption(brand, report, post.topic_hint)
        _keep_inputs(opts, data)
        post.content, post.slides = data, []
        return

    if post.mode == "carousel":
        n_body = int(opts.get("n_body", 4))
        data = ask(
            prompts.carousel_prompt(brand, post.post_type, post.topic_hint, recent, n_body, research),
            lambda: offline.carousel(brand, n_body, post.topic_hint, report),
        )
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
        code = opts.get("template") if opts.get("template") in TEMPLATES else pick_template(db, brand.id, post.post_type)
        data = ask(
            prompts.single_post_prompt(brand, post.post_type, post.topic_hint, recent, code, research),
            lambda: {"slots": offline.single_slots(brand, post.post_type, code, post.topic_hint, report),
                     "image_prompt": offline.image_prompt(brand)},
        )
        if data.get("source") == "offline" and not opts.get("template") and code != SINGLE_TEMPLATE[post.post_type]:
            # without a model, stick to the core template of the type (the others need specific facts)
            code = SINGLE_TEMPLATE[post.post_type]
            data["slots"] = offline.single_slots(brand, post.post_type, code, post.topic_hint, report)
        data["template"] = code
        data["slots"] = _fit(code, data.get("slots", {}), data, sys)

        image = _image(post, data.get("image_prompt", "")) if TEMPLATES[code]["image"] else None
        slides = [_render(post, brand, code, data["slots"], 0, image)]

    if data.get("source") == "offline" and not data.get("caption"):
        data["caption"], data["hashtags"] = offline.caption(brand, report, post.topic_hint)
    data["hashtags"] = list(dict.fromkeys((data.get("hashtags") or []) + (brand.hashtags or [])))
    _keep_inputs(opts, data)
    post.content, post.slides = data, slides


def _keep_inputs(opts: dict, data: dict) -> None:
    """Generation inputs stay in the content so "regenerate" repeats the same request."""
    for key in ("n_body", "target_seconds", "video_style", "content_label"):
        if key in opts:
            data.setdefault(key, opts[key])

def rerender(db: Session, post: Post) -> None:
    """After the user edits text in the panel: re-render only, no model calls."""
    if post.content.get("output_kind") == "prompt_package":
        post.slides = []
        return
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
