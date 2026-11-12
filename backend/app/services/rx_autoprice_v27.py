"""v27: bounded, automatic Iranian SKU discovery. No fabricated prices.

Only suppliers on the explicit allowlist are queried. A price is eligible only
when a returned *product* identifies a matching active ingredient/brand,
route/form, concentration, pack volume/count, currency and stock. No site home
page is treated as price evidence. Search failure is visible per supplier.
Clinical substitutions are NEVER inferred from these shopping data.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from html import unescape
from html.parser import HTMLParser
import json
import math
import re
from typing import Any, Callable, Optional
from urllib.parse import urlencode, urljoin, urlparse

import httpx
from app.services.prescription_engine import PRICE_SOURCES
from app.services.rx_integrated import _host_ok

# Only retail stores. TTAC and Pillix are audited as directories/official sources
# rather than misrepresented as publicly accessible automated retail APIs.
RETAILERS = {s['id']: s for s in PRICE_SOURCES if s['type'] == 'retailer'}
ALIASES = {
    'maropitant': ('maropitant', 'cerenia', 'ماروپیتانت', 'سرنیا'),
    'metoclopramide': ('metoclopramide', 'متوکلوپرامید'),
    'ondansetron': ('ondansetron', 'اندانسترون'),
    'sucralfate': ('sucralfate', 'سوکرالفیت'),
    'fenbendazole': ('fenbendazole', 'فنبندازول', 'panacur'),
}
MAX_PRODUCT_LINKS = 3
_CACHE: dict[str, tuple[datetime, dict[str, Any]]] = {}
_CACHE_LOCK = asyncio.Lock()
CACHE_TIME = timedelta(minutes=20)


def _num(v: Any) -> Optional[float]:
    try:
        x = float(v)
        return x if math.isfinite(x) and 0 < x < 1e12 else None
    except (TypeError, ValueError):
        return None


def _normalize(text: str) -> str:
    return re.sub(r'\s+', ' ', str(text or '').translate(
        str.maketrans('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩', '01234567890123456789'))).lower()


def _line_sku(line: dict[str, Any]) -> Optional[dict[str, Any]]:
    ingredient = str(line.get('ingredient') or '').strip().lower()
    strength = _num(line.get('strength_mg_per_unit') or line.get('reference_strength_mg_per_ml'))
    form = str(line.get('form') or '').lower()
    if any(x in form for x in ('inj', 'amp', 'vial', 'تزریق')):
        form = 'injection'
    elif any(x in form for x in ('tab', 'tablet')):
        form = 'tablet'
    elif any(x in form for x in ('syr', 'susp')):
        form = 'syrup'
    elif 'drop' in form:
        form = 'drop'
    unit = str(line.get('unit_kind') or '').lower()
    if unit.startswith('ml') or unit.startswith('m[l') or (form == 'injection' and not unit):
        unit = 'ml'
    if unit in ('tablet','capsule', 'drop', 'vial','ampoule', 'ml') and ingredient and strength:
        return {'ingredient':ingredient, 'strength':strength, 'unit':unit,
                'form':form, 'units_per_dose':_num(line.get('units_per_dose')),
                'reference_max_duration_days':line.get('reference_max_duration_days'),
                'duration_days':line.get('duration_days'),
                'administrations_per_day':_num(line.get('administrations_per_day'))}
    return None


def _identity_ok(text: str, sku: dict[str, Any]) -> bool:
    name = _normalize(text)
    names = ALIASES.get(sku['ingredient'], (sku['ingredient'],))
    if not any(alias in name for alias in names):
        return False
    if sku['form'] == 'injection' and not any(x in name for x in
          ('injection','injectable','inject', 'inj.', 'vial','ampoule','تزریق','آمپول','ویال')):
        return False
    if sku['form'] == 'tablet' and not any(x in name for x in ('tablet','tab.', 'قرص')):
        return False
    if sku['form'] == 'syrup' and not any(x in name for x in ('syrup', 'suspension','شربت','سوسپانسیون')):
        return False
    s = sku['strength']
    v = re.escape(format(s, '.8g'))
    if sku['unit'] == 'ml':
        patterns = (rf'(?<![\d.]){v}\s*(?:mg|میلی\s*گرم)\s*(?:/|در|per)\s*(?:ml|m[lL]|میلی\s*لیتر)',)
    elif sku['unit'] in ('tablet','capsule'):
        patterns = (rf'(?<![\d.]){v}\s*(?:mg|میلی\s*گرم)(?:\s*(?:/|per)\s*(?:tablet|tab|capsule|قرص))?',)
    else:
        patterns = (rf'(?<![\d.]){v}\s*(?:mg|میلی\s*گرم)\s*(?:/|per)\s*{re.escape(sku["unit"])}',)
    return any(re.search(p, name, re.I) for p in patterns)


def _pack_from_text(text: str, sku: dict[str, Any]) -> Optional[float]:
    text = _normalize(text)
    if sku['unit'] == 'ml':
        patterns = (r'(?<![/\w])(?:volume|size|pack|vial|ویال|حجم|بطری)?\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:ml|میلی\s*لیتر)\b',
                    r'(\d+(?:\.\d+)?)\s*(?:ml|میلی\s*لیتر)\s*(?:vial|ampoule|ویال|آمپول)')
    else:
        patterns = (r'(\d+(?:\.\d+)?)\s*(?:tablets|tabs|capsules|قرص|کپسول|عدد)\b',)
    for pat in patterns:
        for match in re.finditer(pat, text, flags=re.I):
            p = _num(match.group(1))
            if p and 0.5 <= p <= 1000:
                return p
    return None


class _HtmlProducts(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self._script = False
        self._buffer = ''
        self.products: list[dict[str, Any]] = []
        self.links: list[tuple[str,str]] = []
        self._link: Optional[str] = None
        self._link_text = ''
    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        if tag == 'script' and 'ld+json' in str(data.get('type','')).lower():
            self._script=True; self._buffer=''
        if tag == 'a' and data.get('href'):
            self._link = str(data['href'])[:1200]; self._link_text = ''
    def handle_data(self, data):
        if self._script and len(self._buffer) < 180000: self._buffer += data
        if self._link and len(self._link_text) < 250: self._link_text += data
    def handle_endtag(self, tag):
        if tag == 'a' and self._link:
            self.links.append((self._link, self._link_text))
            self._link = None
        if tag == 'script' and self._script:
            self._script = False
            try: node = json.loads(unescape(self._buffer))
            except ValueError: return
            self.products.extend(_walk_products(node))


def _walk_products(node: Any) -> list[dict[str, Any]]:
    if isinstance(node,list): return [p for x in node for p in _walk_products(x)]
    if not isinstance(node,dict): return []
    found = []
    kind = node.get('@type')
    if kind == 'Product' or (isinstance(kind,list) and 'Product' in kind): found.append(node)
    for field in ('@graph','mainEntity','hasVariant','itemListElement'):
        if field in node: found.extend(_walk_products(node[field]))
    return found


def _offer_record(raw: dict[str, Any], sku: dict[str, Any], source_id: str,
                  url: str, observed_at: str) -> Optional[dict[str, Any]]:
    title = re.sub('<[^>]*>', ' ', str(raw.get('name') or ''))
    description = re.sub('<[^>]*>', ' ', str(raw.get('description') or ''))
    text = title+' '+description
    if not _identity_ok(text, sku): return None
    pack = _pack_from_text(text,sku)
    if not pack: return None
    offers = raw.get('offers')
    if isinstance(offers, dict): offers = [offers]
    if not isinstance(offers, list): return None
    for item in offers:
        if not isinstance(item,dict): continue
        currency = str(item.get('priceCurrency') or '').upper()
        val = _num(item.get('price'))
        if not val or currency not in ('IRR','IRT','TOMAN'): continue
        availability = str(item.get('availability') or '').lower()
        if not availability.endswith('instock') or availability.endswith('outofstock'): continue
        return {'ingredient':sku['ingredient'], 'form':sku['form'], 'unit_kind':sku['unit'],
            'strength_mg_per_unit':sku['strength'], 'pack_units':pack, 'product_name':title[:180],
            'brand':str(raw.get('brand') or '')[:80],
            'price_toman':round(val/10 if currency=='IRR' else val),
            'source_id':source_id,'url':url,'observed_at':observed_at,
            'status':'online_product_offer_unverified', 'stock':'listed_in_stock',
            'raw_currency':currency,
            'note':'Seller-advertised price; check shelf stock, legal authorization, and final checkout.'}
    return None


def parse_jsonld_price(html: str, sku: dict[str, Any], source_id: str,
                       url: str, observed_at: str) -> list[dict[str, Any]]:
    parser = _HtmlProducts()
    parser.feed(html[:500000])
    return [x for obj in parser.products if
            (x:=_offer_record(obj,sku,source_id,url,observed_at)) is not None]


def _shop_api_products(payload: Any, sku: dict[str, Any], source_id: str,
                       observed_at: str) -> list[dict[str, Any]]:
    if not isinstance(payload,list): return []
    offers=[]
    for entry in payload[:15]:
        if not isinstance(entry,dict) or entry.get('is_in_stock') is not True: continue
        text = re.sub('<[^>]*>',' ', str(entry.get('name') or '')+' '+str(entry.get('description') or '')+
                      ' '+str(entry.get('short_description') or ''))
        if not _identity_ok(text,sku): continue
        pack = _pack_from_text(text, sku)
        if not pack: continue
        prices = entry.get('prices') or {}
        if not isinstance(prices,dict): continue
        val = _num(prices.get('price'))
        currency = str(prices.get('currency_code') or '').upper()
        digits = prices.get('currency_minor_unit')
        if val is None or currency not in ('IRR','IRT') or not isinstance(digits,int) or digits < 0 or digits > 4: continue
        url=str(entry.get('permalink') or '')
        if not _host_ok(source_id,url): continue
        toman=val/(10**digits)/(10 if currency=='IRR' else 1)
        if not _num(toman): continue
        offers.append({'ingredient':sku['ingredient'],'form':sku['form'], 'unit_kind':sku['unit'],
            'strength_mg_per_unit':sku['strength'], 'pack_units':pack,
            'product_name':str(entry.get('name') or '')[:180], 'brand':'',
            'price_toman':round(toman), 'source_id':source_id, 'url':url,
            'observed_at':observed_at, 'status':'online_product_offer_unverified',
            'stock':'listed_in_stock','raw_currency':currency,
            'note':'Seller-advertised WooCommerce price, not verified at checkout.'})
    return offers


async def discover_prices_for_line(line: dict[str, Any], *,
        retrieve: Optional[Callable[[str], Any]] = None,
        sites: Optional[dict[str,dict[str,str]]] = None,
        now: Optional[datetime] = None) -> dict[str, Any]:
    """No user input. Collect exact product offers or explicit per-source failures.

    retrieve injectable for deterministic offline tests. Only allowlisted URLs
    are requested, with no redirect following by default.
    """
    now=now or datetime.now(timezone.utc)
    sku=_line_sku(line)
    if not sku:
        return {'status':'sku_not_specified','offers':[], 'suppliers':[],
                'note':'Exact active ingredient, form, strength and administration unit are needed.'}
    sources=sites if sites is not None else RETAILERS
    aliases=ALIASES.get(sku['ingredient'],(sku['ingredient'],))
    term=aliases[0]
    stamp=now.isoformat()
    async def fetch(client: httpx.AsyncClient,url: str):
        if retrieve is not None: return await retrieve(url)
        response=await client.get(url, follow_redirects=False)
        if response.status_code != 200: return None
        if len(response.content) > 1200000: return None
        typ=response.headers.get('content-type','')
        if 'json' in typ: return response.json()
        return response.text if 'html' in typ else None
    async def one(client, sid, info):
        origin=info['url'].rstrip('/')
        # Keep separate site status for each attempted supplier.
        state={'source_id':sid,'homepage':origin,'status':'no_exact_product_offer',
               'search_attempted':True,'product_pages_scanned':0,'offer_count':0}
        results=[]
        try:
            # Store API is public on some (not all) WooCommerce sites.
            api=urljoin(origin+'/', 'wp-json/wc/store/v1/products?'+urlencode({'search':term,'per_page':8}))
            if _host_ok(sid,api):
                payload=await fetch(client,api)
                if isinstance(payload,list):
                    results.extend(_shop_api_products(payload,sku,sid,stamp))
            # Public shop search in both Latin and Persian when the drug has a
            # recorded Persian alias. Search pages are *not* price evidence;
            # product details still need explicit JSON-LD exact-SKU matching.
            search_terms=[term]
            persian=next((v for v in aliases if any('\u0600' <= c <= '\u06ff' for c in v)),None)
            if persian and persian != term: search_terms.append(persian)
            candidate_links=[]
            search_responses=0
            for query_term in search_terms:
                url=origin+'/?'+urlencode({'s':query_term,'post_type':'product'})
                html=await fetch(client,url)
                if not isinstance(html,str): continue
                search_responses+=1
                parser=_HtmlProducts(); parser.feed(html[:500000])
                for obj in parser.products:
                    product_url=str(obj.get('url') or '')
                    if _host_ok(sid,product_url):
                        offer=_offer_record(obj,sku,sid,product_url,stamp)
                        if offer: results.append(offer)
                for href,label in parser.links:
                    candidate=urljoin(origin+'/',href)
                    path=urlparse(candidate).path.lower()
                    if not _host_ok(sid,candidate) or candidate in candidate_links: continue
                    if any(block in path for block in ('/product-category/', '/category/','/cart','/checkout')):continue
                    if not any(p in path for p in ('/product/','/products/','/shop/','/محصول/')):continue
                    if not any(a in _normalize(label+' '+href) for a in aliases): continue
                    candidate_links.append(candidate)
                    if len(candidate_links)>=MAX_PRODUCT_LINKS: break
            for candidate in candidate_links[:MAX_PRODUCT_LINKS]:
                detail=await fetch(client,candidate)
                state['product_pages_scanned']+=1
                if isinstance(detail,str):
                    results.extend(parse_jsonld_price(detail,sku,sid,candidate,stamp))
            uniq={r['url']:r for r in results}
            results=list(uniq.values())
            state['offer_count']=len(results)
            if results: state['status']='exact_product_offer_found'
            elif search_responses == 0 and not results: state['status']='search_restricted_or_unavailable'
        except (httpx.HTTPError, ValueError, OSError, UnicodeError, TypeError) as exc:
            state['status']='search_error'
            state['error_type']=type(exc).__name__
        return results,state
    async with httpx.AsyncClient(timeout=httpx.Timeout(4.5),trust_env=False,
      headers={'User-Agent':'AssistantVet/27 product-price comparison (no bypass)','Accept':'text/html, application/json'}) as client:
        audits=await asyncio.gather(*(one(client,sid,info) for sid,info in sources.items()))
    offers=[p for rs,_ in audits for p in rs]
    # Keep supplier discovery order for an identifiable reference listing;
    # Economic Choice independently chooses the lowest price.
    directory_status=[{'source_id':sid, 'status':'no_verified_public_sku_price_api',
                       'search_attempted':False,'offer_count':0,
                       'product_pages_scanned':0} for sid in ('ttac','pillix')]
    return {'status':'offers_found' if offers else 'no_exact_verified_price_found',
            'offers':offers[:15], 'suppliers':[a for _,a in audits]+directory_status,
            'checked_at':stamp,'sku':sku,
            'note':'Automated vendor-listed observations; not authoritative pharmacy prices or established therapeutic equivalence.'}


async def automatic_price_batch(lines: list[dict[str,Any]], *,
        retrieve=None, sites=None, now=None) -> dict[str,Any]:
    """Bound max eight distinct line SKUs; do not auto-query arbitrary drugs."""
    unique={}
    for line in lines[:18]:
        sku=_line_sku(line)
        if sku:
            key=(sku['ingredient'], sku['form'],sku['unit'],sku['strength'])
            unique.setdefault(key,line)
    jobs=await asyncio.gather(*(discover_prices_for_line(line, retrieve=retrieve,sites=sites,now=now)
                               for line in list(unique.values())[:8]))
    mapping={key:job for key,job in zip(list(unique)[:8], jobs)}
    return {'status':'completed','by_sku':mapping,'supplier_count':len(sites or RETAILERS)+2,
            'offers_count':sum(len(r['offers']) for r in jobs),
            'checked_at':(now or datetime.now(timezone.utc)).isoformat(),
            'directories_not_claimed_as_price_apis':['ttac','pillix']}
