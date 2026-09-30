import json

from app import admin_price_probe as probe
from app import safe_fetch

WOO_API = json.dumps([{"name": "اکانت ChatGPT Plus", "permalink": "https://shop.example/product/plus/", "is_in_stock": True,
                       "type": "variable", "variations": [1, 2],
                       "prices": {"price": "15000000", "currency_code": "IRR", "currency_minor_unit": 0}}])
HOME = '<html><body class="woocommerce"><a href="/wp-content/x">x</a></body></html>'


class R:
    def __init__(self, status, body, url):
        self.status_code, self._content, self.url, self.headers = status, body.encode(), url, {"server": "nginx"}
        self.text = body


def fake_get(url, timeout=15, connect_timeout=5, **k):
    if "blocked" in url:
        return R(403, "Just a moment...", url)
    if "wc/store/v1/products" in url:
        return R(200, WOO_API, url)
    if url.endswith("/") and url.count("/") == 3:
        return R(200, HOME, url)
    if "blocked" in url:
        return R(403, "Just a moment...", url)
    return R(404, "", url)


def test_probe_site_uses_store_api_and_writes_files(tmp_path, monkeypatch):
    monkeypatch.setattr(safe_fetch, "get", fake_get)
    monkeypatch.setattr(probe, "lookup", lambda c, q: {"status": "not_found", "matches": []})
    row = probe.probe_site("shop.example", ["ChatGPT Plus"], tmp_path)
    assert row["reachable"] and row["platform"] == "woocommerce" and row["store_api"]
    p = row["per_product"][0]
    assert p["best"] == "woo_store_api"
    assert p["strategies"]["woo_store_api"][0]["price"] == 1_500_000  # IRR / 10
    assert (tmp_path / "shop.example" / "requests.json").exists()
    assert "shop.example" in probe.table([row])


def test_probe_flags_blocked_site(tmp_path, monkeypatch):
    monkeypatch.setattr(safe_fetch, "get", fake_get)
    monkeypatch.setattr(probe, "lookup", lambda c, q: {"status": "unreachable", "matches": []})
    row = probe.probe_site("blocked.example", ["Gemini"], tmp_path)
    assert row["blocked"] is True
