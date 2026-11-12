"""Assistant Vet v6 — clinician-reviewed prescription planning and price evidence.

No AI-supplied dose is silently accepted. Protocols must be approved in a local
formulary by a veterinarian and linked to evidence. Price observations are
explicit, time-stamped, traceable, and comparable only for the same SKU.

Live vendor APIs are NOT claimed or scraped. The site registry is a directory;
future authorized connectors can populate the same price-observation schema.
"""
from __future__ import annotations

import json
import math
import os
import statistics
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

from pydantic import BaseModel, Field

PROTOCOLS_FILE = Path(os.getenv('AV_PRESCRIPTION_PROTOCOLS', 'data/prescription/verified_protocols.json'))
PRICES_FILE = Path(os.getenv('AV_PRESCRIPTION_PRICES', 'data/prescription/price_observations.json'))
MAX_PRICE_AGE_DAYS = 14

# These are directories of sources, NOT integrated live pricing APIs.
PRICE_SOURCES = [
    {'id': 'ttac', 'name': 'TTAC — official Iranian drug price lookup', 'url': 'https://www.ttac.ir/', 'type': 'official', 'integration': 'manual_lookup'},
    {'id': 'pillix', 'name': 'Pillix — Iranian medicine directory', 'url': 'https://www.pillix.ir/medicine', 'type': 'directory', 'integration': 'manual_lookup'},
    {'id': 'salardam', 'name': 'Salardam — veterinary retail listings', 'url': 'https://salardam.ir/', 'type': 'retailer', 'integration': 'manual_lookup'},
    {'id': 'pharmacy4pet', 'name': 'Pharmacy4Pet — veterinary pharmacy', 'url': 'https://pharmacy4pet.com/', 'type': 'retailer', 'integration': 'manual_lookup'},
    {'id': 'cheetavet', 'name': 'Cheetavet — veterinary products', 'url': 'https://cheetavet.com/', 'type': 'retailer', 'integration': 'manual_lookup'},
    {'id': 'vetkala', 'name': 'Vetkala — pet/veterinary product listings', 'url': 'https://vetkala.com/', 'type': 'retailer', 'integration': 'manual_lookup'},
]


class PrescriptionPlanRequest(BaseModel):
    case_payload: Dict[str, Any]
    analysis_result: Dict[str, Any]


def _load_list(file_path: Path, key: str) -> List[Dict[str, Any]]:
    if not file_path.exists():
        return []
    try:
        with file_path.open('r', encoding='utf-8') as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            data = data.get(key, [])
        return [row for row in data if isinstance(row, dict)] if isinstance(data, list) else []
    except (OSError, ValueError):
        # Corrupted/invalid data must not be allowed to create an incorrect price.
        return []


def _positive_number(value: Any) -> Optional[float]:
    try:
        number = float(value)
        return number if math.isfinite(number) and number > 0 else None
    except (TypeError, ValueError):
        return None


def _utc(value: Any) -> Optional[datetime]:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed.astimezone(timezone.utc)
    except ValueError:
        return None


def _approved_url(url: str) -> bool:
    parsed = urlparse(url)
    return parsed.scheme == 'https' and bool(parsed.hostname) and not parsed.username and not parsed.password


