from app import price_search as ps


def test_aliases_and_plans():
    assert ps.matches('قیمت کلاد مکس','Claude Max 20x')
    assert ps.matches('کلاد مکس ۵x','Claude Max 5x - یک ماهه')
    assert not ps.matches('کلاد مکس ۵x','Claude Max 20x')
    assert not ps.matches('کلاد مکس','Claude Pro')
    assert ps.matches('Notion Plus','خرید Notion Plus')


def test_every_competitor_gets_result(monkeypatch):
    monkeypatch.setattr(ps.safe_fetch,'text',lambda *a,**k: ('https://example.com/',''))
    rows=ps.run_price_search([{'id':'a','website':'https://example.com'},{'id':'b','website':''}],'Claude Max')['results']
    assert len(rows)==2 and rows[0]['status']=='unreachable' and rows[1]['status']=='no_website'


def test_price_currency_source_and_range(monkeypatch):
    html='''<script type="application/ld+json">{"@type":"Product","name":"Claude Max 5x یک ماهه","offers":{"lowPrice":"300000000","highPrice":"320000000","priceCurrency":"IRR"}}</script>'''
    monkeypatch.setattr(ps.safe_fetch,'text',lambda url,**k:(url,html))
    row=ps.lookup({'id':'a','website':'https://example.com'},'کلاد مکس')
    p=row['matches'][0]
    assert p['price']==30000000 and p['price_max']==32000000 and p['currency']=='Toman'
    assert p['url'].startswith('https://example.com')
    assert row['checked_at']


def test_unknown_currency_not_labelled_toman(monkeypatch):
    html='''<script type="application/ld+json">{"@type":"Product","name":"Claude Max","offers":{"price":"100","priceCurrency":"USD"}}</script>'''
    monkeypatch.setattr(ps.safe_fetch,'text',lambda url,**k:(url,html))
    p=ps.lookup({'id':'a','website':'https://example.com'},'Claude Max')
    assert p['status']=='price_unavailable' and p['matches'][0]['price'] is None


def test_cannot_follow_offsite_links(monkeypatch):
    urls=[]
    def fetch(url,**k):
        urls.append(url)
        return url,'<a href="http://127.0.0.1/claude-max">Claude Max</a><a href="https://evil.example/claude-max">Claude Max</a>'
    monkeypatch.setattr(ps.safe_fetch,'text',fetch)
    ps.lookup({'id':'a','website':'https://example.com'},'Claude Max')
    assert all(ps.same_site(u,'https://example.com') for u in urls)
