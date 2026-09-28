"""Fast static serving for the PWA and media.

- Precompressed files: `x.wasm.gz` next to `x.wasm` (made in the Docker build) is sent when the browser accepts
  gzip, so the 3–7 MB engine/app files travel as ~1–3 MB.
- Caching: engine, fonts and icons are kept by the browser for a week; the app code and index revalidate with
  ETag (a cheap 304 when nothing changed).
- Versioned assets: the app's `flutter_bootstrap.js` is served with `assetBase = "v/<build>/"`, so the engine loads
  fonts, icons and images from `/v/<build>/assets/...`. Every deploy gets new URLs, so a browser can never reuse a
  file cached from an older build (the cause of blank icons), and those files can be cached for a year.
- Thumbnails: `/thumb/<media path>?w=240` returns a small JPEG instead of the 1080px PNG."""

import mimetypes
import os
import re
from pathlib import Path

from fastapi import HTTPException
from fastapi.responses import FileResponse
from starlette.staticfiles import StaticFiles
from starlette.types import Scope

LONG = "public, max-age=604800"
IMMUTABLE = "public, max-age=31536000, immutable"
_VERSIONED = re.compile(r"v/[^/]+/(.+)")
REVALIDATE = "no-cache"
# Only files whose content never changes under the same URL. Not "assets/": the icon font there is tree-shaken
# per build, so a cached copy from an older build lacks newly used icons.
_LONG_PREFIXES = ("canvaskit/", "icons/", "favicon", "brand/")


class FastStatic(StaticFiles):
    def __init__(self, *args, long_cache: bool = False, **kw):
        super().__init__(*args, **kw)
        self.long_cache = long_cache
        self.build_id = _build_id(self.directory) if kw.get("html") else ""

    async def __call__(self, scope, receive, send):
        # After a deploy, the first page load tells the browser to drop its HTTP cache once (via a build cookie),
        # so files cached by an older build (e.g. the icon font) are fetched again. Login data is not touched.
        if not self.build_id or scope["type"] != "http":
            return await super().__call__(scope, receive, send)
        cookie = dict(scope.get("headers") or []).get(b"cookie", b"").decode()
        path = scope.get("path", "")
        is_page = path.endswith(".html") or not os.path.splitext(path)[1]
        stale = is_page and f"pv={self.build_id}" not in cookie
        if stale:  # no 304 for a stale browser: the full page must arrive to carry the header below
            scope = {**scope, "headers": [(k, v) for k, v in scope.get("headers") or []
                                          if k not in (b"if-none-match", b"if-modified-since")]}

        async def send_wrapper(message):
            if stale and message["type"] == "http.response.start":
                headers = list(message.get("headers") or [])
                ctype = dict(headers).get(b"content-type", b"")
                if ctype.startswith(b"text/html"):
                    headers.append((b"clear-site-data", b'"cache"'))
                    headers.append((b"set-cookie", f"pv={self.build_id}; Path=/; Max-Age=31536000; SameSite=Lax".encode()))
                    message = {**message, "headers": headers}
            await send(message)

        return await super().__call__(scope, receive, send_wrapper)

    async def get_response(self, path: str, scope: Scope):
        if self.build_id and path == "flutter_bootstrap.js":
            return self._bootstrap()
        versioned = self.build_id and _VERSIONED.fullmatch(path)
        if versioned:
            resp = await self._file(versioned.group(1), scope)
            resp.headers["Cache-Control"] = IMMUTABLE
            return resp
        return await self._file(path, scope)

    def _bootstrap(self):
        """The Flutter loader script, pointing the engine at this build's versioned asset URLs."""
        from starlette.responses import Response

        path, stat = self.lookup_path("flutter_bootstrap.js")
        if stat is None:
            raise HTTPException(404, "not found")
        text = Path(path).read_text(encoding="utf-8").replace("__ASSET_BASE__", f"v/{self.build_id}/")
        return Response(text, media_type="text/javascript", headers={"Cache-Control": REVALIDATE})

    async def _file(self, path: str, scope: Scope):
        accepts = b"gzip" in dict(scope.get("headers") or []).get(b"accept-encoding", b"")
        if accepts and self.directory and path and not path.endswith("/"):
            # Reuse StaticFiles containment checks, including symlink resolution.
            gz_path, gz_stat = self.lookup_path(path + ".gz")
            gz = Path(gz_path)
            if gz_stat is not None and gz.is_file():
                media = mimetypes.guess_type(path)[0] or "application/octet-stream"
                resp = FileResponse(gz, media_type=media, stat_result=os.stat(gz), headers={"Content-Encoding": "gzip", "Vary": "Accept-Encoding"})
                resp.headers["Cache-Control"] = self._cache(path)
                if_none = dict(scope.get("headers") or []).get(b"if-none-match", b"").decode()
                if if_none and if_none == resp.headers.get("etag"):
                    return self.not_modified_response(resp)
                return resp
        resp = await super().get_response(path, scope)
        resp.headers.setdefault("Cache-Control", self._cache(path))
        return resp

    def not_modified_response(self, resp):
        from starlette.responses import Response

        return Response(status_code=304, headers={k: v for k, v in resp.headers.items()
                                                  if k in ("etag", "cache-control", "vary")})

    def _cache(self, path: str) -> str:
        return LONG if self.long_cache or path.startswith(_LONG_PREFIXES) else REVALIDATE


def _build_id(directory) -> str:
    """Changes on every deploy: newest modification time of the app's top-level files."""
    try:
        return str(max(int(e.stat().st_mtime) for e in os.scandir(directory) if e.is_file()))
    except (OSError, ValueError, TypeError):
        return ""


def thumbnail(media_dir: str, path: str, w: int) -> FileResponse:
    """Small JPEG of a media PNG, cached on disk and rebuilt when the source changes."""
    w = max(80, min(int(w), 1080))
    root = Path(media_dir).resolve()
    src = (root / path).resolve()
    if root not in src.parents or not src.is_file() or src.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
        raise HTTPException(404, "not found")
    mtime = int(src.stat().st_mtime)
    out = root / ".thumbs" / f"{path.replace('/', '_')}.{w}.{mtime}.jpg"
    if not out.is_file():
        from PIL import Image

        out.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(src) as im:
            im = im.convert("RGB")
            im.thumbnail((w, w * 2), Image.LANCZOS)
            tmp = out.with_suffix(f".{os.getpid()}.tmp")
            im.save(tmp, "JPEG", quality=82, optimize=True, progressive=True)
            tmp.replace(out)
    return FileResponse(out, media_type="image/jpeg", headers={"Cache-Control": REVALIDATE})  # file may be re-rendered
