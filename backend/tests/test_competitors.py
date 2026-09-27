import socket
import time
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

from app import competitors as comp
from app import safe_fetch
from app.main import app
from app.worker import process_one

FIXTURES = Path(__file__).parent / "fixtures" / "competitors"


def _read(name: str) -> str:
    return (FIXTURES / name).read_text()


# ---------- normalisation ----------


def test_blank_competitors_are_dropped():
    items = comp.normalize_competitors(["", "  ", "@", {"name": ""}, {"notes": "x"}, None, {"website": "https://a.ir"}])
    assert [c["website"] for c in items] == ["https://a.ir"]


def test_legacy_string_competitors_become_objects():
    items = comp.normalize_competitors(["rival_shop", "@another_one", {"instagram": "third", "name": "Third"}])
    assert items[0]["instagram"] == "rival_shop" and items[0]["website"] == "" and "id" in items[0]
    assert items[1]["instagram"] == "another_one"
    assert items[2]["name"] == "Third" and items[2]["instagram"] == "third"
    assert comp.competitor_handles(items) == ["rival_shop", "another_one", "third"]


# ---------- product alias normalisation ----------


@pytest.mark.parametrize("name,key", [
    ("اکانت ChatGPT Plus یک ماهه", "chatgpt_plus"),
    ("چت جی پی تی پلاس", "chatgpt_plus"),
    ("اشتراک Midjourney سه ماهه", "midjourney"),
    ("Gemini Advanced", "gemini"),
    ("یک محصول ناشناخته", None),
])
def test_canonicalize_product(name, key):
    assert comp.canonicalize_product(name) == key


def test_detect_duration():
    assert comp.detect_duration("اکانت ChatGPT Plus یک ماهه") == "1m"
    assert comp.detect_duration("اشتراک Midjourney سه ماهه") == "3m"
    assert comp.detect_duration("بدون مدت") == ""


def test_parse_price_persian_digits_and_rial():
    assert comp.parse_price("۱٬۵۰۰٬۰۰۰ تومان") == 1_500_000
    assert comp.parse_price("15,000,000 ریال") == 1_500_000
    assert comp.parse_price("") is None


def test_parse_price_decimal_fraction_is_not_thousands():
    assert comp.parse_price("125000.00") == 125_000
    assert comp.parse_price("125000.00", "IRR") == 12_500  # decimal Rial amount -> Toman


def test_parse_price_range():
    lo, hi = comp.parse_price_range("۱۰۰٬۰۰۰ – ۲۵۰٬۰۰۰ تومان")
    assert (lo, hi) == (100_000, 250_000)
    lo, hi = comp.parse_price_range("۱۵۰٬۰۰۰ تومان")
    assert (lo, hi) == (150_000, 150_000)


def test_canonicalize_product_zwnj_and_arabic_letters():
    assert comp.canonicalize_product("چت‌جی‌پی‌تی پلاس") == "chatgpt_plus"  # ZWNJ between words
    assert comp.canonicalize_product("كلود") == "claude"  # Arabic ك/ي forms


def test_canonicalize_product_generic_and_new_aliases():
    assert comp.canonicalize_product("خرید اکانت ChatGPT") == "chatgpt"
    assert comp.canonicalize_product("سوپر گروک") == "grok"
    assert comp.canonicalize_product("Copilot") == "copilot"
    assert comp.canonicalize_product("Canva Pro") == "canva"
    assert comp.canonicalize_product("لایسنس ویندوز اورجینال") == "windows"
    # plans still win over the generic key
    assert comp.canonicalize_product("ChatGPT Plus یک ماهه") == "chatgpt_plus"


# ---------- HTML extraction against fixtures ----------


def test_extract_products_woocommerce():
    products = comp.extract_products(_read("woo_product.html"))
    assert products[0]["name"] == "اکانت ChatGPT Plus یک ماهه"
    assert products[0]["price"] == 1_500_000
    assert products[0]["regular_price"] == 1_900_000
    assert products[0]["in_stock"] is True


def test_extract_products_jsonld():
    products = comp.extract_products(_read("jsonld_product.html"))
    assert products[0]["name"] == "اشتراک Midjourney سه ماهه"
    assert products[0]["price"] == 2_400_000
    assert products[0]["in_stock"] is True


