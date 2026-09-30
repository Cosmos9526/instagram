"""Price selectors audited against public product pages, September 2026.

Never infer a plan's price from an unrelated page-wide amount. All returned
amounts are Toman; selectors carry the exact plan and direct source URL.
"""
import json
from urllib.parse import urljoin, urlparse, unquote, quote
from lxml import html as lh
from .competitors import parse_price
from . import safe_fetch


def public_catalog(host):
    if host != 'codinocard.ir':return None
    # Endpoint used by the public shop, not an authenticated/admin API.
    products=None
    for _ in range(2):
        _,body=safe_fetch.text('https://api.codinocard.ir/api/products',timeout=8,connect_timeout=3)
        try:products=json.loads(body)['products']
        except (ValueError,KeyError,TypeError):continue
        if isinstance(products,list):break
    if not isinstance(products,list):return None
    result=[]
    for p in products:
        for v in p.get('variants',[]):
            price=v.get('price')
            if not isinstance(price,(int,float)):continue
            # variant.currency is the face-value currency (USD), NOT the
            # checkout currency. price is the displayed Toman selling amount.
            source='https://codinocard.ir/product/'+quote(p['id'],safe='')
            result.append(row(p['name']+' '+v.get('label',''),int(price),source,p.get('available'), 'Public catalogue selling price in Toman'))
    return result

CLAUDE_PAGES = {
    'parspremium.ir': ['/product/Claude-AI'],
    'cafearz.com': ['/services/ai/claude'],
    'dicardo.com': ['/product/claude-ai'],
    'numberland.ir': ['/account/claude-ai'],
    'license-market.ir': ['/product/Claude-AI'],
    'asangem.com': ['/game/claude/', '/product/claude-max-monthly/', '/product/cluade-max-plan/'],
    'account4all.ir': ['/product/خرید-اکانت-claude-ai/'],
    'g1verify.ir': ['/product/claude-max/'],
    'kharidaccount.ir': ['/account/claude/'],
    'licenseyar.ir': ['/product/claude-pro-یکماهه-گارانتی-۳۰-روزه/'],
    'premium24.ir': ['/product/calude-ai-pricing'],
    'majazite.com': ['/product/claude-ai/'],
    'giftpin.ir': ['/product/claude-pro'],
    'khanehlicense.ir': ['/product/claude-pro/'],
}


def row(name, price, url, stock=None, evidence='Visible product price'):
    return dict(name=name.strip(), price=price, price_max=price, currency='IRT',
                in_stock=stock, url=url, evidence=evidence)


