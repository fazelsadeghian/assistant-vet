"""Assistant Vet integrated dual-Rx *review workspace* (v24).

Patient safety: no automatically signed prescriptions, no invented substitutions,
prices, formulations, clinical dosing, or unsupported paper-based extrapolation.
The *only* built-in sample source-to-patient pathway is a tightly scoped adult-
dog acute-vomiting maropitant label transcription, backed by a local Plumb row
AND the official Zoetis/DailyMed label. All outputs remain for clinician review.

Verified local protocols in prescription_engine.py continue to work unchanged.
"""
from __future__ import annotations

import json
import math
import os
import re
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from app.services.prescription_engine import PRICE_SOURCES, make_prescription_plan

RATE_URL = 'https://nerkhara.com/api/v1/latest/usd.json'
FDA_LABEL_URL = 'https://dailymed.nlm.nih.gov/dailymed/fda/fdaDrugXsl.cfm?setid=6aeda328-97c9-4868-8ecb-b3a4dcdbc0a0&type=display'
PRICE_FILE = Path(os.getenv('AV_RX_LOCAL_PRICE_FILE', 'data/prescription/v24_price_entries.json'))
# Peer-reviewed randomized trials with reported SC dosage in clinically vomiting dogs.
# These were checked against PubMed abstracts; they are not guarantees of safety
# for an unexamined patient and do not establish interchangeable alternatives.
MAROPITANT_TRIALS = [
    {'title': 'Ramsey et al. 2008 — randomized placebo-controlled treatment of vomiting in dogs',
     'url': 'https://pubmed.ncbi.nlm.nih.gov/19000277/', 'locator': 'PMID 19000277 · DOI 10.1111/j.1365-2885.2008.00992.x',
     'population': 'Dogs with acute vomiting of diverse etiologies; multicenter randomized trial',
     'reported_dose': '1 mg/kg SC initial dose', 'status': 'article_regimen_matches_label_for_population'},
    {'title': 'de la Puente-Redondo et al. 2007 — maropitant vs metoclopramide for ongoing canine emesis',
     'url': 'https://pubmed.ncbi.nlm.nih.gov/17286662/', 'locator': 'PMID 17286662 · DOI 10.1111/j.1748-5827.2006.00321.x',
     'population': 'Dogs with ongoing vomiting; European multicentre trial',
     'reported_dose': 'Maropitant 1 mg/kg SC once daily, up to 5 days',
     'status': 'article_regimen_matches_label_for_population'},
]

PRICE_SOURCE_HOSTS = {item['id']: (urlparse(item['url']).hostname or '').removeprefix('www.') for item in PRICE_SOURCES}
RATE_MAX_AGE = timedelta(hours=2)
QUOTE_MAX_AGE = timedelta(days=14)
_SAVED_RATE: dict[str, Any] = {}
_RATE_LOCK = threading.Lock()
_FILE_LOCK = threading.Lock()


def _positive(v: Any) -> Optional[float]:
    try:
        x = float(v)
        return x if 0 < x < 1e12 and math.isfinite(x) else None
    except (ValueError, TypeError):
        return None


def _time(raw: Any) -> Optional[datetime]:
    if not isinstance(raw, str):
        return None
    try:
        dt = datetime.fromisoformat(raw.replace('Z', '+00:00'))
        return (dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)).astimezone(timezone.utc)
    except ValueError:
        return None


def _host_ok(source_id: str, url: str) -> bool:
    host = PRICE_SOURCE_HOSTS.get(source_id)
    parsed = urlparse(url)
    return bool(host and parsed.scheme == 'https' and parsed.hostname in {host, 'www.' + host}
                and not parsed.username and not parsed.password and not parsed.fragment
                and len(url) < 1500 and parsed.path not in ('', '/')
                and parsed.port in (None, 443))


def _fetch_json(url: str) -> Dict[str, Any]:
    # Only the constant, vetted rate endpoint is used; no user-controlled URL.
    if url != RATE_URL:
        raise ValueError('Unsupported rate endpoint')
    req = Request(url, headers={'User-Agent': 'AssistantVet/24 price-context', 'Accept': 'application/json'})
    with urlopen(req, timeout=3) as resp:
        if resp.status != 200:
            raise ValueError('Rate HTTP status')
        raw = resp.read(80_001)
    if len(raw) > 80_000:
        raise ValueError('Oversize rate response')
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError('Invalid rate response')
    return data