def test_extract_products_variable_product_variations():
    products = comp.extract_products(_read("variable_product.html"))
    assert len(products) == 2
    one_month = next(p for p in products if p["duration"] == "1m")
    three_month = next(p for p in products if p["duration"] == "3m")
    assert one_month["price"] == 990_000
    assert three_month["price"] == 2_600_000 and three_month["regular_price"] == 2_900_000


def test_jsonld_decimal_rial_price_and_sanity_bounds():
    html = """<html><head><title>t</title><script type="application/ld+json">
    {"@type": "Product", "name": "اکانت تست", "offers": {"price": "125000.00", "priceCurrency": "IRR"}}
    </script></head><body></body></html>"""
    products = comp.extract_products(html)
    assert products[0]["price"] == 12_500


def test_price_sanity_bounds_are_enforced_and_reported():
    errors: list[str] = []
    products = comp._apply_price_sanity(
        [{"name": "قیمت نجومی", "price": 999_000_000, "price_max": 999_000_000},
         {"name": "قیمت معقول", "price": 100_000, "price_max": 100_000}],
        errors, "https://rival.example/product/1/",
    )
    assert products[0]["price"] is None and products[1]["price"] == 100_000
    assert errors and "unrealistic price" in errors[0]


def test_detect_socials_excludes_accounts_login_and_picks_frequent():
    html = """<html><body>
    <a href="https://instagram.com/accounts/login/">login</a>
    <a href="https://instagram.com/example.shop">us</a>
    <a href="https://instagram.com/example.shop">us again</a>
    <a href="https://t.me/joinchat/abc123">join</a>
    <a href="https://t.me/example_shop">telegram</a>
    </body></html>"""
    socials = comp.detect_socials(html)
    assert socials["instagram"] == "example.shop"
    assert socials["telegram"] == "example_shop"


def test_homepage_signals_and_socials():
    html = _read("homepage.html")
    socials = comp.detect_socials(html)
    signals = comp.detect_signals(html)
    assert socials == {"instagram": "example.shop", "telegram": "example_shop", "whatsapp": ""}
    assert signals["enamad"] is True
    assert signals["guarantee"] is True
    assert signals["instant_delivery"] is True
    assert signals["support_hours"]
    assert comp.detect_discounts(html)
    assert comp.detect_blog(html)


# ---------- /parse endpoint ----------


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c


_n = 0


def _user(c) -> dict:
    global _n
    _n += 1
    r = c.post("/auth/register", json={"email": f"comp{_n}@example.com", "password": "secret123", "name": "تست"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _brand(c, h) -> str:
    body = {"name": "رهبوم", "industry": "هوش مصنوعی", "language": "fa",
            "products": [{"name": "ChatGPT Plus"}], "audience": "دانشجوها", "tone": "صمیمی"}
    return c.post("/brands", json=body, headers=h).json()["id"]


def test_parse_endpoint(client):
    h = _user(client)
    bid = _brand(client, h)
    text = "parspremium.ir\ninstagram.com/cafearz\n@dicardo_shop\nt.me/numberland_ir\n"
    r = client.post(f"/brands/{bid}/competitors/parse", json={"text": text}, headers=h)
    assert r.status_code == 200
    items = r.json()
    assert len(items) == 4
    assert any(i["website"] == "https://parspremium.ir" for i in items)
    assert any(i["instagram"] == "cafearz" for i in items)
    assert any(i["instagram"] == "dicardo_shop" for i in items)
    assert any(i["telegram"] == "numberland_ir" for i in items)


def test_bulk_replace_competitors_normalises(client):
    h = _user(client)
    bid = _brand(client, h)
    body = {"competitors": [{"name": "Rival", "website": "https://rival.example", "instagram": "rival_ig"}]}
    r = client.put(f"/brands/{bid}/competitors", json=body, headers=h)
    assert r.status_code == 200
    saved = r.json()
    assert saved[0]["name"] == "Rival" and saved[0]["id"]
    assert client.get(f"/brands/{bid}/competitors", headers=h).json() == saved


# ---------- SSRF guard ----------


@pytest.mark.parametrize("url", [
    "http://127.0.0.1/",
    "http://localhost/",
    "http://10.0.0.5/",
    "http://169.254.169.254/",
    "ftp://example.com/",
])
def test_safe_fetch_rejects_unsafe_targets(url):
    with pytest.raises(safe_fetch.UnsafeURLError):
        safe_fetch.get(url)


@pytest.fixture
def fake_public_dns(monkeypatch):
    """DNS resolution shouldn't gate these tests on real network access: example.com always resolves
    to a fixed public IP, so the SSRF guard's redirect-handling logic is what's actually exercised."""
    real_getaddrinfo = socket.getaddrinfo

    def fake(host, *a, **k):
        if host == "example.com":
            return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 0))]
        return real_getaddrinfo(host, *a, **k)

    monkeypatch.setattr(socket, "getaddrinfo", fake)


