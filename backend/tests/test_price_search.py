from app import price_search as ps


def test_aliases_and_plans():
    assert ps.matches('قیمت کلاد مکس','Claude Max 20x')
    assert ps.matches('کلاد مکس ۵x','Claude Max 5x - یک ماهه')
    assert not ps.matches('کلاد مکس ۵x','Claude Max 20x')
    assert not ps.matches('کلاد مکس','Claude Pro')
    assert ps.matches('کلود','Claude AI')
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


def test_page_fragments_are_not_downloaded_repeatedly(monkeypatch):
    urls=[]
    def fetch(url,**k):
        urls.append(url)
        return url,'<a href="/product/claude-max#details">Claude Max</a><a href="/product/claude-max#faq">Claude Max</a>'
    monkeypatch.setattr(ps.safe_fetch,'text',fetch)
    ps.lookup({'id':'a','website':'https://example.com'},'Claude Max')
    product=[u for u in urls if u.endswith('/product/claude-max')]
    assert len(product)==1


def test_search_page_link_flood_does_not_starve_direct_candidates(monkeypatch):
    urls=[]
    product='''<script type="application/ld+json">{"@type":"Product","name":"Claude Max 5x","offers":{"price":"320000000","priceCurrency":"IRR"}}</script>'''
    def fetch(url,**k):
        urls.append(url)
        links=''.join(f'<a href="/result-{i}">Claude Max result {i}</a>' for i in range(10))
        return url, product if url.endswith('/product/claude-max') else links
    monkeypatch.setattr(ps.safe_fetch,'text',fetch)
    row=ps.lookup({'id':'a','website':'https://example.com'},'Claude Max')
    assert row['status']=='found'
    assert any(u.endswith('/product/claude-max') for u in urls)


def test_direct_product_paths_find_sites_without_working_search(monkeypatch):
    product='''<script type="application/ld+json">{"@type":"Product","name":"Claude AI","offers":{"price":"2990000","priceCurrency":"IRR"}}</script>'''
    def fetch(url,**k):
        return url, product if url.endswith('/product/ai-claude') else '<html></html>'
    monkeypatch.setattr(ps.safe_fetch,'text',fetch)
    row=ps.lookup({'id':'a','website':'https://example.com'},'Claude')
    assert row['status']=='found'
    assert row['matches'][0]['price']==299000
    assert row['matches'][0]['url'].endswith('/product/ai-claude')


def test_broad_max_search_keeps_distinct_plans(monkeypatch):
    def fetch(url,**k):
        if url.endswith('/product/claude'):
            name,price='Claude Max 20x','600000000'
        else:
            name,price='Claude Max 5x','320000000'
        body=f'''<script type="application/ld+json">{{"@type":"Product","name":"{name}","offers":{{"price":"{price}","priceCurrency":"IRR"}}}}</script>'''
        return url,body
    monkeypatch.setattr(ps.safe_fetch,'text',fetch)
    row=ps.lookup({'id':'a','website':'https://example.com'},'Claude Max')
    assert {(p['name'],p['price']) for p in row['matches']} == {
        ('Claude Max 5x',32000000),('Claude Max 20x',60000000)
    }


def test_numeric_pagination_is_one_page():
    assert ps.page_key('https://dicardo.com/product/claude-ai/2')==ps.page_key('https://dicardo.com/product/claude-ai/3')==ps.page_key('https://dicardo.com/product/claude-ai')
    assert ps.page_key('https://x.ir/product/1')=='https://x.ir/product/1'  # too short to be pagination


def test_pagination_pages_are_not_refetched(monkeypatch):
    calls=[]
    page='<html><a href="/product/claude-ai/2">Claude</a><a href="/product/claude-ai/3">Claude</a><script type="application/ld+json">{"@type":"Product","name":"Claude Pro","offers":{"price":"100000","priceCurrency":"IRT"}}</script></html>'
    def fake(url,**k):calls.append(url);return url,page
    monkeypatch.setattr(ps.safe_fetch,'text',fake)
    row=ps.lookup({'id':'a','website':'https://x.ir'},'Claude Pro')
    assert not any(u.endswith(('/2','/3')) for u in calls)
    assert len(row['matches'])==1


def test_failure_reason_is_reported_and_retried(monkeypatch):
    monkeypatch.setattr(ps.time,'sleep',lambda s:None)
    calls=[]
    def fake(url,**k):
        calls.append(url);ps.safe_fetch._last.reason='timeout_read';return url,''
    monkeypatch.setattr(ps.safe_fetch,'text',fake)
    row=ps.lookup({'id':'a','website':'https://slow.ir'},'Claude Pro')
    assert row['status']=='unreachable' and 'timeout_read' in row['reason']
    assert len(calls)>=3  # retried with backoff, not a single miss


def test_transient_failure_then_success(monkeypatch):
    monkeypatch.setattr(ps.time,'sleep',lambda s:None)
    state={'n':0}
    page='<script type="application/ld+json">{"@type":"Product","name":"Claude Pro","offers":{"price":"100000","priceCurrency":"IRT"}}</script>'
    def fake(url,**k):
        state['n']+=1
        if state['n']==1:ps.safe_fetch._last.reason='timeout_read';return url,''
        return url,page
    monkeypatch.setattr(ps.safe_fetch,'text',fake)
    row=ps.lookup({'id':'a','website':'https://x.ir'},'Claude Pro')
    assert row['status']=='found' and row['matches'][0]['price']==100000


def test_numberland_duration_only_when_stated():
    from lxml import html as lh
    from app.price_adapters import extract
    page='<div class="accountclickable" accid="1" datatag="اشتراک یک ماهه"><div>Claude Pro</div><div>5,900,000 تومان</div></div><div class="accountclickable" accid="2" datatag=""><div>Claude Max</div><div>9,000,000 تومان</div></div>'
    rows=extract(lh.fromstring('<html>'+page+'</html>'),'https://numberland.ir/account/claude-ai')
    assert rows[0].get('duration')=='1m' and 'duration' not in rows[1]