def fetch_usd_toman(*, now: Optional[datetime] = None,
                    fetch: Callable[[str], Dict[str, Any]] = _fetch_json) -> Dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    with _RATE_LOCK:
        cache_until = _SAVED_RATE.get('expires')
        if fetch is _fetch_json and cache_until and now < cache_until:
            return dict(_SAVED_RATE['rate'])
    result = {'status': 'unavailable', 'toman_per_usd': None, 'source': 'NerkhAra',
              'url': 'https://nerkhara.com/en/api/', 'checked_at': now.isoformat()}
    try:
        payload = fetch(RATE_URL)
        item = payload.get('item', {})
        price = _positive(item.get('price'))
        stamp = _time(item.get('updated_utc'))
        if (item.get('id') == 'usd' and item.get('unit') == 'IRT' and price is not None and stamp and
                timedelta(minutes=-10) <= now - stamp <= RATE_MAX_AGE and item.get('stale') is False):
            result.update(status='current', toman_per_usd=round(price, 2), updated_at=stamp.isoformat(),
                          source_count=item.get('sources'), source_page='https://nerkhara.com/en/dollar/')
        else:
            result['status'] = 'stale_or_invalid'
            result['updated_at'] = stamp.isoformat() if stamp else None
    except (ValueError, OSError, TimeoutError, TypeError, KeyError, json.JSONDecodeError) as exc:
        result['status'] = 'unavailable'
        result['note'] = f'FX fetch failed ({type(exc).__name__}); no USD estimate reported.'
    with _RATE_LOCK:
        if fetch is _fetch_json:
            _SAVED_RATE['expires'] = now + timedelta(minutes=5)
            _SAVED_RATE['rate'] = result
    return result


def save_quote(raw: Dict[str, Any], *, path: Optional[Path] = None,
               now: Optional[datetime] = None) -> Dict[str, Any]:
    """Local opt-in clinician-entered retail observation, not independent verification."""
    now = now or datetime.now(timezone.utc)
    path = path or PRICE_FILE
    source = str(raw.get('source_id') or '').lower().strip()
    url = str(raw.get('url') or '').strip()
    name = str(raw.get('product_name') or '').strip()
    brand = str(raw.get('brand') or '').strip()
    checker = str(raw.get('entered_by') or '').strip()
    currency = str(raw.get('currency') or 'TOMAN').upper()
    mg_ml = _positive(raw.get('strength_mg_per_ml'))
    pack_ml = _positive(raw.get('pack_ml'))
    amount = _positive(raw.get('price'))
    if (not _host_ok(source, url) or len(name) < 5 or len(name) > 130 or len(brand) > 80 or
            not checker or len(checker) > 100 or raw.get('confirm_exact_product') is not True or
            not re.search(r'maropitant|cerenia|ماروپیتانت|سرنیا', name, re.I) or
            currency not in ('TOMAN', 'IRR') or amount is None or mg_ml != 10.0 or
            pack_ml is None or not 1 <= pack_ml <= 100):
        raise ValueError('Quote must have an exact maropitant 10 mg/mL injectable SKU, verified product page, pack size and confirmation.')
    if len(json.dumps(raw, ensure_ascii=False)) > 5500:
        raise ValueError('Input too large')
    quote = {
        'product_id': 'maropitant_injection_10mg_ml', 'ingredient': 'maropitant',
        'product_name': name, 'brand': brand or name, 'source_id': source,
        'url': url, 'strength_mg_per_ml': 10.0, 'pack_ml': float(pack_ml),
        'price_toman': round(amount / 10 if currency == 'IRR' else amount),
        'observed_at': now.isoformat(), 'entered_by': checker,
        'status': 'clinician_entered_unverified_external',
        'preferred': raw.get('preferred') is True,
        'note': 'Manually transcribed; not validated automatically against source page or stock.',
    }
    with _FILE_LOCK:
        original = _read_quotes(path)
        original = [r for r in original if not (r.get('source_id') == source and r.get('url') == url)]
        original.append(quote)
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix('.tmp')
        temp.write_text(json.dumps({'observations': original[-200:]}, ensure_ascii=False, indent=2), encoding='utf-8')
        os.replace(temp, path)
    return quote


def _read_quotes(path: Optional[Path] = None) -> List[Dict[str, Any]]:
    path = path or PRICE_FILE
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        return [x for x in data.get('observations', []) if isinstance(x, dict)]
    except (OSError, ValueError, AttributeError):
        return []


