"""Fast static serving for the PWA and media.

- Precompressed files: `x.wasm.gz` next to `x.wasm` (made in the Docker build) is sent when the browser accepts
  gzip, so the 3–7 MB engine/app files travel as ~1–3 MB.
- Caching: engine, fonts and icons are kept by the browser for a week; the app code and index revalidate with
  ETag (a cheap 304 when nothing changed).
- Thumbnails: `/thumb/<media path>?w=240` returns a small JPEG instead of the 1080px PNG."""

import mimetypes
import os
from pathlib import Path

from fastapi import HTTPException
from fastapi.responses import FileResponse
from starlette.staticfiles import StaticFiles
from starlette.types import Scope

LONG = "public, max-age=604800"
REVALIDATE = "no-cache"
# Only files whose content never changes under the same URL. Not "assets/": the icon font there is tree-shaken
# per build, so a cached copy from an older build lacks newly used icons.
_LONG_PREFIXES = ("canvaskit/", "icons/", "favicon", "brand/")


class FastStatic(StaticFiles):
    def __init__(self, *args, long_cache: bool = False, **kw):
        super().__init__(*args, **kw)
        self.long_cache = long_cache

    async def get_response(self, path: str, scope: Scope):
        accepts = b"gzip" in dict(scope.get("headers") or []).get(b"accept-encoding", b"")
        if accepts and self.directory and path and not path.endswith("/"):
            gz = Path(self.directory) / (path + ".gz")
            if gz.is_file():
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