def test_safe_fetch_rejects_redirect_to_private(fake_public_dns):
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(302, headers={"location": "http://127.0.0.1/secret"})

    client = httpx.Client(transport=httpx.MockTransport(handler), follow_redirects=False)
    with pytest.raises(safe_fetch.UnsafeURLError):
        safe_fetch.get("http://example.com/", client=client)


def test_safe_fetch_text_never_raises_on_unsafe_url():
    final, text = safe_fetch.text("http://127.0.0.1/")
    assert text == ""


def test_safe_fetch_forces_manual_redirects_even_if_caller_client_auto_follows(fake_public_dns):
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(302, headers={"location": "http://127.0.0.1/secret"})

    # a caller passing follow_redirects=True must not bypass the guard
    client = httpx.Client(transport=httpx.MockTransport(handler), follow_redirects=True)
    with pytest.raises(safe_fetch.UnsafeURLError):
        safe_fetch.get("http://example.com/", client=client)


def test_safe_fetch_streams_and_caps_at_max_bytes(monkeypatch, fake_public_dns):
    monkeypatch.setattr(safe_fetch, "MAX_BYTES", 10)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text="x" * 1000)

    client = httpx.Client(transport=httpx.MockTransport(handler))
    r = safe_fetch.get("http://example.com/", client=client)
    assert len(r.text) <= 10 + 4096  # allowed to overshoot by at most one chunk, never load the whole body


# ---------- full scan job (monkeypatched fetch, fake LLM) ----------


def test_full_competitor_scan_job(client, monkeypatch):
    pages = {
        "https://rival.example": _read("homepage.html"),
        "https://rival.example/": _read("homepage.html"),
        "https://rival.example/robots.txt": "Sitemap: https://rival.example/sitemap_index.xml",
        "https://rival.example/sitemap_index.xml": _read("sitemap_index.xml").replace("example-competitor.test", "rival.example"),
        "https://rival.example/product-sitemap.xml": _read("product_sitemap.xml").replace("example-competitor.test", "rival.example"),
        "https://rival.example/page-sitemap.xml": "<urlset xmlns='http://www.sitemaps.org/schemas/sitemap/0.9'></urlset>",
        "https://rival.example/product/chatgpt-plus-1m/": _read("woo_product.html"),
        "https://rival.example/product/midjourney-3m/": _read("jsonld_product.html"),
    }

    def fake_text(url, timeout=15, client=None):
        return url, pages.get(url, "")

    monkeypatch.setattr(safe_fetch, "text", fake_text)
    monkeypatch.setattr(comp, "analyze_competitor_instagram", lambda handle: {
        "username": handle, "posts": [], "partial": True, "source": "", "post_frequency_30d": 0,
        "format_mix": {}, "top_posts": [], "top_hashtags": [],
    })

    h = _user(client)
    bid = _brand(client, h)
    client.put(f"/brands/{bid}/competitors", json={"competitors": [
        {"name": "رقیب یک", "website": "https://rival.example", "instagram": "rival_ig"},
    ]}, headers=h)

    r = client.post(f"/brands/{bid}/competitors/scan", json={}, headers=h)
    assert r.status_code == 200
    assert client.post(f"/brands/{bid}/competitors/scan", json={}, headers=h).status_code == 409

    while process_one():
        pass

    scans = client.get(f"/brands/{bid}/competitors/scans", headers=h).json()
    assert len(scans) == 1 and scans[0]["status"] == "ready", scans[0].get("error")
    report = scans[0]["report"]
    assert report["price_matrix"]
    products_by_key = {row["product"]: row for row in report["price_matrix"]}
    assert "chatgpt_plus" in products_by_key
    assert products_by_key["chatgpt_plus"]["prices"]["رقیب یک"] == 1_500_000
    assert products_by_key["chatgpt_plus"]["duration"] == "1m"
    assert report["gaps"] and all(g["evidence"] for g in report["gaps"])
    assert len(report["suggestions"]) >= 8
    assert len(report["post_ideas"]) >= 1

    one = client.get(f"/competitor-scans/{scans[0]['id']}", headers=h).json()
    assert one["id"] == scans[0]["id"]


