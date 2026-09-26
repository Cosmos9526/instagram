"""Slide renderer: Jinja2 HTML templates -> PNG via one headless Chromium (one page at a time)."""

import threading
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

TEMPLATE_DIR = Path(__file__).parent / "templates"
FONT_DIR = (Path(__file__).parent / "fonts").resolve().as_uri()
FA_DIGITS = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")

env = Environment(loader=FileSystemLoader(TEMPLATE_DIR), autoescape=select_autoescape(["html"]))

# Shrinks font-size of every .fit element until its content fits its max-height.
AUTOFIT_JS = """
() => {
  for (const el of document.querySelectorAll('.fit')) {
    const limit = parseFloat(getComputedStyle(el).maxHeight);
    if (!limit) continue;
    let size = parseFloat(getComputedStyle(el).fontSize);
    const floor = size * 0.55;
    el.style.maxHeight = 'none';
    while (el.scrollHeight > limit && size > floor) {
      size -= 2;
      el.style.fontSize = size + 'px';
      for (const li of el.querySelectorAll('li')) li.style.fontSize = size + 'px';
    }
    el.style.maxHeight = limit + 'px';
  }
}
"""


def to_lang_digits(value, lang: str) -> str:
    s = str(value)
    return s.translate(FA_DIGITS) if lang == "fa" else s


def render_html(code: str, *, slots: dict, lang: str, colors: dict, brand_name: str,
                image: str | None = None, page: str = "", n: int = 0) -> str:
    return env.get_template(f"{code}.html").render(
        s=slots, lang=lang, colors=colors or {}, brand_name=brand_name, image=image,
        page=to_lang_digits(page, lang), n=n, font_dir=FONT_DIR, digits=lambda v: to_lang_digits(v, lang),
    )


class Renderer:
    """Holds a single Chromium; restarts it every `recycle_after` renders to cap memory growth."""

    def __init__(self, recycle_after: int = 200):
        self._lock = threading.Lock()
        self._pw = self._browser = None
        self._count = 0
        self._recycle_after = recycle_after

    def _ensure(self):
        if self._browser and self._count < self._recycle_after:
            return
        self.close()
        from playwright.sync_api import sync_playwright

        from .config import settings

        self._pw = sync_playwright().start()
        self._browser = self._pw.chromium.launch(
            executable_path=settings.chromium_path or None,
            args=["--disable-dev-shm-usage", "--no-sandbox", "--disable-gpu",
                  "--allow-file-access-from-files"]
        )
        self._count = 0

    def screenshot(self, html: str, html_path: Path, out_png: Path) -> Path:
        with self._lock:
            self._ensure()
            html_path.parent.mkdir(parents=True, exist_ok=True)
            html_path.write_text(html, encoding="utf-8")
            page = self._browser.new_page(viewport={"width": 1080, "height": 1350})
            try:
                page.goto(html_path.resolve().as_uri(), wait_until="networkidle", timeout=30000)
                page.evaluate("document.fonts.ready")
                page.evaluate(AUTOFIT_JS)
                page.screenshot(path=str(out_png), type="png")
            finally:
                page.close()
                self._count += 1
            return out_png

    def close(self):
        if self._browser:
            self._browser.close()
        if self._pw:
            self._pw.stop()
        self._pw = self._browser = None


renderer = Renderer()
