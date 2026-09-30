from pathlib import Path
from lxml import html
from app.price_adapters import extract, CLAUDE_PAGES
from app import price_search as ps

FIXTURES=Path(__file__).parent/'fixtures'/'prices'

def adapted(domain):
    return extract(html.fromstring((FIXTURES/(domain+'.html')).read_text()),'https://'+domain+CLAUDE_PAGES[domain][0])

def test_visible_toman_beats_wrong_asangem_irr_schema():
    products=adapted('asangem.com')
    assert {p['price'] for p in products if ps.matches('Claude Max',p['name'])}=={27689900,55379900}

def test_numberland_plan_conditions_preserved():
    products=adapted('numberland.ir')
    assert next(p['price'] for p in products if p['name']=='Claude Max 5X بدون گارانتی')==26132000
    assert next(p['price'] for p in products if p['name']=='Claude Max 5x')==35548300

def test_dicardo_does_not_assign_pro_price_to_max():
    products=adapted('dicardo.com')
    assert [p['price'] for p in products if ps.matches('Claude Max',p['name'])]==[35425000]

def test_parspremium_option_prices_not_aggregate_range():
    products=adapted('parspremium.ir')
    assert [p['price'] for p in products if ps.matches('Claude Max 20x',p['name'])]==[80917000]
    assert [p['price'] for p in products if ps.matches('Claude Max 5x',p['name'])]==[45140000]

def test_quote_required_is_not_a_price():
    assert adapted('g1verify.ir')[0]['price'] is None

def test_max_without_space_and_cart_links():
    assert ps.matches('کلاد مکس ۵x','Claude max5x exclusive 1month')
    assert not ps.matches('Claude Max 5x','Claude max20x')
    assert not ps.product_link('https://site.ir/product/claude?add-to-cart=42')

def test_audited_woo_variation_units(monkeypatch):
    for domain,expected in [('majazite.com',{34358000,66753000}),('kharidaccount.ir',{47097500,31398000,84774400,60595900})]:
        body=(FIXTURES/(domain+'.html')).read_text()
        monkeypatch.setattr(ps.safe_fetch,'text',lambda url,**kw:(url,body))
        result=ps.lookup({'id':'a','website':'https://'+domain},'Claude Max')
        assert {p['price'] for p in result['matches']}==expected
