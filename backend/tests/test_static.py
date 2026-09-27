import gzip
import os

from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image

from app.static import FastStatic, thumbnail


def test_precompressed_and_cache(tmp_path):
    (tmp_path / "canvaskit").mkdir()
    (tmp_path / "main.dart.wasm").write_bytes(b"\0asm" + b"x" * 5000)
    (tmp_path / "main.dart.wasm.gz").write_bytes(gzip.compress((tmp_path / "main.dart.wasm").read_bytes()))
    (tmp_path / "canvaskit" / "a.js").write_text("1")
    (tmp_path / "assets" / "fonts").mkdir(parents=True)
    (tmp_path / "assets" / "fonts" / "MaterialIcons-Regular.otf").write_bytes(b"font")
    app = FastAPI()
    app.mount("/", FastStatic(directory=tmp_path, html=True))
    c = TestClient(app)
    r = c.get("/main.dart.wasm", headers={"Accept-Encoding": "gzip"})
    assert r.headers["content-encoding"] == "gzip" and r.headers["content-type"] == "application/wasm"
    assert r.content.startswith(b"\0asm") and r.headers["cache-control"] == "no-cache"
    assert c.get("/main.dart.wasm", headers={"Accept-Encoding": "gzip", "If-None-Match": r.headers["etag"]}).status_code == 304
    assert "max-age" in c.get("/canvaskit/a.js").headers["cache-control"]
    # the icon font is tree-shaken per build: must revalidate, or new icons go missing after a deploy
    assert c.get("/assets/fonts/MaterialIcons-Regular.otf").headers["cache-control"] == "no-cache"


def test_thumbnail(tmp_path):
    (tmp_path / "posts" / "p").mkdir(parents=True)
    Image.new("RGB", (1080, 1350), "teal").save(tmp_path / "posts/p/slide_0.png")
    r = thumbnail(str(tmp_path), "posts/p/slide_0.png", 200)
    with Image.open(r.path) as im:
        assert im.format == "JPEG" and im.width == 200


def test_new_build_clears_browser_cache_once(tmp_path):
    (tmp_path / "index.html").write_text("<html></html>")
    (tmp_path / "main.dart.js").write_text("1")
    app = FastAPI()
    app.mount("/", FastStatic(directory=tmp_path, html=True))
    c = TestClient(app)
    r = c.get("/")
    assert r.headers["clear-site-data"] == '"cache"' and "pv=" in r.headers["set-cookie"]
    assert "clear-site-data" not in c.get("/main.dart.js").headers  # only on the page itself
    old = r.headers["set-cookie"].split(";")[0]
    assert "clear-site-data" not in c.get("/", headers={"Cookie": old}).headers  # cookie matches this build
    os.utime(tmp_path / "main.dart.js", (2_000_000_000, 2_000_000_000))  # a new deploy
    app2 = FastAPI()
    app2.mount("/", FastStatic(directory=tmp_path, html=True))
    assert TestClient(app2).get("/", headers={"Cookie": old}).headers["clear-site-data"] == '"cache"'
