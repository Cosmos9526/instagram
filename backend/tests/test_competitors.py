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


def test_safe_fetch_rejects_redirect_to_private():
    def handler(request: httpx.Request) -> httpx.Response:
        if "public" in str(request.url):
            return httpx.Response(302, headers={"location": "http://127.0.0.1/secret"})
        return httpx.Response(200, text="ok")

    client = httpx.Client(transport=httpx.MockTransport(handler), follow_redirects=False)
    with pytest.raises(safe_fetch.UnsafeURLError):
        safe_fetch.get("http://public.example.test/", client=client)


def test_safe_fetch_text_never_raises_on_unsafe_url():
    final, text = safe_fetch.text("http://127.0.0.1/")
    assert text == ""


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
    assert len(report["gaps"]) >= 8
    assert len(report["post_ideas"]) >= 1

    one = client.get(f"/competitor-scans/{scans[0]['id']}", headers=h).json()
    assert one["id"] == scans[0]["id"]
