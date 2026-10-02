from app import price_search as ps
from app.competitors import extract_products
from app.price_adapters import extract
from lxml import html


def test_multilingual_product_queries():
    for query, title in [('مید جرنی','Midjourney Standard'),('گوگل فلو','Flow Pro'),('جمینی','Google Gemini'),('کپ کات پرو','CapCut Pro'),('گیت هاب','GitHub Copilot'),('الون لبز','ElevenLabs'),('کلاد مکس ٥x','Claude Max 5x')]:
        assert ps.matches(query,title)
    assert not ps.matches('کلاد مکس ٥x','Claude Max 20x')


def test_sitemap_discovers_nonstandard_product_url(monkeypatch):
    ps._SITEMAPS.clear()
    calls=[]
    def fetch(url,**kw):
        calls.append(url)
        if url.endswith('/sitemap_index.xml'):
            return url,'<sitemapindex><sitemap><loc>https://example.com/product-sitemap.xml</loc></sitemap><sitemap><loc>http://127.0.0.1/private.xml</loc></sitemap></sitemapindex>'
        if url.endswith('/product-sitemap.xml'):
            return url,'<urlset><url><loc>https://example.com/buy-midjourney-subscription-2026</loc></url></urlset>'
        if url.endswith('/buy-midjourney-subscription-2026'):
            return url,'<script type="application/ld+json">{"@type":"Product","name":"Midjourney Pro monthly","offers":{"price":"2200000","priceCurrency":"IRT"}}</script>'
        return url,'<html></html>'
    monkeypatch.setattr(ps.safe_fetch,'text',fetch)
    result=ps.lookup({'id':'a','website':'https://example.com'},'میدجرنی')
    assert result['status']=='found'
    p=result['matches'][0]
    assert p['price']==2200000 and p['duration']=='1m' and p['plan']=='pro'
    assert p['in_stock'] is None
    assert all(ps.same_site(u,'https://example.com') for u in calls)
    ps._SITEMAPS.clear()


def test_nested_woo_sale_price_excludes_old_and_related_prices():
    body='''<h1 class="product_title">Midjourney Pro</h1><p class="price"><del><span class="woocommerce-Price-amount"><bdi>3,000,000 <span class="woocommerce-Price-currencySymbol">تومان</span></bdi></span></del><ins><span class="woocommerce-Price-amount"><bdi>2,000,000 <span class="woocommerce-Price-currencySymbol">تومان</span></bdi></span></ins></p><section><span class="woocommerce-Price-amount">99,000</span></section>'''
    row=extract_products(body)[0]
    assert row['price']==2000000 and row['regular_price']==3000000
    assert row['price_max']==2000000


def test_variation_numeric_price_requires_explicit_purchase_unit():
    body='''<div class="summary"><h1>Midjourney</h1><span class="woocommerce-Price-currencySymbol">ریال</span><form data-product_variations='[{"attributes":{"duration":"3-month","plan":"pro"},"display_price":20000000,"display_regular_price":25000000,"is_in_stock":false}]'></form></div>'''
    row=extract(html.fromstring(body),'https://example.com/product/midjourney')[0]
    assert row['price']==2000000 and row['regular_price']==2500000
    assert row['duration']=='3m' and row['in_stock'] is False
    unknown=extract(html.fromstring(body.replace('ریال','')),'https://example.com/product/midjourney')[0]
    assert unknown['price'] is None


def test_explicit_duration_from_adapter_preserved(monkeypatch):
    monkeypatch.setattr(ps.safe_fetch,'text',lambda url,**kw:(url,'<html></html>'))
    monkeypatch.setattr(ps,'audited_products',lambda *a:[{'name':'Claude Pro شخصی','price':2000000,'price_max':2000000,'currency':'IRT','duration':'3m'}])
    row=ps.lookup({'id':'a','website':'https://example.com'},'Claude Pro')['matches'][0]
    assert row['duration']=='3m' and row['account_type']=='personal'


def test_later_verified_price_replaces_missing_price(monkeypatch):
    monkeypatch.setattr(ps.safe_fetch,'text',lambda url,**kw:(url,'<html></html>'))
    monkeypatch.setattr(ps,'sitemap_links',lambda *a:[])
    def products(tree,url):
        price=2000000 if url.endswith('/product/midjourney') else None
        return [{'name':'Midjourney Pro','price':price,'price_max':price,'currency':'IRT'}]
    monkeypatch.setattr(ps,'audited_products',products)
    row=ps.lookup({'id':'a','website':'https://example.com'},'Midjourney')
    assert row['status']=='found' and len(row['matches'])==1
    assert row['matches'][0]['price']==2000000


def test_duration_four_eighteen_and_twenty_one_months():
    from app.competitors import detect_duration
    assert detect_duration('۱۸ ماهه - ۳ ماه گارانتی')=='18m'
    assert detect_duration('4 months')=='4m'
    assert detect_duration('21 ماهه')=='21m'


def test_case_sensitive_catalogue_routes(monkeypatch):
    monkeypatch.setattr(ps,'sitemap_links',lambda *a:[])
    def fetch(url,**kw):
        return url, '<script type="application/ld+json">{"@type":"Product","name":"Google Flow Pro","offers":{"price":"2200000","priceCurrency":"IRT"}}</script>' if url.endswith('/product/Flow') else '<html></html>'
    monkeypatch.setattr(ps.safe_fetch,'text',fetch)
    row=ps.lookup({'id':'a','website':'https://parspremium.ir'},'گوگل فلو')
    assert row['status']=='found' and row['matches'][0]['url'].endswith('/product/Flow')