def valid_offers(quotes: List[Dict[str, Any]], *, now: datetime,
                 dose_ml: float) -> List[Dict[str, Any]]:
    """Never compare a different ingredient, concentration, route or stale pack."""
    out: List[Dict[str, Any]] = []
    for quote in quotes:
        if (quote.get('product_id') != 'maropitant_injection_10mg_ml' or
                quote.get('ingredient') != 'maropitant' or
                quote.get('status') != 'clinician_entered_unverified_external'):
            continue
        if not _host_ok(str(quote.get('source_id')), str(quote.get('url'))):
            continue
        dt = _time(quote.get('observed_at'))
        if not dt or not timedelta(minutes=-10) <= now - dt <= QUOTE_MAX_AGE:
            continue
        pack = _positive(quote.get('pack_ml'))
        toman = _positive(quote.get('price_toman'))
        if pack is None or toman is None or _positive(quote.get('strength_mg_per_ml')) != 10.0:
            continue
        # Price is per purchasable vial, not per injection or automatically shared doses.
        out.append({**quote, 'packs_for_one_administration': math.ceil(dose_ml / pack),
                    'one_administration_purchase_toman': round(math.ceil(dose_ml / pack) * toman),
                    'unit_price_toman_per_ml': round(toman / pack, 2)})
    return sorted(out, key=lambda x: (x['one_administration_purchase_toman'], x['unit_price_toman_per_ml']))


def _case_text(case: Dict[str, Any], analysis: Dict[str, Any]) -> str:
    clinic = case.get('clinical') or {}
    if not isinstance(clinic, dict): clinic = {}
    items = [str(v) for v in clinic.values() if isinstance(v, (str, int, float))]
    diag = ((analysis.get('analysis') or {}).get('most_probable_diagnoses') or [])
    items += [str(x.get('diagnosis', '')) for x in diag if isinstance(x, dict)]
    return ' '.join(items).lower()


def _clinical_blockers(case: Dict[str, Any], analysis: Dict[str, Any]) -> Dict[str, Any]:
    checks = case.get('prescription_checks') or {}
    if not isinstance(checks, dict): checks = {}
    required = [
        ('obstruction_ruled_out', 'GI obstruction/foreign body not excluded'),
        ('toxin_ruled_out', 'Toxin ingestion not excluded'),
        ('hydration_assessed', 'Hydration status and need for fluid therapy not assessed'),
        ('medications_reviewed', 'Current medications / interactions not reviewed'),
        ('liver_status_reviewed', 'Hepatic disease / drug handling not reviewed'),
        ('veterinarian_examined', 'Veterinary clinical assessment not documented'),
    ]
    missing = [name for key, name in required if checks.get(key) is not True]
    text = _case_text(case, analysis)
    explicit = []
    if re.search(r'\b(obstruction|foreign body|ileus|blocked intestine)\b|انسداد|جسم خارجی', text):
        explicit.append('Possible bowel obstruction mentioned in case — STOP; assess cause')
    if re.search(r'\b(toxin|poison|toxic ingestion|intoxication)\b|مسموم|بلع سم', text):
        explicit.append('Possible toxin ingestion mentioned in case — STOP; assess cause')
    return {'status': 'blocked' if explicit else 'missing_checks' if missing else 'requires_signoff',
            'missing_checks': missing, 'red_flags': explicit,
            'automated_prescription_allowed': False,
            'note': 'Checklists cannot replace examination, diagnosis, contraindication review or veterinarian approval.'}