def _validate_protocol(raw: Dict[str, Any], species: str, age: Optional[float], terms: str) -> Optional[Dict[str, Any]]:
    """A model's free-form treatment text is NOT a prescription protocol."""
    if raw.get('review_status') != 'approved' or not raw.get('reviewer') or _utc(raw.get('reviewed_at')) is None:
        return None
    evidence = raw.get('evidence')
    if not isinstance(evidence, list) or not evidence or not any(
        isinstance(src, dict) and src.get('title') and src.get('locator') for src in evidence
    ):
        return None
    if str(raw.get('species', '')).lower() != species:
        return None
    if age is not None:
        minimum = raw.get('min_age_years')
        maximum = raw.get('max_age_years')
        if minimum is not None and age < float(minimum):
            return None
        if maximum is not None and age > float(maximum):
            return None
    elif raw.get('min_age_years') is not None or raw.get('max_age_years') is not None:
        return None
    keywords = [str(w).strip().lower() for w in raw.get('indication_keywords', []) if str(w).strip()]
    if not keywords or not any(k in terms for k in keywords):
        return None
    required = ['id', 'active_ingredient', 'product_id', 'form', 'route', 'therapeutic_slot', 'substitution_group']
    if any(not str(raw.get(key, '')).strip() for key in required):
        return None
    if any(_positive_number(raw.get(key)) is None for key in
           ('dose_mg_per_kg', 'strength_mg_per_unit', 'administrations_per_day', 'duration_days', 'pack_units')):
        return None
    if _positive_number(raw.get('max_dose_mg')) is None:
        return None  # require an explicit clinician-reviewed max dose
    if raw.get('unit_kind') not in ('tablet', 'capsule', 'ml', 'ampoule', 'drop'):
        return None
    # Explicit equivalent products only. Two medications with similar names are
    # NOT assumed therapeutically interchangeable.
    return raw


def _candidate(protocol: Dict[str, Any], weight: float) -> Optional[Dict[str, Any]]:
    dose = weight * float(protocol['dose_mg_per_kg'])
    if dose > float(protocol['max_dose_mg']):
        dose = float(protocol['max_dose_mg'])
    units_per_dose = dose / float(protocol['strength_mg_per_unit'])
    units_per_course = units_per_dose * float(protocol['administrations_per_day']) * float(protocol['duration_days'])
    if not all(math.isfinite(x) for x in (dose, units_per_dose, units_per_course)):
        return None
    # Tablets/capsules require explicitly approved divisible steps; otherwise
    # do NOT round a dose to fit the strength.
    step = _positive_number(protocol.get('allowed_unit_step'))
    if protocol['unit_kind'] != 'ml':
        if step is None or abs(units_per_dose / step - round(units_per_dose / step)) > 1e-6:
            return None
    else:
        step = step or 0.01
        if abs(units_per_dose / step - round(units_per_dose / step)) > 1e-6:
            return None
    if protocol['unit_kind'] == 'ampoule':
        # Single-use vials may not be shared between administration events.
        units_per_course = math.ceil(units_per_dose) * float(protocol['administrations_per_day']) * float(protocol['duration_days'])
    packages = math.ceil(units_per_course / float(protocol['pack_units']))
    return {
        'protocol_id': str(protocol['id']), 'ingredient': str(protocol['active_ingredient']),
        'product_id': str(protocol['product_id']), 'form': str(protocol['form']),
        'unit_kind': str(protocol['unit_kind']), 'route': str(protocol['route']),
        'therapeutic_slot': str(protocol['therapeutic_slot']),
        'substitution_group': str(protocol['substitution_group']),
        'reviewer': str(protocol['reviewer']), 'reviewed_at': str(protocol['reviewed_at']),
        'evidence': protocol['evidence'], 'priority': int(protocol.get('priority', 100)),
        'dose_mg_per_kg': float(protocol['dose_mg_per_kg']), 'dose_mg': round(dose, 3),
        'units_per_dose': round(units_per_dose, 4),
        'administrations_per_day': float(protocol['administrations_per_day']),
        'duration_days': float(protocol['duration_days']), 'pack_units': float(protocol['pack_units']),
        'packages_needed': packages, 'cost_toman': None, 'cost_status': 'not_available',
        'price_evidence': None,
        'notes': 'Clinician-reviewed draft; confirm suitability, contraindications, interactions and product authorization before signing.',
        'why': str(protocol.get('clinical_rationale') or ''),
        'rx_abbreviation': {'tablet':'Tab.', 'capsule':'Cap.', 'syrup':'Syrp.', 'suspension':'Susp.',
                            'drop':'Drop.', 'drops':'Drop.', 'fluid':'Serum / IV Fluid',
                            'injection':'Inj.', 'ampoule':'Amp.', 'vial':'Vial'}.get(
                                str(protocol.get('form', '')).lower(), str(protocol.get('form', 'Rx/'))),
    }


