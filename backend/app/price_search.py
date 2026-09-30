"""Bounded product-price lookup across saved competitor sites; never model-invented prices."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from urllib.parse import urljoin, urlparse, urlencode, unquote, urldefrag
import re
import time
from lxml import html as lh
from . import safe_fetch
from .competitors import extract_products, detect_duration, _woo_currency

ALIASES={'کلاد':'claude','کلاود':'claude','کلود':'claude','مکس':'max','مکث':'max','پلاس':'plus','پرو':'pro','کرسر':'cursor','چتجیپیتی':'chatgpt','جمینای':'gemini','اسپاتیفای':'spotify','کانوا':'canva','پرپلکسیتی':'perplexity'}
STOP={'قیمت','خرید','اکانت','اشتراک','هزینه','price','buy','account','subscription','چنده','چقدر','است','توی','در','بهم','بگو','لطفا'}

def terms(text):
    text=unquote(text).lower().translate(str.maketrans('۰۱۲۳۴۵۶۷۸۹يك','0123456789یک'))
    text=text.replace('چت جی پی تی','chatgpt').replace('چت جی‌پی‌تی','chatgpt').replace('chat gpt','chatgpt')
    text=re.sub(r'(\d+)\s*[×xایکس]+',r'\1x',text)
    return [ALIASES.get(w,w) for w in re.findall(r'[\w]+',text) if w not in STOP]

def matches(query,name):
    wanted=terms(query);found=terms(name)
    return bool(wanted) and all(w in found for w in wanted)

def same_site(url,base):
    host=(urlparse(url).hostname or '').removeprefix('www.')
    target=(urlparse(base).hostname or '').removeprefix('www.')
    return bool(target) and host==target

def canonical(url):
    """Page fragments never change product data and must not trigger another download."""
    return urldefrag(url)[0].rstrip('/') or urldefrag(url)[0]

def lookup(c,query):
    base=c.get('website','').strip()
    if base and '://' not in base:base='https://'+base
    out={'competitor_id':c['id'],'name':c.get('name') or urlparse(base).hostname or 'Competitor','website':base,'status':'not_found','matches':[],'checked_at':datetime.now(timezone.utc).isoformat()}
    if not base:out['status']='no_website';return out
    deadline=time.monotonic()+32
    normalized=' '.join(terms(query))
    wanted=terms(query)
    slug='-'.join(wanted)
    family=wanted[0] if wanted else ''
    direct=[]
    for path in (f'product/{slug}',f'product/{family}',f'product/ai-{family}',f'product/{family}-ai',f'services/ai/{family}'):
        if family:direct.append(base.rstrip('/')+'/'+path)
    queue=[base.rstrip('/')+'/?'+urlencode({'s':normalized,'post_type':'product'})]
    if normalized!=query:queue.append(base.rstrip('/')+'/?'+urlencode({'s':query,'post_type':'product'}))
    queue.extend(direct)
    queue.append(base)
    queue=list(dict.fromkeys(canonical(url) for url in queue))
    visited=set();ok=0;seen=set()
    while queue and len(visited)<6 and time.monotonic()<deadline:
        url=canonical(queue.pop(0))
        if url in visited or not same_site(url,base):continue
        visited.add(url)
        try:final,body=safe_fetch.text(url,timeout=5,connect_timeout=2.5)
        except Exception:continue
        if not body or not same_site(final,base):continue
        ok+=1
        try:tree=lh.fromstring(body)
        except Exception:continue
        links=[]
        for a in tree.xpath('//a[@href]'):
            dest=canonical(urljoin(final,a.get('href')))
            if same_site(dest,base) and (matches(query,a.text_content()) or matches(query,dest)) and dest not in visited:
                links.append(dest)
        queue=list(dict.fromkeys(links[:5]+queue))
        for p in extract_products(body):
            if not matches(query,p['name']):continue
            # Generic list-page prices must link to the relevant product, not a whole catalog.
            product_links=[urljoin(final,a.get('href')) for a in tree.xpath('//a[@href]') if matches(p['name'],a.text_content())]
            source=next((u for u in product_links if same_site(u,base)),final)
            currency=p.get('currency','').upper()
            variation_currency = not currency and 'data-product_variations=' in body
            if variation_currency:
                currency = _woo_currency(body).upper()
            if currency not in ('IRR','IRT','TMN','TOMAN','تومان','ریال'):
                price=None;price_max=None
            else:
                price=p.get('price');price_max=p.get('price_max')
                if variation_currency and currency in ('IRR', 'ریال'):
                    price = int(price / 10) if price is not None else None
                    price_max = int(price_max / 10) if price_max is not None else None
            if price is not None and (price<=0 or price>10**10):price=None;price_max=None
            key=(p['name'],price,price_max)
            if key in seen:continue
            seen.add(key)
            out['matches'].append({'name':p['name'],'price':price,'price_max':price_max,'currency':'Toman' if price is not None else 'Unknown','duration':detect_duration(p['name']),'in_stock':p.get('in_stock'),'url':source})
        if any(p['price'] is not None for p in out['matches']):
            out['status']='found'
            return out
    out['status']='found' if any(p['price'] is not None for p in out['matches']) else 'price_unavailable' if out['matches'] else 'not_found' if ok else 'unreachable'
    return out

def run_price_search(competitors,query,on_progress=None):
    rows=[]
    with ThreadPoolExecutor(max_workers=min(6, len(competitors) or 1)) as pool:
        futures={pool.submit(lookup,c,query):c for c in competitors}
        for future in as_completed(futures):
            try:row=future.result()
            except Exception:
                c=futures[future];row={'competitor_id':c['id'],'name':c.get('name') or c.get('website'),'website':c.get('website'),'status':'unreachable','matches':[],'checked_at':datetime.now(timezone.utc).isoformat()}
            rows.append(row)
            if on_progress:on_progress(list(rows),len(competitors))
    order={c['id']:i for i,c in enumerate(competitors)}
    return {'kind':'price_search','query':query,'results':sorted(rows,key=lambda r:order[r['competitor_id']]),'progress':{'done':len(rows),'total':len(competitors)}}
