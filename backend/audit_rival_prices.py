"""Public-page audit; saves reproducible evidence, never account credentials."""
import json
import re
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urljoin, urlparse, urldefrag
from lxml import html
from app.safe_fetch import get
from app.competitors import extract_products
from app.price_search import matches, same_site, product_link

DOMAINS = ['parspremium.ir','cafearz.com','dicardo.com','numberland.ir','license-market.ir','asangem.com','account4all.ir','g1verify.ir','kharidaccount.ir','licenseyar.ir','premium24.ir','codinocard.ir','majazite.com','giftpin.ir','khanehlicense.ir','iranicard.ir']
ROOT = Path('/private/tmp/rahboom-price-audit')

def audit(domain):
    root=ROOT/domain; root.mkdir(parents=True,exist_ok=True)
    base='https://'+domain
    queue=[base+'/?s=claude&post_type=product',base]
    known={'cafearz.com':['/services/ai/claude'],'dicardo.com':['/product/ai-claude'],'asangem.com':['/product/claude-max-monthly/','/product/cluade-max-plan/'],'g1verify.ir':['/product/claude-max/'],'license-market.ir':['/product/Claude-AI'],'kharidaccount.ir':['/account/claude/'],'majazite.com':['/product/claude-ai/']}
    queue=[base+p for p in known.get(domain,[])]+queue
    seen=set();rows=[]
    while queue and len(seen)<7:
        url=urldefrag(queue.pop(0))[0]
        if url in seen or not same_site(url,base):continue
        seen.add(url)
        try:
            r=get(url,timeout=8,connect_timeout=3)
            row={'url':url,'final_url':r.url,'status':r.status_code}
            if r.status_code<400:
                tree=html.fromstring(r.text)
                row['products']=extract_products(r.text)
                links=[]
                for a in tree.xpath('//a[@href]'):
                    dest=urldefrag(urljoin(r.url,a.get('href')))[0]
                    if same_site(dest,base) and product_link(dest) and (matches('Claude',a.text_content()) or matches('Claude',dest)):
                        links.append(dest)
                row['links']=list(dict.fromkeys(links))[:30]
                queue+=row['links']
                (root/f'{len(rows)}.html').write_text(r.text)
                for node in tree.xpath('//script|//style|//noscript'):node.drop_tree()
                text=' '.join(tree.text_content().split())
                (root/f'{len(rows)}.txt').write_text(text)
                row['evidence']=re.findall(r'.{0,90}(?:تومان|ریال|5x|20x|۵ برابر|۲۰ برابر).{0,100}',text,re.I)[:35]
            rows.append(row)
        except Exception as e:rows.append({'url':url,'error':type(e).__name__})
    (root/'report.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
    print(domain,[(r.get('status',r.get('error')),len(r.get('products',[]))) for r in rows],flush=True)

if __name__=='__main__':
    with ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(audit,DOMAINS))