def _price_consensus(product_id: str, quotes: List[Dict[str, Any]], now: datetime,
                     *, pack_units: float, strength_mg_per_unit: float,
                     unit_kind: str) -> Dict[str, Any]:
    """Consensus only across independent sources for IDENTICAL SKU + pack."""
    vendor = {}
    official = []
    known_sources = {s['id']: s for s in PRICE_SOURCES}
    for q in quotes:
        if q.get('product_id') != product_id or q.get('in_stock') is not True:
            continue
        # Never blend similarly named formulations or differently sized packs.
        if (_positive_number(q.get('pack_units')) != pack_units or
            _positive_number(q.get('strength_mg_per_unit')) != strength_mg_per_unit or
            q.get('unit_kind') != unit_kind):
            continue
        if q.get('review_status') != 'verified' or not q.get('verified_by'):
            continue
        source_url = str(q.get('url', ''))
        source_name = str(q.get('source_id', '')).strip().lower()
        known = known_sources.get(source_name)
        if known is None or not _approved_url(source_url):
            continue
        expected_host = urlparse(known['url']).hostname
        actual_host = urlparse(source_url).hostname
        root_host = expected_host.removeprefix('www.')
        if actual_host not in (root_host, 'www.' + root_host):
            continue
        observed = _utc(q.get('observed_at'))
        if observed is None or now - timedelta(days=MAX_PRICE_AGE_DAYS) > observed or observed > now + timedelta(minutes=10):
            continue
        val = _positive_number(q.get('price'))
        if val is None or q.get('currency') not in ('IRR', 'TOMAN'):
            continue
        toman = val / 10 if q['currency'] == 'IRR' else val
        entry = {'source_id': source_name, 'url': source_url, 'observed_at': observed.isoformat(), 'price_toman': round(toman)}
        if q.get('source_type') == 'official' and source_name == 'ttac' and urlparse(source_url).hostname in ('ttac.ir', 'www.ttac.ir'):
            official.append(entry)
        elif q.get('source_type') == 'retailer' and known['type'] == 'retailer':
            # Same retailer repeated 10x is still one source. Keep its latest quote.
            if source_name not in vendor or observed.isoformat() > vendor[source_name]['observed_at']:
                vendor[source_name] = entry
    vendor_list = list(vendor.values())
    official_toman = official[-1]['price_toman'] if official else None
    if len(vendor_list) < 2:
        return {'status': 'insufficient_independent_quotes', 'consensus_toman': None,
                'official_toman': official_toman, 'quotes': vendor_list, 'min_sources': 2}
    prices = [q['price_toman'] for q in vendor_list]
    median = statistics.median(prices)
    # Dispersion check; don't announce market consensus when sources disagree.
    if median <= 0 or max(prices) / min(prices) > 1.25:
        return {'status': 'price_disagreement', 'consensus_toman': None,
                'official_toman': official_toman, 'quotes': vendor_list, 'min_sources': 2}
    return {'status': 'market_consensus', 'consensus_toman': round(median),
            'official_toman': official_toman, 'quotes': vendor_list, 'min_sources': 2}