# ---------- report honesty ----------


def test_unreachable_site_yields_no_trust_gap(monkeypatch):
    monkeypatch.setattr(safe_fetch, "text", lambda *a, **k: (a[0] if a else "", ""))
    website = comp.analyze_competitor_website("https://unreachable.example")
    assert website["ok"] is False and "signals" not in website
    brand = type("B", (), {"name": "رهبوم", "products": [], "language": "fa"})()
    report = comp.rule_based_report(brand, [{"name": "رقیب ناموجود", "website": website}])
    assert report["trust_compare"] == [{"name": "رقیب ناموجود", "reachable": False}]
    assert not any(g["evidence"] == ["رقیب ناموجود"] and "اینماد" in g["text"] for g in report["gaps"])


# ---------- scan time budget ----------


def test_scan_stops_at_time_budget_and_marks_partial(monkeypatch):
    def slow_text(url, timeout=15, client=None, connect_timeout=5.0):
        if url.endswith("robots.txt"):
            return url, ""
        if "sitemap" in url:
            return url, _read("product_sitemap.xml").replace("example-competitor.test", "slow.example")
        time.sleep(0.05)
        return url, _read("woo_product.html")

    monkeypatch.setattr(safe_fetch, "text", slow_text)
    past_deadline = time.time() - 1
    website = comp.analyze_competitor_website("https://slow.example", deadline=past_deadline)
    assert website["ok"] is False and website["partial"] is True


def test_per_competitor_deadline_marks_website_partial(monkeypatch):
    calls = {"n": 0}

    def counting_text(url, timeout=15, client=None, connect_timeout=5.0):
        calls["n"] += 1
        if url.endswith("robots.txt"):
            return url, ""
        if "sitemap_index" in url:
            return url, _read("sitemap_index.xml").replace("example-competitor.test", "slow.example")
        if "product-sitemap" in url:
            return url, _read("product_sitemap.xml").replace("example-competitor.test", "slow.example")
        if "page-sitemap" in url:
            return url, ""
        if url in ("https://slow.example", "https://slow.example/"):
            return url, _read("homepage.html")
        time.sleep(0.2)
        return url, _read("woo_product.html")

    monkeypatch.setattr(safe_fetch, "text", counting_text)
    deadline = time.time() + 0.1  # shorter than the two product page fetches combined
    website = comp.analyze_competitor_website("https://slow.example", deadline=deadline)
    assert website["ok"] is True
    assert website["partial"] is True


# ---------- handle write-back ----------


def test_write_back_handles_marks_verified(client, monkeypatch):
    pages = {
        "https://rival.example": _read("homepage.html"),
        "https://rival.example/": _read("homepage.html"),
        "https://rival.example/robots.txt": "",
        "https://rival.example/sitemap_index.xml": "",
        "https://rival.example/sitemap.xml": "",
        "https://rival.example/product-sitemap.xml": "",
    }
    monkeypatch.setattr(safe_fetch, "text", lambda url, timeout=15, client=None, connect_timeout=5.0: (url, pages.get(url, "")))
    monkeypatch.setattr(comp, "analyze_competitor_instagram", lambda handle: {})

    h = _user(client)
    bid = _brand(client, h)
    client.put(f"/brands/{bid}/competitors", json={"competitors": [
        {"name": "رقیب یک", "website": "https://rival.example"},  # no instagram/telegram given
    ]}, headers=h)

    client.post(f"/brands/{bid}/competitors/scan", json={}, headers=h)
    while process_one():
        pass

    saved = client.get(f"/brands/{bid}/competitors", headers=h).json()
    assert saved[0]["instagram"] == "example.shop"
    assert saved[0]["instagram_status"] == "verified"
    assert saved[0]["instagram_evidence"] == "https://rival.example"
    assert saved[0]["telegram"] == "example_shop"
    assert saved[0]["telegram_status"] == "verified"
