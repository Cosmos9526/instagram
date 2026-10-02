"""Bounded product-price lookup across saved competitor sites; never model-invented prices."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from urllib.parse import urljoin, urlparse, urlencode, unquote, urldefrag
import re
import time
from html import unescape
from threading import Lock
from lxml import html as lh
from . import safe_fetch
from .competitors import extract_products, detect_duration, _woo_currency
from .price_adapters import CLAUDE_PAGES, extract as audited_products, public_catalog

ALIASES={'کلاد':'claude','کلاود':'claude','کلود':'claude','مکس':'max','مکث':'max','پلاس':'plus','پرو':'pro','کرسر':'cursor','چتجیپیتی':'chatgpt','جمینای':'gemini','اسپاتیفای':'spotify','کانوا':'canva','پرپلکسیتی':'perplexity'}
ALIASES.update({name: 'higgsfield' for name in ('هیگزفیلد', 'هیگسفیلد', 'هگزفیلد', 'هگسفیلد', 'فیگزفیلد')})
STOP={'قیمت','خرید','اکانت','اشتراک','هزینه','price','buy','account','subscription','چنده','چقدر','است','توی','در','بهم','بگو','لطفا'}
EXTRACTOR_VERSION = 4
ALIASES.update({
    'جمینی': 'gemini', 'جمنای': 'gemini', 'میدجرنی': 'midjourney', 'میدجورنی': 'midjourney',
    'گروک': 'grok', 'نوشن': 'notion', 'ادوبی': 'adobe', 'نتفلیکس': 'netflix',
    'گیتهاب': 'github', 'یوتیوب': 'youtube', 'پرمیوم': 'premium', 'پریمیوم': 'premium',
    'فلو': 'flow', 'گوگل': 'google', 'اولترا': 'ultra', 'تیم': 'team', 'بیزینس': 'business',
    'رانوی': 'runway', 'کلینگ': 'kling', 'لئوناردو': 'leonardo', 'سانو': 'suno', 'سونو': 'suno',
    'کپکات': 'capcut', 'کوپایلوت': 'copilot', 'کاپایلوت': 'copilot', 'الونلبز': 'elevenlabs',
})
PHRASES = {
    r'کپ[\s_-]*کات': 'capcut', r'گیت[\s_-]*هاب': 'github',
    r'مید[\s_-]*ج[و]?رنی': 'midjourney', r'پرپلکس[ی]?تی': 'perplexity',
    r'الون[\s_-]*لبز': 'elevenlabs', r'یو[\s_-]*تیوب': 'youtube',
}
_SITEMAPS = {}
_SITEMAP_LOCK = Lock()


def sitemap_links(base, family, deadline):
    """Cache only discovery URLs, never prices. Bounded, same-origin XML traversal."""
    with _SITEMAP_LOCK:
        cached = _SITEMAPS.get(base)
    if cached and time.monotonic() - cached[0] < 3600:
        return [u for u in cached[1] if matches(family, urlparse(u).path)]
    queue = [base.rstrip('/') + p for p in ('/sitemap_index.xml', '/sitemap.xml', '/product-sitemap.xml')]
    seen, urls = set(), []
    while queue and len(seen) < 4 and time.monotonic() + 2 < deadline:
        url = queue.pop(0)
        if url in seen or not same_site(url, base):
            continue
        seen.add(url)
        final, body = safe_fetch.text(url, timeout=min(4, max(1, deadline-time.monotonic())), connect_timeout=2)
        if not same_site(final, base):
            continue
        locs = [unescape(u.strip()) for u in re.findall(r'<loc>\s*([^<]+)\s*</loc>', body, re.I)]
        locs = [u for u in locs if same_site(u, base)]
        if re.search(r'<(?:\w+:)?sitemapindex\b', body, re.I):
            children = sorted(locs, key=lambda u: ('product' not in u.lower(), u))[:3]
            queue = children + queue
        else:
            urls.extend(locs)
    urls = list(dict.fromkeys(urls))[:10000]
    if urls:
        with _SITEMAP_LOCK:
            if len(_SITEMAPS) >= 64:
                _SITEMAPS.pop(next(iter(_SITEMAPS)))
            _SITEMAPS[base] = (time.monotonic(), urls)
    return [u for u in urls if matches(family, urlparse(u).path)]


def offer_details(product):
    """Only explicit offer text is used; missing conditions remain unknown."""
    name = product['name']
    normalized = terms(name)
    plans = [w for w in normalized if w in {'plus','pro','max','ultra','premium','team','business','enterprise','starter','standard','advanced','basic'} or re.fullmatch(r'\d+x', w)]
    ownership = 'shared' if re.search(r'اشتراکی|shared', name, re.I) else 'personal' if re.search(r'اختصاصی|شخصی|personal|exclusive', name, re.I) else ''
    return {'duration': product.get('duration') or detect_duration(name),
            'plan': ' '.join(dict.fromkeys(plans)), 'account_type': ownership,
            'price_kind': 'range' if product.get('price_max') is not None and product.get('price_max') != product.get('price') else 'exact'}


def preserve_verified(rows, previous_reports, query):
    """Keep a recent, explicitly labelled snapshot when a website stops replying.
    Never reuse results made before the currency/variant corrections.
    """
    previous={}
    for report in previous_reports:
        if report.get('extractor_version') != EXTRACTOR_VERSION or terms(report.get('query','')) != terms(query):continue
        for old in report.get('results',[]):
            if old.get('status') not in ('found','stale') or not old.get('matches'):continue
            try:age=(datetime.now(timezone.utc)-datetime.fromisoformat(old['checked_at'])).total_seconds()
            except (KeyError,ValueError,TypeError):continue
            if 0 <= age <= 86400:previous.setdefault(old['competitor_id'],old)
    result=[]
    for current in rows:
        old=previous.get(current['competitor_id'])
        if old and current['status'] in ('unreachable','blocked','not_found'):
            current=current | {'status':'stale','matches':old['matches'],'checked_at':old['checked_at'],
                               'attempted_at':current['checked_at'],'refresh_status':current['status']}
        result.append(current)
    return result

def terms(text):
    text=unquote(text).lower().translate(str.maketrans('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩يك','01234567890123456789یک'))
    text=re.sub(r'چت[\s\u200c_-]*جی[\s\u200c_-]*پی[\s\u200c_-]*تی|chat[\s_-]*gpt', 'chatgpt', text)
    text=text.replace('\u200c', ' ')
    text=re.sub(r'(?:هیگ[زس]|هگ[زس]|فیگ[زس])[\s_-]*فیلد|higgs[\s_-]*field', 'higgsfield', text)
    for pattern, replacement in PHRASES.items():
        text=re.sub(pattern, replacement, text)
    text=re.sub(r'(max)(\d)',r'\1 \2',text)
    text=re.sub(r'(\d+)\s*[×xایکس]+',r'\1x',text)
    words=[ALIASES.get(w,w) for w in re.findall(r'[\w]+',text) if w not in STOP]
    if 'flow' in words or 'gemini' in words:
        words=[w for w in words if w!='google']
    return words

def query_problem(query):
    wanted = terms(query)
    if 'chatgpt' in wanted and 'max' in wanted:
        return 'ChatGPT Max is ambiguous. Choose ChatGPT Pro for OpenAI, or Claude Max for Anthropic. Prices are compared by the exact plan name.'
    return None

def matches(query,name):
    wanted=terms(query);found=terms(name)
    if 'pro' in wanted and 'max' not in wanted and 'max' in found:
        return False
    return bool(wanted) and all(w in found for w in wanted)

def same_site(url,base):
    host=(urlparse(url).hostname or '').removeprefix('www.')
    target=(urlparse(base).hostname or '').removeprefix('www.')
    return bool(target) and host==target

def canonical(url):
    """Page fragments never change product data and must not trigger another download."""
    return urldefrag(url)[0].rstrip('/') or urldefrag(url)[0]

def page_key(url):
    """Numeric pagination of one product page (/product/claude-ai/2, /3) is the same page."""
    parsed=urlparse(canonical(url))
    parts=parsed.path.split('/')
    if len([x for x in parts if x])>=3 and parts[-1].isdigit():parts=parts[:-1]
    return parsed._replace(path='/'.join(parts),query='',fragment='').geturl().rstrip('/')

def product_link(url):
    parsed=urlparse(url)
    if parsed.query or any(x in parsed.path.lower() for x in ('cart','checkout','comment-page','login','logout')):
        return False
    return any(part in parsed.path.lower() for part in ('product','service','account','shop','game'))

def lookup(c,query):
    base=c.get('website','').strip()
    if base and '://' not in base:base='https://'+base
    reasons=[]
    out={'competitor_id':c['id'],'name':c.get('name') or urlparse(base).hostname or 'Competitor','website':base,'status':'not_found','matches':[],'checked_at':datetime.now(timezone.utc).isoformat()}
    if not base:out['status']='no_website';return out
    started=time.monotonic()
    deadline=started+40
    normalized=' '.join(terms(query))
    wanted=terms(query)
    slug='-'.join(wanted)
    family=next((w for w in wanted if w not in {'google','خدمات','سرویس'}), '')
    direct=[]
    for path in (f'product/{slug}',f'product/{family}',f'product/ai-{family}',f'product/{family}-ai',f'services/ai/{family}'):
        if family:direct.append(base.rstrip('/')+'/'+path)
    host=(urlparse(base).hostname or '').removeprefix('www.')
    try:catalog=public_catalog(host)
    except Exception:catalog=None
    if host=='codinocard.ir' and catalog is None:
        out['status']='unreachable'
        return out
    if catalog is not None:
        out['matches']=[p | {'currency':'Toman'} | offer_details(p) for p in catalog if matches(query,p['name'])]
        out['status']='found' if out['matches'] else 'not_found'
        return out
    queue=[base.rstrip('/')+p for p in CLAUDE_PAGES.get(host,[]) ] if family=='claude' else []
    if family == 'higgsfield':
        paths = {'parspremium.ir': '/product/Higgsfield', 'license-market.ir': '/product/Higgsfield',
                 'dicardo.com': '/product/higgsfield-ai', 'g1verify.ir': '/product/higgsfield/',
                 'kharidaccount.ir': '/account/higgsfield/', 'premium24.ir': '/product/higgsfield-ai-pricing'}
        if host in paths:queue.append(base.rstrip('/')+paths[host])
    # These catalogues use case-sensitive product routes (Flow != flow).
    if host in ('parspremium.ir','license-market.ir') and family:
        queue.append(base.rstrip('/')+'/product/'+family.capitalize())
    queue.append(base.rstrip('/')+'/?'+urlencode({'s':family or normalized,'post_type':'product'}))
    queue.extend(direct)
    queue.append(base)
    queue=list(dict.fromkeys(canonical(url) for url in queue))
    visited=set();ok=0;seen={};blocked=False;discovered=False
    while queue and len(visited)<12:
        if time.monotonic()>=deadline:reasons.append('budget_exhausted');break
        if len(visited) >= 3 and not discovered and not any(p['price'] is not None for p in out['matches']):
            discovered=True
            try: candidates=sitemap_links(base, family, min(deadline, time.monotonic()+12))
            except Exception: candidates=[]
            candidates=sorted(candidates, key=lambda u: (-sum(w in terms(urlparse(u).path) for w in wanted), len(u)))
            queue=list(dict.fromkeys(candidates[:5]+queue))
        url=canonical(queue.pop(0))
        if page_key(url) in visited or not same_site(url,base):continue
        visited.add(page_key(url))
        final,body=url,''
        for attempt in range(3):
            t0=time.monotonic();safe_fetch._last.reason=''
            try:final,body=safe_fetch.text(url,timeout=7,connect_timeout=3)
            except Exception:body=''
            if body:break
            reason=safe_fetch.last_reason() or 'empty_body'
            reasons.append(reason)
            if reason in ('http_401','http_403','http_429'):blocked=True
            if reason.startswith('http_4') and reason!='http_429' or reason in ('dns','unsafe'):break
            # A slow site gets a longer budget (up to 65 s) instead of being reported as missing.
            if time.monotonic()-t0>4:deadline=min(deadline+8,started+65)
            if time.monotonic()+7>=deadline:reasons.append('budget_exhausted');break
            time.sleep(0.6*(attempt+1))
        if not body or not same_site(final,base):continue
        if '__zrkjc' in body or 'در حال بررسی مرورگر' in body:
            blocked=True;reasons.append('challenge');continue
        ok+=1
        try:tree=lh.fromstring(body)
        except Exception:continue
        links=[]
        for a in tree.xpath('//a[@href]'):
            dest=canonical(urljoin(final,a.get('href')))
            if same_site(dest,base) and product_link(dest) and (matches(family,a.text_content()) or matches(family,dest)) and page_key(dest) not in visited:
                links.append(page_key(dest))
        queue=list(dict.fromkeys(links[:2]+queue))
        adapted=audited_products(tree,final)
        for p in adapted if adapted is not None else extract_products(body):
            if not matches(query,p['name']):continue
            # Generic list-page prices must link to the relevant product, not a whole catalog.
            product_links=[urljoin(final,a.get('href')) for a in tree.xpath('//a[@href]') if matches(p['name'],a.text_content())]
            source=p.get('url') or next((u for u in product_links if same_site(u,base) and product_link(u)),final)
            source=urljoin(final,source)
            if not same_site(source,base):source=final
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
            # Review pagination/alternate URLs often repeat the same offer.
            # Keep the first exact offer from the prioritized product page.
            key=(tuple(terms(p['name'])), p.get('duration') or detect_duration(p['name']))
            product={'name':p['name'],'price':price,'price_max':price_max,'currency':'Toman' if price is not None else 'Unknown','in_stock':p.get('in_stock'),'url':source,'evidence':p.get('evidence','Product structured data')}
            product.update(offer_details(p))
            regular=p.get('regular_price')
            if variation_currency and currency in ('IRR','ریال') and regular is not None:regular=int(regular/10)
            if price is not None and isinstance(regular,(int,float)) and price < regular <= 10**10:
                product['regular_price']=regular
            if key in seen:
                index=seen[key]
                if out['matches'][index]['price'] is None and price is not None:
                    out['matches'][index]=product
                continue
            seen[key]=len(out['matches'])
            out['matches'].append(product)
        specific_plan = any(re.fullmatch(r'\d+x', term) for term in wanted)
        if specific_plan and any(p['price'] is not None for p in out['matches']):
            out['status']='found'
            return out
    out['pages_checked']=len(visited)
    out['reason']=', '.join(dict.fromkeys(reasons))
    out['status']='found' if any(p['price'] is not None for p in out['matches']) else 'price_unavailable' if out['matches'] else 'blocked' if blocked else 'not_found' if ok else 'unreachable'
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
    return {'kind':'price_search','extractor_version':EXTRACTOR_VERSION,'query':query,'results':sorted(rows,key=lambda r:order[r['competitor_id']]),'progress':{'done':len(rows),'total':len(competitors)}}