def make_prescription_plan(case_payload: Dict[str, Any], analysis_result: Dict[str, Any], *,
                           protocols: Optional[List[Dict[str, Any]]] = None,
                           quotes: Optional[List[Dict[str, Any]]] = None,
                           now: Optional[datetime] = None) -> Dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    protocols = _load_list(PROTOCOLS_FILE, 'protocols') if protocols is None else protocols
    quotes = _load_list(PRICES_FILE, 'observations') if quotes is None else quotes
    patient = case_payload.get('patient') or {}
    clinical = case_payload.get('clinical') or {}
    analysis = analysis_result.get('analysis') or {}
    species = str(patient.get('species', '')).lower()
    weight = _positive_number(patient.get('weight_kg'))
    try:
        age = float(patient['age_years']) if patient.get('age_years') is not None else None
    except (TypeError, ValueError):
        age = None
    diagnoses = ' '.join(str(a.get('diagnosis', '')) for a in (analysis.get('most_probable_diagnoses') or []) if isinstance(a, dict))
    terms = ' '.join((str(clinical.get('chief_complaint') or ''), str(clinical.get('history') or ''), diagnoses)).lower()
    response: Dict[str, Any] = {
        'schema_version': 1, 'status': 'awaiting_verified_formulary',
        'patient': {'name': patient.get('name'), 'species': species, 'weight_kg': weight},
        'first_choice': {'status': 'unavailable', 'lines': [], 'total_toman': None},
        'economic': {'status': 'unavailable', 'lines': [], 'total_toman': None, 'verified_savings_toman': None},
        'price_sources': PRICE_SOURCES,
        'price_policy': {'market_source_minimum': 2, 'max_age_days': MAX_PRICE_AGE_DAYS,
                         'currency': 'TOMAN', 'live_price_sync': False,
                         'note': 'Only clinician-verified local quotes are used. Site links are not live API integrations. TTAC official prices are reported separately; market quotes may differ.'},
        'warning': 'Do not use a draft as a signed prescription without a veterinarian checking the patient, contraindications, route, formulation and evidence.'
    }
    if species not in ('dog', 'cat') or weight is None or not terms.strip():
        response['status'] = 'insufficient_patient_data'
        return response
    eligible: List[Dict[str, Any]] = []
    for p in protocols:
        approved = _validate_protocol(p, species, age, terms)
        if approved is not None:
            candidate = _candidate(approved, weight)
            if candidate:
                price = _price_consensus(candidate['product_id'], quotes, now,
                                         pack_units=float(approved['pack_units']),
                                         strength_mg_per_unit=float(approved['strength_mg_per_unit']),
                                         unit_kind=str(approved['unit_kind']))
                candidate['price_evidence'] = price
                candidate['cost_status'] = price['status']
                if price['consensus_toman'] is not None:
                    candidate['cost_toman'] = int(candidate['packages_needed'] * price['consensus_toman'])
                eligible.append(candidate)
    if not eligible:
        return response
    grouped: Dict[str, List[Dict[str, Any]]] = {}
    for c in eligible:
        grouped.setdefault(c['therapeutic_slot'], []).append(c)
    first_lines = []
    economic_lines = []
    for group in grouped.values():
        sorted_group = sorted(group, key=lambda c: (c['priority'], c['protocol_id']))
        first = sorted_group[0]
        first_lines.append(first)
        # Only approved alternatives in the same *explicit* substitution group.
        swappable = [c for c in sorted_group if c['substitution_group'] == first['substitution_group']]
        priced = [c for c in swappable if c['cost_toman'] is not None]
        economic_lines.append(min(priced, key=lambda c: c['cost_toman']) if priced else first)
    all_first_known = all(c['cost_toman'] is not None for c in first_lines)
    all_economic_known = all(c['cost_toman'] is not None for c in economic_lines)
    first_total = int(sum(c['cost_toman'] for c in first_lines)) if all_first_known else None
    economic_total = int(sum(c['cost_toman'] for c in economic_lines)) if all_economic_known else None
    response.update({
        'status': 'draft_requires_veterinarian_approval',
        'first_choice': {'status': 'price_verified' if all_first_known else 'price_incomplete',
                         'lines': first_lines, 'total_toman': first_total},
        'economic': {'status': 'price_verified' if all_economic_known else 'price_incomplete',
                     'lines': economic_lines, 'total_toman': economic_total,
                     'verified_savings_toman': max(0, first_total - economic_total)
                     if first_total is not None and economic_total is not None else None},
    })
    return response
