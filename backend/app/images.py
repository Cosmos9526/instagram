"""Background/hero image generation. Text is never drawn by the image model.

Providers: pollinations (free, no key; default), cloudflare (Workers AI Flux), none (brand gradient).
Any failure returns None and the template falls back to its brand-colour background."""

import base64
import io
import logging
import random
from pathlib import Path
from urllib.parse import quote

import httpx

from .config import settings

log = logging.getLogger("images")
NEGATIVE = "no text, no letters, no words, no logos, no watermark, no signage"


def _pollinations(prompt: str, out: Path) -> Path | None:
    from PIL import Image, ImageFilter

    url = f"https://image.pollinations.ai/prompt/{quote(prompt + '. ' + NEGATIVE)}"
    resp = httpx.get(url, params={"width": 1080, "height": 1200, "nologo": "true", "seed": random.randint(1, 10**6)},
                     timeout=120, follow_redirects=True)
    resp.raise_for_status()
    img = Image.open(io.BytesIO(resp.content)).convert("RGB")
    w, h = img.size
    img = img.crop((0, 0, w, int(h * 0.9)))  # the free tier stamps a small mark in the bottom corner
    if img.width < 1080:  # free tier returns ~730px: upscale properly and sharpen instead of letting CSS stretch it
        img = img.resize((1080, round(img.height * 1080 / img.width)), Image.LANCZOS)
        img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=80, threshold=2))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG")
    return out


def _cloudflare(prompt: str, out: Path) -> Path | None:
    url = f"https://api.cloudflare.com/client/v4/accounts/{settings.cf_account_id}/ai/run/{settings.cf_image_model}"
    resp = httpx.post(url, headers={"Authorization": f"Bearer {settings.cf_api_token}"},
                      json={"prompt": f"{prompt}. {NEGATIVE}", "steps": 8}, timeout=120)
    resp.raise_for_status()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(base64.b64decode(resp.json()["result"]["image"]))
    return out


def generate_image(prompt: str, out: Path) -> Path | None:
    """Returns the saved path, or None (template then uses its brand background)."""
    if not prompt or settings.image_provider == "none":
        return None
    try:
        if settings.image_provider == "cloudflare":
            return _cloudflare(prompt, out)
        try:
            return _pollinations(prompt, out)
        except Exception as e:  # noqa: BLE001 — free tier is flaky: one retry with a short prompt
            log.info("image retry after: %s", e)
            return _pollinations(prompt.split(",")[0] + ", photograph", out)
    except Exception as e:  # noqa: BLE001 — images are optional
        log.warning("image generation failed: %s", e)
        return None