def extract(tree, url):
    host=(urlparse(url).hostname or '').removeprefix('www.')
    result=[]
    if host == 'cafearz.com' and '/services/ai/' in urlparse(url).path:
        title=' '.join(tree.xpath('//h1//text()')).strip()
        article=' '.join(tree.xpath('//article//text()'))
        if 'Claude' in title and 'Max' in article:
            return [row('Claude Max',None,url,evidence='Plan mentioned; public page does not expose a verifiable price')]
    if host == 'asangem.com':
        # This site's JSON-LD incorrectly labels its Toman values as IRR.
        # Use the product card's displayed amount and its adjacent ت symbol.
        for a in tree.xpath('//a[.//h2[contains(@class,"product_title_thumb")]]'):
            names=a.xpath('.//h2[contains(@class,"product_title_thumb")]/text()')
            prices=a.xpath('.//*[contains(@class,"pricebox")]//label[not(contains(@class,"old"))]')
            prices=[p for p in prices if not p.xpath('ancestor::del') and p.xpath('.//small[normalize-space()="ت"]')]
            if names and prices:
                result.append(row(names[0],parse_price(prices[-1].text_content(),'IRT'),urljoin(url,a.get('href',''))))
        if not result:
            # Detail page amount is carried by the purchase form in the same
            # units as the catalogue. Require the site's Toman symbol as well.
            names=tree.xpath('//h1/text()')
            prices=tree.xpath('//input[@name="cpf_product_price"]/@value')
            symbols=tree.xpath('//*[self::small or self::span][normalize-space()="ت" or normalize-space()="تومان"]')
            if names and prices and symbols:
                result.append(row(names[0],parse_price(prices[0],'IRT'),url))
        # Never fall back to this site's incorrectly labelled schema.
        return result
    if host == 'numberland.ir':
        for card in tree.xpath('//*[contains(concat(" ",normalize-space(@class)," ")," accountclickable ")][@accid]'):
            parts=card.xpath('./div')
            if len(parts)!=2 or 'تومان' not in parts[1].text_content():continue
            name=parts[0].text_content().strip()
            if name=='Max':name='Claude Max 5x' if '5 برابر' in card.get('datatag','') else 'Claude Max'
            result.append(row(name,parse_price(parts[1].text_content(),'IRT'),url))
        return result
    if host == 'dicardo.com':
        title=' '.join(tree.xpath('//h1//text()')).strip()
        for card in tree.xpath('//div[@class="single-top__item__product__type__item"]'):
            name=' '.join(card.xpath('.//h2//text()'))
            price=card.xpath('./div[contains(@class,"__price")]')
            if name and price and 'تومان' in price[0].text_content():
                result.append(row(title+' '+name,parse_price(price[0].text_content(),'IRT'),url))
        return result or None
    if host in ('parspremium.ir','license-market.ir'):
        for script in tree.xpath('//script'):
            text=script.text or ''
            marker="window.__PRELOADED_STATE__ = JSON.parse('"
            if marker not in text:continue
            # Parse data, never execute site JavaScript.
            try:
                raw=text.split(marker,1)[1].replace("\\'","'").replace('\\\\','\\')
                state=json.JSONDecoder().raw_decode(raw)[0]
                variants=state['entity_route']['other_props']['product_variants']
            except (ValueError,KeyError,TypeError):continue
            visible=tree.xpath('//*[@data-product="price"]')
            amounts={parse_price(p.text_content(),'IRT') for p in visible if 'تومان' in p.text_content()}
            # Verify the state's numeric unit against a visible price, instead
            # of guessing from a schema currency or unrelated conversion rate.
            if not any(v.get('price') in amounts for v in variants):continue
            for v in variants:
                if not v.get('enabled'):continue
                stock=v.get('stock_number',0)>0 if v.get('is_stock_managed') else None
                result.append(row(v['title'],v.get('price'),url,stock,'Product option; unit checked against displayed Toman price'))
        return result or None
    if host == 'g1verify.ir':
        title=' '.join(tree.xpath('//h1//text()')).strip()
        if title and 'استعلام قیمت' in tree.text_content():
            return [row(title,None,url,evidence='Contact seller for a quote')]
    # Currency plugins can expose display_price in Rials while price_html is
    # already converted to Toman. Read the selected option's visible sale price.
    for form in tree.xpath('//*[@data-product_variations]'):
        try:variants=json.loads(form.get('data-product_variations'))
        except (ValueError,TypeError):continue
        if not isinstance(variants,list):continue
        title=' '.join(tree.xpath('//h1//text()')).strip()
        for v in variants:
            attrs=' '.join(unquote(str(a)).replace('-',' ') for a in (v.get('attributes') or {}).values())
            fragment=v.get('price_html','')
            price=None
            if fragment:
                prices=lh.fragment_fromstring(fragment,create_parent='div')
                amounts=prices.xpath('//*[contains(@class,"woocommerce-Price-amount") and not(ancestor::del)]')
                if len(amounts)==1:
                    text=amounts[0].text_content()
                    if 'تومان' in text or 'ریال' in text:price=parse_price(text)
            result.append(row(title+' '+attrs,price,url,v.get('is_in_stock'), 'Selected product option price'))
        if result:return result
    return None
