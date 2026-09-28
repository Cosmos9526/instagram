from app import business_analyzer as ba

HTML = """<html><head><title>کلینیک مو آریا | کاشت مو</title>
<meta name="description" content="کاشت مو و درمان ریزش مو با روش FIT">
<meta name="theme-color" content="#0b9488">
<script type="application/ld+json">{"@type":"Product","name":"کاشت مو FIT","offers":{"price":"25000000"}}</script>
</head><body><h2>کاشت ابرو</h2><a href="https://instagram.com/aria.hair">ig</a>
<style>.a{color:#ff5500}.b{color:#ff5500}.c{color:#ffffff}</style></body></html>"""


def test_analyze_business_offline(monkeypatch):
    monkeypatch.setattr(ba, "_fetch", lambda url, timeout=15: (url, HTML if "instagram" not in url else ""))
    monkeypatch.setattr(ba, "analyze_instagram", lambda u: {"username": u, "posts": [], "ok": False})
    monkeypatch.setattr(ba, "chat_json", lambda *a, **k: (_ for _ in ()).throw(ba.LLMError("off")))
    r = ba.analyze_business("aria.example", "")
    p = r["profile"]
    assert p["name"] == "کلینیک مو آریا"
    assert p["industry"] == "زیبایی و آرایشی"
    assert p["products"][0]["name"] == "کاشت مو FIT"
    assert p["colors"]["primary"] == "#0b9488"
    assert p["instagram"] == "aria.hair"
    assert r["plan"] and all(i["idea"] for i in r["plan"])


def test_model_cannot_replace_observed_catalog(monkeypatch):
    monkeypatch.setattr(ba, '_fetch', lambda url, timeout=15: (url, HTML))
    monkeypatch.setattr(ba, 'analyze_instagram', lambda u: {'username': u, 'posts': [], 'ok': False})
    monkeypatch.setattr(ba, 'chat_json', lambda *a, **k: {
        'products': [{'name': 'Invented subscription', 'desc': 'Guaranteed delivery'}],
        'description': 'Refined description',
    })
    result = ba.analyze_business('https://aria.example')
    assert result['profile']['products'] == [{'name': 'کاشت مو FIT', 'desc': ''}]
    assert result['profile']['description'] == 'Refined description'