def _source_maropitant_row(discovery: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Accept exclusively a local Plumb dog label row with exact dose/indication.

    Official-label URL is additional independent cross-check; the local Plumb
    row provides in-database provenance, but is not independently approved.
    """
    refs = discovery.get('handbook_references') or []
    for ref in refs:
        if not isinstance(ref, dict): continue
        if ref.get('drug_name', '').lower() != 'maropitant': continue
        review = ref.get('monograph_review') or {}
        for row in review.get('source_label_rows') or []:
            if not isinstance(row, dict): continue
            if (row.get('ingredient') == 'maropitant' and row.get('species') == 'dog' and
                    row.get('indication_as_printed', '').lower() == 'prevention and treatment of acute vomiting' and
                    row.get('dose_as_printed') == '1 mg/kg' and
                    row.get('frequency_as_printed') == 'once daily' and
                    row.get('duration_as_printed') == 'Up to 5 consecutive days' and
                    row.get('minimum_age_as_printed') == '4 months' and
                    row.get('route_as_printed') == 'SC or IV (over 1 to 2 minutes)' and
                    row.get('source_id', '').startswith('kb:plumb_veterinary_drug_handbook_10e:') and
                    row.get('page_start') == 827 and
                    row.get('status') == 'source_label_row_extracted_unverified' and
                    '4 months' in row.get('exact_source_row', '') and
                    '1 mg/kg' in row.get('exact_source_row', '')):
                return row
    return None


def _article_context(discovery: Dict[str, Any]) -> List[Dict[str, Any]]:
    articles = []
    for row in (discovery.get('sources_examined') or []):
        if not isinstance(row, dict): continue
        url = str(row.get('url') or '')
        typ = str(row.get('type') or '').lower()
        if (typ in ('article', 'paper', 'pubmed', 'europepmc') or
                'pubmed' in url or 'europepmc' in url):
            if url.startswith('https://'):
                articles.append({'title': row.get('title'), 'url': url, 'locator': row.get('locator'),
                                 'status': 'topic_candidate_not_dose_verified'})
    return articles[:4]


def _review_candidate(case: Dict[str, Any], analysis: Dict[str, Any],
                      discovery: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    patient = case.get('patient') or {}
    if not isinstance(patient, dict) or str(patient.get('species', '')).lower() != 'dog':
        return None
    weight = _positive(patient.get('weight_kg'))
    age = _positive(patient.get('age_years'))
    # A model's differential diagnosis does not prove the patient's symptom.
    # Require it in the clinician-entered clinical narrative instead.
    clinical = case.get('clinical') or {}
    if not isinstance(clinical, dict): clinical = {}
    text = ' '.join(str(v) for v in clinical.values() if isinstance(v, str)).lower()
    if (weight is None or not 0 < weight < 150 or age is None or age < 4/12 or
            not re.search(r'vomit|emesis|استفراغ|تهوع', text)):
        return None
    row = _source_maropitant_row(discovery)
    if row is None: return None
    amount = round(weight, 3)  # 1 mg/kg per source; 10 mg/ml for reference CERENIA injectable.
    ml = round(amount / 10, 4)
    return {
        'ingredient': 'maropitant', 'form': 'Inj. / Amp.',
        'therapeutic_slot': 'antiemetic',
        'substitution_group': 'canine_acute_vomiting',
        'rx_abbreviation': 'Inj.', 'dose_mg_per_kg': 1.0,
        'dose_mg': amount, 'units_per_dose': ml, 'unit_kind': 'mL (reference 10 mg/mL only)',
        'reference_strength_mg_per_ml': 10.0, 'route': 'SC (reference option; verify locally)',
        'administrations_per_day': 1, 'duration_days': None,
        'reference_max_duration_days': 5,
        'notes': 'Reference arithmetic only. Duration, formulation, and patient suitability NOT approved.',
        'why': 'For canine acute vomiting: NK1 antiemetic; regimen corroborated by two controlled canine studies and the official injection label; rule out dangerous causes.',
        'evidence': [
            {'title': "Plumb’s Veterinary Drug Handbook, 10e", 'locator': 'p. 827', 'source_id': row['source_id']},
            {'title': 'FDA / CERENIA injection prescribing information', 'locator': 'Dogs ≥4 months', 'url': FDA_LABEL_URL},
            {'title': MAROPITANT_TRIALS[0]['title'], 'locator': MAROPITANT_TRIALS[0]['locator'], 'url': MAROPITANT_TRIALS[0]['url']},
            {'title': MAROPITANT_TRIALS[1]['title'], 'locator': MAROPITANT_TRIALS[1]['locator'], 'url': MAROPITANT_TRIALS[1]['url']},
        ],
        'prescription_ready': False, 'needs_vet_signoff': True,
        'dose_context': 'source_row_review_not_prescription',
        'product_id': 'maropitant_injection_10mg_ml',
        'packages_needed': None, 'cost_toman': None, 'price_evidence': {'status':'no_verified_offer'},
    }



def _attach_review_summary(plan: Dict[str, Any], case: Dict[str, Any],
                           discovery: Dict[str, Any]) -> Dict[str, Any]:
    """A factual, case-linked evidence audit, NOT a new AI prescribing model.

    Candidate mentions are explicitly not counted as validated alternatives.
    The UI can explain why a draft exists and why other names were not ordered.
    """
    clinical = case.get('clinical') or {}
    if not isinstance(clinical, dict):
        clinical = {}
    chief = str(clinical.get('chief_complaint') or clinical.get('history') or
                clinical.get('presenting_problem') or '').strip()
    if not chief:
        chief = 'No clinician-entered complaint available for review.'
    names = []
    for item in (discovery.get('candidates') or []):
        if not isinstance(item, dict):
            continue
        name = str(item.get('drug_name') or '').strip().lower()
        if name and name not in names:
            names.append(name)
    selected = [str(r.get('ingredient')) for r in
                (plan.get('first_choice') or {}).get('lines', [])
                if isinstance(r, dict) and r.get('ingredient')]
    safety = plan.get('clinical_safety') or {}
    reasons = []
    if not selected:
        reasons.append('No complete source-matched medicine protocol was available; do not construct a prescription from name mentions.')
    else:
        reasons.append('The displayed candidate comes from a source-matched dog label row; its calculation does not establish patient suitability.')
    if safety.get('red_flags'):
        reasons.append('The case contains red-flag terms that require investigation before considering a prescription.')
    elif safety.get('missing_checks'):
        reasons.append('Clinical examination and safety fields remain unverified; the output must not be signed as-is.')
    if names:
        reasons.append('Other retrieved names are literature mentions, not automatically appropriate alternatives or confirmed doses.')
    plan['case_review'] = {
        'status': 'source_linked_review_only',
        'chief_complaint': chief[:450],
        'selected_ingredients': selected,
        'mentioned_ingredients': names[:24],
        'not_selected_ingredients': [name for name in names if name not in selected][:24],
        'sources_examined': len(discovery.get('sources_examined') or []),
        'handbook_entries_examined': len(discovery.get('handbook_references') or []),
        'evidence_search_status': discovery.get('status', 'unknown'),
        'reasons': reasons,
        'approval_allowed': False,
        'clinician_next_steps': [
            'Examine the patient and document vital signs, hydration and abdominal findings.',
            'Evaluate obstruction, foreign-body and toxic exposure when clinically indicated.',
            'Plan fluid therapy only after assessing dehydration, losses and relevant electrolytes.',
            'Confirm diagnosis, available formulation, patient contraindications and drug interactions before prescribing.',
            'Set treatment duration and follow-up after clinical assessment; a source maximum is not a prescribed course.',
        ],
        'note': 'Not a diagnosis or signed prescription. Articles may be flawed or inappropriate for this patient; check full methods and drug label.',
    }
    return plan


def build_integrated_plan(case: Dict[str, Any], analysis: Dict[str, Any],
                          discovery: Dict[str, Any], *,
                          quotes: Optional[List[Dict[str, Any]]] = None,
                          fx: Optional[Dict[str, Any]] = None,
                          now: Optional[datetime] = None,
                          legacy_protocols: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    base = make_prescription_plan(case, analysis, protocols=legacy_protocols, now=now)
    checks = _clinical_blockers(case, analysis)
    base.update(schema_version=25, workspace_mode='dual_review_no_auto_sign',
                clinical_safety=checks,
                literature_evidence=_article_context(discovery),
                exchange_rate=fx or {'status':'unavailable', 'toman_per_usd':None},
                source_review_status='not_a_signed_prescription')
    base['price_policy'].update(live_price_sync=False,
        iranian_site_product_apis='not_verified',
        manual_entries_are='unverified_external_claims',
        fx_live_api='NerkhAra (no key; with timestamp and freshness check)')
    # Never downgrade or silently override existing clinician-approved formulary
    # options. They retain their own species, dose, price and substitution rules.
    if (base.get('first_choice') or {}).get('lines') and checks['red_flags']:
        base['blocked_protocol_candidates'] = [
            {'ingredient':line.get('ingredient'), 'protocol_id':line.get('protocol_id')}
            for line in base['first_choice']['lines'] if isinstance(line,dict)]
        base['first_choice'] = {'status':'blocked_red_flags','lines':[],'total_toman':None}
        base['economic'] = {'status':'blocked_red_flags','lines':[],'total_toman':None,
                            'verified_savings_toman':None}
        base['status'] = 'requires_urgent_case_review_before_any_rx'
        base['clinical_review_note'] = 'A possible obstruction or toxic exposure overrides cached protocol matches.'
        return _attach_review_summary(base,case,discovery)
    if (base.get('first_choice') or {}).get('lines'):
        base['status'] = 'clinician_reviewed_formulary_draft_requires_patient_signoff'
        base['clinical_review_note'] = 'Existing clinician-approved protocols preserved; review clinical checks before signing.'
        return _attach_review_summary(base, case, discovery)
    cand = None if checks['red_flags'] else _review_candidate(case, analysis, discovery)
    if cand is None:
        base['clinical_review_note'] = ('Potential obstruction/toxin: do not propose a dose before investigation.' if checks['red_flags'] else 'No validated source-to-patient regimen for this case; review evidence or register clinician-approved formulary protocol.')
        return _attach_review_summary(base, case, discovery)
    offers = valid_offers(quotes if quotes is not None else _read_quotes(), now=now,
                          dose_ml=float(cand['units_per_dose']))
    base['available_price_offers'] = offers
    base['literature_evidence'] = MAROPITANT_TRIALS + base['literature_evidence']
    base['clinical_review_note'] = ('Only a source-based reference arithmetic candidate is shown; '
        'no automatic order, no inferred course length, and no unsupported alternative therapy.')
    choice = dict(cand)
    economy = dict(cand)
    # An explicit product preference is required: the system does not declare
    # the cheapest product to be clinically preferred by default.
    first_quote = next((q for q in offers if q.get('preferred') is True), None)
    cheapest = next((q for q in offers if first_quote is not None and
                     (q['source_id'], q['url']) != (first_quote['source_id'], first_quote['url'])
                     and q['one_administration_purchase_toman'] <
                         first_quote['one_administration_purchase_toman']), None)
    for row, offer in ((choice, first_quote), (economy, cheapest)):
        if offer:
            row.update(product_name=offer['product_name'], brand=offer['brand'],
                cost_toman=offer['one_administration_purchase_toman'],
                packages_needed=offer['packs_for_one_administration'],
                price_evidence={'status':'single_or_multiple_clinician_entered_prices_unverified',
                                'source_id':offer['source_id'], 'source_url':offer['url'],
                                'observed_at':offer['observed_at'],
                                'price_per_pack_toman':offer['price_toman'],
                                'pack_ml':offer['pack_ml'], 'estimated_dose_purchase_only':True})
            rate = _positive((fx or {}).get('toman_per_usd')) if (fx or {}).get('status') == 'current' else None
            row['cost_usd_approx'] = round(row['cost_toman']/rate, 2) if rate else None
    savings = (choice.get('cost_toman') or 0) - (economy.get('cost_toman') or 0) if first_quote and cheapest else None
    base['first_choice'] = {'status':'clinical_review_required', 'lines':[choice],
                            'total_toman':choice.get('cost_toman'),
                            'pricing_scope':'1 administration; purchasing entire product packs if required'}
    base['economic'] = {
        'status': ('same_ingredient_price_comparison_only' if cheapest else
                   'preferred_brand_not_marked' if offers and not first_quote else
                   'no_cheaper_comparable_offer' if offers else 'price_data_missing'),
        'lines':[economy] if cheapest else [],
        'detail': ('A cheaper offer for the same active ingredient and concentration is shown only for '
                   'clinician comparison; stock, quality, authorization and equivalence remain unchecked.'
                   if cheapest else
                   'No documented cheaper option yet. Record the preferred product and a distinct '
                   'comparable supplier offer; do not replace with an unrelated drug.'),
        'total_toman':economy.get('cost_toman') if cheapest else None,
        'verified_savings_toman':None,
        'indicative_savings_toman':savings,
        'pricing_scope':'1 administration; not course cost',
        'equivalent_clinical_substitute_verified':False}
    base['status'] = 'two_review_drafts_not_signed'
    return _attach_review_summary(base, case, discovery)


def _extract_structured_product_offer(html: str, *, expected_pack_ml: float) -> Dict[str, Any]:
    """Parse exact-product machine-readable markup, NEVER guess a price from digits.

    Requires: an identified maropitant product, concentration 10mg/mL, vial
    volume match, a schema.org Product Offer price, and stated IRR/IRT currency.
    This is only a *preview*, not an authenticated price or approval.
    """
    import html as html_lib
    from html.parser import HTMLParser

    class JSONLD(HTMLParser):
        def __init__(self):
            super().__init__(); self.in_script = False; self.payloads: List[str] = []
        def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]):
            props = dict(attrs)
            self.in_script = tag.lower() == 'script' and (props.get('type') or '').lower() == 'application/ld+json'
        def handle_data(self, data: str):
            if self.in_script and len(data) <= 90_000: self.payloads.append(data)
        def handle_endtag(self, tag: str):
            if tag.lower() == 'script': self.in_script = False

    parser = JSONLD(); parser.feed(html[:500_000])
    def objects(value: Any):
        if isinstance(value, list):
            for item in value: yield from objects(item)
        if isinstance(value, dict):
            yield value
            for key in ('@graph', 'mainEntity', 'hasVariant'):
                if key in value: yield from objects(value[key])

    for payload in parser.payloads:
        try:
            parsed = json.loads(html_lib.unescape(payload))
        except (ValueError, TypeError):
            continue
        for item in objects(parsed):
            typ = item.get('@type', '')
            if not (typ == 'Product' or (isinstance(typ, list) and 'Product' in typ)):
                continue
            label = ' '.join(str(item.get(k) or '') for k in ('name', 'description'))
            label = html_lib.unescape(re.sub('<[^>]+>', ' ', label))
            if not re.search(r'maropitant|cerenia|ماروپیتانت|سرنیا', label, re.I):
                continue
            normalized = label.translate(str.maketrans('۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩', '01234567890123456789'))
            if not re.search(r'10\s*(?:mg|milligrams?)\s*[/\\]|10\s*میلی\s*گرم\s*/', normalized, re.I):
                continue
            # Match exact volume only if explicitly present in title or description.
            pack_string = format(expected_pack_ml, '.6g')
            if not re.search(r'\b' + re.escape(pack_string) + r'\s*(?:ml|mL|میلی\s*لیتر)\b', normalized, re.I):
                continue
            offers = item.get('offers')
            for offer in (offers if isinstance(offers, list) else [offers]):
                if not isinstance(offer, dict): continue
                if str(offer.get('availability', '')).lower().endswith('outofstock'): continue
                raw_currency = str(offer.get('priceCurrency') or '').upper()
                if raw_currency not in ('IRR', 'IRT'): continue
                price = _positive(offer.get('price'))
                if price is None: continue
                return {'status':'source_page_price_preview_unverified',
                        'price': price, 'currency':'TOMAN' if raw_currency=='IRT' else 'IRR',
                        'product_name':str(item.get('name') or '')[:130],
                        'strength_mg_per_ml':10.0,'pack_ml':expected_pack_ml,
                        'warning':'Page listing only; veterinarian must verify stock, identity, date and final cost.'}
    return {'status':'unavailable_or_unverifiable', 'warning':
            'No exact matching JSON-LD Product offer found. Do not guess a price; enter a checked amount manually.'}


def preview_iranian_listing(raw: Dict[str, Any], *,
                             retrieve: Optional[Callable[[str, str], str]] = None) -> Dict[str, Any]:
    source = str(raw.get('source_id') or '').lower().strip()
    url = str(raw.get('url') or '').strip()
    pack_ml = _positive(raw.get('pack_ml'))
    if not _host_ok(source, url) or not pack_ml or pack_ml > 100:
        raise ValueError('Select a registered Iranian source, exact HTTPS product URL and vial size.')

    def _retrieve(uri: str, sid: str) -> str:
        from urllib.request import HTTPRedirectHandler, build_opener
        class SafeRedirect(HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                if not _host_ok(sid, newurl):
                    raise ValueError('Redirected outside verified supplier host')
                return super().redirect_request(req, fp, code, msg, headers, newurl)
        opener = build_opener(SafeRedirect())
        with opener.open(Request(uri, headers={'User-Agent':'AssistantVet/24 clinical price-preview',
                                              'Accept':'text/html'}),timeout=6) as resp:
            ctype = str(resp.headers.get('Content-Type', '')).lower()
            if 'text/html' not in ctype:
                raise ValueError('Unsupported product-page content type')
            data = resp.read(500_001)
            if len(data) > 500_000: raise ValueError('Oversize page')
            return data.decode('utf-8', errors='replace')
    try:
        result = _extract_structured_product_offer((retrieve or _retrieve)(url, source),
                                                    expected_pack_ml=pack_ml)
        return {**result, 'source_id':source,'source_url':url}
    except (OSError, ValueError, TimeoutError) as exc:
        return {'status':'source_unavailable', 'source_id':source, 'source_url':url,
                'warning':f'Could not read structured product price ({type(exc).__name__}). No price inferred.'}
