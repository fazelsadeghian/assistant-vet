"""Assistant Vet v26 -- explicit Iranian supplier connector audit / SKU quote registry.

Supplier home page connectivity is NOT a medicine-price API and never produces a
price. A price must come from an exact SKU product URL with machine-readable
price and product identity, or an explicitly marked clinician-entered quote.
All amounts use TOMAN (10 IRR=1 toman); expiry and provenance are preserved.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
from html import unescape
from html.parser import HTMLParser
import json
import math
import os
from pathlib import Path
import re
import threading
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

import httpx
from app.services.prescription_engine import PRICE_SOURCES
from app.services.rx_integrated import _host_ok

OFFERS_PATH = Path(os.getenv('AV_RX_V26_PRODUCT_QUOTES', 'data/prescription/product_quotes_v26.json'))
_DATA_LOCK = threading.RLock()
KNOWN = {row['id']: row for row in PRICE_SOURCES}
MAX_AGE = timedelta(days=14)


def _number(value: Any) -> Optional[float]:
    try:
        val = float(value)
        if not math.isfinite(val) or not 0 < val < 1e12:
            return None
        return val
    except (ValueError, TypeError):
        return None


def _iso(raw: str) -> Optional[datetime]:
    try:
        dt = datetime.fromisoformat(raw.replace('Z', '+00:00'))
        return dt.astimezone(timezone.utc) if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except (ValueError, TypeError, AttributeError):
        return None


def _clean(value: Any, limit: int = 120) -> str:
    return re.sub(r'\s+', ' ', str(value or '')).strip()[:limit]


def _valid_ingredient(value: str) -> bool:
    return bool(re.fullmatch(r'[A-Za-z][A-Za-z\- ]{2,49}', value))


def _read_offers(path: Optional[Path] = None) -> list[dict[str, Any]]:
    path = path or OFFERS_PATH
    try:
        payload = json.loads(path.read_text(encoding='utf-8'))
        rows = payload.get('offers', []) if isinstance(payload, dict) else []
        return [row for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []
    except (OSError, ValueError):
        return []


def save_product_quote(raw: dict[str, Any], *, path: Optional[Path] = None,
                       now: Optional[datetime] = None) -> dict[str, Any]:
    """Persist an UNVERIFIED price claim, not a verified commercial offer."""
    now = now or datetime.now(timezone.utc)
    path = path or OFFERS_PATH
    if len(json.dumps(raw, ensure_ascii=False)) > 6500:
        raise ValueError('Quote payload too long')
    name = _clean(raw.get('product_name'), 140)
    ingredient = _clean(raw.get('ingredient'), 50).lower()
    form = _clean(raw.get('form'), 35).lower()
    source = _clean(raw.get('source_id'), 40).lower()
    url = _clean(raw.get('url'), 1600)
    entered_by = _clean(raw.get('entered_by'), 80)
    strength = _number(raw.get('strength_mg_per_unit'))
    package = _number(raw.get('pack_units'))
    price = _number(raw.get('price'))
    unit = _clean(raw.get('unit_kind'), 20).lower()
    cur = _clean(raw.get('currency') or 'TOMAN', 10).upper()
    # No automatic therapeutic, regulatory or product equivalence inference.
    if (not _valid_ingredient(ingredient) or len(name) < 5 or not form or not entered_by
        or not _host_ok(source, url) or raw.get('confirm_exact_product') is not True
        or ingredient not in name.lower() and not _clean(raw.get('active_ingredient_on_label'), 50).lower() == ingredient
        or strength is None or package is None or package > 100000 or price is None
        or cur not in ('TOMAN', 'IRR') or unit not in ('ml','tablet','capsule','ampoule','drop','sachet','vial')
        or raw.get('in_stock') is not True):
        raise ValueError('Exact ingredient, dosage form, strength, pack, stock and source URL must be confirmed')
    if form.lower() in ('injection','inj','ampoule') and unit not in ('ml', 'ampoule', 'vial'):
        raise ValueError('Incompatible injection unit')
    price_toman = round(price / 10 if cur == 'IRR' else price)
    quote = {'ingredient': ingredient, 'product_name': name, 'form': form,
             'strength_mg_per_unit': strength, 'pack_units': package, 'unit_kind': unit,
             'price_toman': price_toman, 'source_id': source, 'url': url,
             'entered_by': entered_by, 'observed_at': now.isoformat(),
             'status': 'manually_observed_not_independently_verified',
             'in_stock_claimed': True, 'preferred': raw.get('preferred') is True,
             'product_id': _clean(raw.get('product_id'), 100) or None,
             'brand': _clean(raw.get('brand'), 80),
             'note': 'Source-linked clinician observation; validate identity, legality, expiration and final price.'}
    with _DATA_LOCK:
        rows = [r for r in _read_offers(path) if (r.get('url'), r.get('ingredient')) != (url, ingredient)]
        rows.append(quote)
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix('.tmp')
        temp.write_text(json.dumps({'offers': rows[-500:]}, ensure_ascii=False, indent=2), encoding='utf-8')
        os.replace(temp, path)
    return quote


def comparable_quotes(line: dict[str, Any], *, now: Optional[datetime] = None,
                      quotes: Optional[list[dict[str, Any]]] = None) -> dict[str, Any]:
    """Prices are comparable only for exactly the same dosage-unit definition."""
    now = now or datetime.now(timezone.utc)
    ingredient = str(line.get('ingredient') or '').lower()
    form = str(line.get('form') or '').lower()
    if form.startswith('inj.') or form.startswith('amp.'):
        form = 'injection'
    unit = str(line.get('unit_kind') or '').lower()
    if unit.startswith('ml '): unit = 'ml'
    if unit.startswith('ml('): unit = 'ml'
    strength = _number(line.get('strength_mg_per_unit') or line.get('reference_strength_mg_per_ml'))
    units = _number(line.get('units_per_dose'))
    pack = _number(line.get('pack_units'))
    out: dict[str, Any] = {'status': 'missing_comparable_product', 'quotes': [],
        'cost_range_toman': None, 'usd_range': None, 'price_approved': False,
        'note': 'One supplier price is not a clinically interchangeable treatment; no unverified savings promise.'}
    if not ingredient or strength is None or units is None or not unit:
        return out
    for quote in quotes if quotes is not None else _read_offers():
        observed = _iso(quote.get('observed_at'))
        if not observed or not timedelta(minutes=-10) <= now - observed <= MAX_AGE:
            continue
        if quote.get('ingredient') != ingredient or quote.get('unit_kind') != unit:
            continue
        if abs(float(quote.get('strength_mg_per_unit') or 0) - strength) > 1e-8:
            continue
        if pack and abs(float(quote.get('pack_units') or 0) - pack) > 1e-8:
            continue
        if form and quote.get('form') != form:
            continue
        if not _host_ok(str(quote.get('source_id')), str(quote.get('url'))):
            continue
        cost = math.ceil(units / float(quote['pack_units'])) * float(quote['price_toman'])
        out['quotes'].append({**quote, 'purchase_cost_one_administration_toman': round(cost)})
    out['quotes'].sort(key=lambda q: q['purchase_cost_one_administration_toman'])
    if out['quotes']:
        prices = [r['purchase_cost_one_administration_toman'] for r in out['quotes']]
        out.update(status='indicative_manual_quotes_only', cost_range_toman=[min(prices),max(prices)])
    return out


async def audit_supplier_websites(*, request_site=None) -> dict[str, Any]:
    """Explicitly requested connectivity checks. NEVER call site access an API integration."""
    async def one(client: httpx.AsyncClient, source: dict[str, str]) -> dict[str, Any]:
        item = {'id': source['id'], 'name': source['name'], 'homepage': source['url'],
                'pricing_api': 'no_public_authenticated_api_verified',
                'price_fetch_verified': False, 'status': 'not_checked'}
        try:
            if request_site is not None:
                status = await request_site(source['url'])
                code = int(status)
            else:
                response = await client.get(source['url'], follow_redirects=False)
                code = response.status_code
                # HTTP redirect is not proof of successful vendor access.
                if code in (301,302,303,307,308):
                    location = response.headers.get('location', '')
                    parsed = urlparse(location)
                    if not parsed.scheme and location.startswith('/'):
                        location = source['url'].rstrip('/') + location
                    if _host_ok(source['id'], location) or location.rstrip('/') == source['url'].rstrip('/'):
                        next_response = await client.get(location, follow_redirects=False)
                        code = next_response.status_code
            item['http_status'] = code
            item['status'] = 'site_reachable' if 200 <= code < 300 else 'site_restricted_or_unreachable'
        except (httpx.HTTPError, OSError, ValueError, TypeError) as exc:
            item['status'] = 'site_unreachable'
            item['error_type'] = type(exc).__name__
        return item
    async with httpx.AsyncClient(timeout=httpx.Timeout(5.5),
        headers={'User-Agent':'AssistantVet/26 vendor-healthcheck (not price scraper)'}) as client:
        entries = await asyncio.gather(*(one(client, r) for r in PRICE_SOURCES))
    return {'status': 'completed', 'checked_at': datetime.now(timezone.utc).isoformat(),
            'sources': entries, 'note': ('Webpage availability does not grant automated price APIs. '
                'Without a machine-readable exact-SKU product offer, price is unknown.')}

class _ProductJSONLD(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.inside = False
        self.buffer = ''
        self.scripts: list[str] = []
    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]):
        props = dict(attrs)
        if tag.lower() == 'script' and 'ld+json' in str(props.get('type') or '').lower():
            self.inside = True
            self.buffer = ''
    def handle_data(self, data: str):
        if self.inside and len(self.buffer) + len(data) <= 80000:
            self.buffer += data
    def handle_endtag(self, tag: str):
        if tag.lower() == 'script' and self.inside:
            self.inside = False
            self.scripts.append(self.buffer)


def _walk_products(node: Any):
    if isinstance(node, list):
        for item in node:
            yield from _walk_products(item)
    elif isinstance(node, dict):
        kind = node.get('@type')
        if kind == 'Product' or (isinstance(kind,list) and 'Product' in kind):
            yield node
        for key in ('@graph', 'mainEntity','hasVariant'):
            if key in node:
                yield from _walk_products(node[key])


def inspect_exact_sku_markup(markup: str, sku: dict[str,Any]) -> dict[str, Any]:
    """Only explicit JSON-LD Product offers. No hidden/guessed price scraping."""
    ingredient = _clean(sku.get('ingredient'),50).lower()
    strength = _number(sku.get('strength_mg_per_unit'))
    pack = _number(sku.get('pack_units'))
    unit = _clean(sku.get('unit_kind'),18).lower()
    if not _valid_ingredient(ingredient) or strength is None or pack is None or unit not in (
            'ml','tablet','capsule','ampoule','drop','sachet','vial'):
        raise ValueError('Need exact ingredient, strength, product count/volume and unit')
    parser = _ProductJSONLD()
    parser.feed(markup[:500000])
    for script in parser.scripts[:20]:
        try:
            decoded = json.loads(unescape(script))
        except (ValueError, TypeError):
            continue
        for item in _walk_products(decoded):
            title = _clean(item.get('name'),160)
            description = _clean(item.get('description'),750)
            all_text = (title + ' ' + description).lower()
            if ingredient not in all_text:
                continue
            # Require an explicit unambiguous strength AND exact package size.
            numbers = all_text.translate(str.maketrans('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩','01234567890123456789'))
            a = re.escape(format(strength,'.8g'))
            b = re.escape(format(pack,'.8g'))
            if not re.search(r'(?<![\d.])'+a+r'\s*(?:mg|میلی\s*گرم)\s*(?:/|per)\s*(?:ml|m[lL]|'+re.escape(unit)+r')\b', numbers, re.I):
                continue
            if not re.search(r'(?<![\d.])'+b+r'\s*(?:'+re.escape(unit)+r'|میلی\s*لیتر)\b', numbers, re.I):
                continue
            offers = item.get('offers')
            for offer in offers if isinstance(offers,list) else [offers]:
                if not isinstance(offer,dict):continue
                currency = str(offer.get('priceCurrency') or '').upper()
                price = _number(offer.get('price'))
                if currency not in ('IRR','IRT') or price is None:
                    continue
                if str(offer.get('availability') or '').lower().endswith('outofstock'):
                    continue
                return {'status':'source_page_price_preview_not_verified',
                        'product_name':title, 'ingredient':ingredient,'price_toman':round(price/(10 if currency=='IRR' else 1)),
                        'strength_mg_per_unit':strength, 'pack_units':pack, 'unit_kind':unit,
                        'warning':'Preview only: check actual shelf stock, license, currency, strength and final purchase price.'}
    return {'status':'no_exact_sku_price_exposed', 'price_toman':None,
            'warning':'The page has no unambiguous machine-readable Product/Offer for this exact SKU.'}


async def preview_exact_supplier_offer(raw: dict[str,Any], *, retrieve=None) -> dict[str,Any]:
    sid = _clean(raw.get('source_id'),30)
    url = _clean(raw.get('url'),1600)
    if not _host_ok(sid,url):
        raise ValueError('Only exact HTTPS product pages on listed Iranian sources are allowed')
    if retrieve is None:
        async with httpx.AsyncClient(timeout=httpx.Timeout(7.0),follow_redirects=False,
                                     headers={'User-Agent':'AssistantVet/26 exact-SKU verification'}) as client:
            try:
                resp = await client.get(url)
                if resp.status_code != 200 or 'text/html' not in resp.headers.get('content-type',''):
                    return {'status':'source_page_unavailable','price_toman':None,'source_id':sid}
                text = resp.text[:500000]
            except httpx.HTTPError:
                return {'status':'source_page_unavailable','price_toman':None,'source_id':sid}
    else:
        text = await retrieve(url)
    return {**inspect_exact_sku_markup(text,raw),'source_id':sid,'url':url}
