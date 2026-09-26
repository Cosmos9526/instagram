"""Background/hero image generation. Text is never drawn by the image model."""

import base64
from pathlib import Path

import httpx

from .config import settings

NEGATIVE = "no text, no letters, no words, no logos, no watermark, no signage"


def generate_image(prompt: str, out: Path) -> Path | None:
    """Returns the saved path, or None when images are disabled (template falls back to a gradient)."""
    if settings.image_provider != "cloudflare" or not prompt:
        return None
    url = (
        f"https://api.cloudflare.com/client/v4/accounts/{settings.cf_account_id}"
        f"/ai/run/{settings.cf_image_model}"
    )
    resp = httpx.post(
        url,
        headers={"Authorization": f"Bearer {settings.cf_api_token}"},
        json={"prompt": f"{prompt}. {NEGATIVE}", "steps": 8},
        timeout=120,
    )
    resp.raise_for_status()
    image_b64 = resp.json()["result"]["image"]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(base64.b64decode(image_b64))
    return out
