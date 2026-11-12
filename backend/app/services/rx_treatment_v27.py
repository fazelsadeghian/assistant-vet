"""v27 patient-specific three-plan *review* builder.

No study-abstract doses, extra clinical medications, IV fluids or substitutions
are manufactured. Multiple lines can come from already clinician-approved,
case-matched formulary protocols. Source-only maropitant remains provisional.
"""
from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timezone
import math
import re
from typing import Any, Optional

from app.services.prescription_engine import (_candidate, _validate_protocol,
    _load_list, PROTOCOLS_FILE)
from app.services.rx_autoprice_v27 import _line_sku


def _empty(detail: str, status: str='no_verified_alternative') -> dict[str,Any]:
    return {'lines':[], 'status':status, 'total_toman':None,
            'total_usd_approx':None,'detail':detail,'review_required':True}


def _safety_first(plan: dict[str,Any]) -> bool:
    return bool((plan.get('clinical_safety') or {}).get('red_flags'))


def _clinician_terms(case:dict[str,Any]) -> str:
    """Use documented clinician facts, NEVER speculative AI differential text."""
    clinical=case.get('clinical') or {}
    return ' '.join(str(clinical.get(k) or '') for k in
        ('chief_complaint','history','confirmed_diagnosis','clinical_notes')).lower()


def _reviewed_candidates(case:dict[str,Any], protocols:list[dict[str,Any]]) -> list[dict[str,Any]]:
    """Only previously approved local-file protocols; model output is excluded.

    A symptom word cannot authorize a diagnosis-dependent treatment: protocols
    can flag requires_confirmed_diagnosis to require clinician documentation.
    Known prokinetic obstruction risks require explicit clinician screening.
    """
    patient=case.get('patient') or {}
    species=str(patient.get('species') or '').lower()
    try: weight=float(patient.get('weight_kg'))
    except (ValueError, TypeError): return []
    if not math.isfinite(weight) or weight<=0: return []
    try:
        age=float(patient['age_years']) if patient.get('age_years') is not None else None
    except (ValueError, TypeError): age=None
    checks=case.get('prescription_checks') or {}
    if not isinstance(checks,dict): checks={}
    clinical=case.get('clinical') or {}
    terms=_clinician_terms(case)
    result=[]
    for raw in protocols:
        if not isinstance(raw,dict): continue
        if raw.get('requires_confirmed_diagnosis') is True and not str(clinical.get('confirmed_diagnosis') or '').strip():
            continue
        if str(raw.get('active_ingredient') or '').strip().lower()=='metoclopramide' and checks.get('obstruction_ruled_out') is not True:
            continue
        approved=_validate_protocol(raw,species,age,terms)
        if approved is None:continue
        try: candidate=_candidate(approved,weight)
        except (ValueError, TypeError, ZeroDivisionError, KeyError): continue
        if candidate:
            candidate['dose_context']='clinician_reviewed_local_formulary_patient_signoff_required'
            candidate['patient_approved']=False
            result.append(candidate)
    return sorted(result,key=lambda r:(r.get('priority',100),str(r.get('protocol_id'))))


def _first_from_formulary(case:dict[str,Any], protocols:list[dict[str,Any]]) -> list[dict[str,Any]]:
    """Use one vetted treatment or an EXPLICIT vetted multi-line bundle.

    No implicit addition of antibiotics, corticosteroids or IV fluids from a
    generic matching complaint. The bundle is reviewed by humans offline.
    """
    options=_reviewed_candidates(case,protocols)
    if not options:return []
    first=options[0]
    bundle_id=next((str(p.get('treatment_bundle_id')) for p in protocols
        if isinstance(p,dict) and str(p.get('id'))==first.get('protocol_id')
        and p.get('reviewed_combination') is True and p.get('treatment_bundle_id')),None)
    if not bundle_id:return [deepcopy(first)]
    ids={str(p['id']) for p in protocols if isinstance(p,dict) and
         p.get('reviewed_combination') is True and str(p.get('treatment_bundle_id') or '')==bundle_id and p.get('id')}
    rows=[deepcopy(o) for o in options if o['protocol_id'] in ids]
    slots=[o['therapeutic_slot'] for o in rows]
    # Never include two therapies in the same slot in a bundle by accident.
    if len(rows)!=len(ids) or len(slots)!=len(set(slots)):return [deepcopy(first)]
    return rows


def _alternatives_from_formulary(case: dict[str,Any], analysis:dict[str,Any],
                               first_lines: list[dict[str,Any]], protocols=None) -> list[dict[str,Any]]:
    """Alternative is allowed ONLY for a clinician-reviewed common slot/group."""
    if not first_lines or any(not r.get('substitution_group') or not r.get('therapeutic_slot') for r in first_lines):
        return []
    if protocols is None:
        protocols=_load_list(PROTOCOLS_FILE,'protocols')
    patient=case.get('patient') or {}; clinical=case.get('clinical') or {}
    species=str(patient.get('species') or '').lower()
    try: age=float(patient['age_years']) if patient.get('age_years') is not None else None
    except (ValueError,TypeError): age=None
    try: weight=float(patient.get('weight_kg'))
    except (ValueError,TypeError):return []
    if weight<=0: return []
    # Differential diagnoses generated by AI must not unlock approved protocols.
    terms=_clinician_terms(case)
    options=[]
    for candidate in _reviewed_candidates(case, protocols or []):
        if not any(candidate.get('protocol_id')==f.get('protocol_id') for f in first_lines):
            options.append(candidate)
    grouped={}
    for candidate in options:
        grouped.setdefault((candidate['therapeutic_slot'],candidate['substitution_group']),[]).append(candidate)
    alternative=[]
    for first in first_lines:
        matches=grouped.get((first['therapeutic_slot'],first['substitution_group']),[])
        if matches: alternative.append(deepcopy(sorted(matches,key=lambda a:a.get('priority',100))[0]))
        else:alternative.append(deepcopy(first))
    if not any(x.get('protocol_id')!=y.get('protocol_id') for x,y in zip(alternative,first_lines)):
        return []
    return alternative


def _cost_one_administration(line:dict[str,Any], offer:dict[str,Any]) -> Optional[int]:
    # Full-course estimate is allowed only when both course days and frequency
    # are set by a reviewed protocol. Missing duration => ONE administration.
    sku=_line_sku(line)
    if not sku or sku['units_per_dose'] is None: return None
    units=sku['units_per_dose']; pack=offer.get('pack_units')
    price=offer.get('price_toman')
    if not isinstance(pack,(int,float)) or pack<=0 or not isinstance(price,(int,float)) or price<=0: return None
    if sku.get('duration_days') and sku.get('administrations_per_day'):
        units *= float(sku['duration_days'])*float(sku['administrations_per_day'])
    return round(math.ceil(units/pack)*price)


def _price_choice(line:dict[str,Any], offer:dict[str,Any], fx:dict[str,Any]) -> dict[str,Any]:
    updated=deepcopy(line)
    price=_cost_one_administration(line,offer)
    if price is None: return updated
    sku=_line_sku(line)
    has_course=bool(sku and sku.get('duration_days') and sku.get('administrations_per_day'))
    required_units=float(sku['units_per_dose'])*(float(sku['duration_days'])*float(sku['administrations_per_day']) if has_course else 1)
    updated.update(brand=offer.get('brand') or '',product_name=offer['product_name'],
        packages_needed=math.ceil(required_units/float(offer['pack_units'])),
        cost_toman=price,
        cost_scope='whole_course_pack_acquisition' if has_course else 'one_administration_pack_acquisition', 
        price_evidence={'status':'automated_vendor_listed_not_clinician_verified',
            'source_id':offer['source_id'],'url':offer['url'],
            'observed_at':offer['observed_at'], 'product_name':offer['product_name'],
            'pack_units':offer['pack_units'],'stock':'listed_in_stock',
            'price_per_pack_toman':offer['price_toman'],
            'disclaimer':'Verify product registration, final checkout price and current stock.'})
    rate=fx.get('toman_per_usd') if fx.get('status')=='current' else None
    if isinstance(rate,(float,int)) and rate>0:
        updated['cost_usd_approx']=round(price/rate,2)
    return updated


def _pricing_for_lines(lines:list[dict[str,Any]], auto:dict, fx:dict) -> tuple[list,dict]:
    out=[]; audits=[]
    for line in lines:
        sku=_line_sku(line)
        if sku is None:
            out.append(deepcopy(line));audits.append({'ingredient':line.get('ingredient'),'status':'no_exact_sku_for_automatic_search'})
            continue
        key=(sku['ingredient'],sku['form'],sku['unit'],sku['strength'])
        info=(auto.get('by_sku') or {}).get(key) or {}
        offers=info.get('offers') or []
        audit={'ingredient':sku['ingredient'], 'status':info.get('status','price_unavailable'),
               'offer_count':len(offers), 'sources':info.get('suppliers',[]),
               'matching_offers':offers}
        if offers:
            # A reference supplier is chosen deterministically by configured
            # retailer order, not claimed to be clinically superior.
            out.append(_price_choice(line,offers[0],fx))
        else: out.append(deepcopy(line))
        audits.append(audit)
    total=_total(out)
    return out,{'cost_toman':total,'price_audit':audits}


def _economic_prices(lines:list[dict[str,Any]], auto:dict, fx:dict) -> list[dict[str,Any]]:
    out=[]
    for line in lines:
        sku=_line_sku(line)
        if sku is None: return []
        key=(sku['ingredient'],sku['form'],sku['unit'],sku['strength'])
        offers=((auto.get('by_sku') or {}).get(key) or {}).get('offers') or []
        eligible=[o for o in offers if _cost_one_administration(line,o) is not None]
        if not eligible: return []
        cheaper=min(eligible,key=lambda offer:_cost_one_administration(line,offer))
        row=_price_choice(line,cheaper,fx)
        row['dose_context']=line.get('dose_context') # Preserves review-only status.
        row['economic_note']='Same ingredient and formulation; regulatory/brand equivalence NOT certified.'
        out.append(row)
    return out


def _total(lines:list[dict[str,Any]]) -> Optional[int]:
    costs=[x.get('cost_toman') for x in lines]
    scopes={x.get('cost_scope') for x in lines}
    if len(scopes)>1: return None  # Never add a 1-dose cost to a whole-course cost.
    return round(sum(costs)) if costs and all(isinstance(p,(float,int)) for p in costs) else None


def _article_triage(papers:dict[str,Any], case:dict[str,Any]) -> dict[str,int]:
    """Do not confuse perioperative prevention, chronic single case or skin studies
    with trials of treating active undifferentiated emesis."""
    counts={'direct_treatment':0,'indirect_context':0,'unrelated':0}
    clinical=case.get('clinical') or {}
    words=' '.join(str(v) for v in clinical.values() if isinstance(v,str)).lower()
    vomiting=bool(re.search(r'vomit|emesis|استفراغ', words))
    for paper in papers.get('papers') or []:
        text=(str(paper.get('title') or '')+' '+str(paper.get('abstract_excerpt') or '')).lower()
        title=str(paper.get('title') or '').lower()
        # Topic flag from abstract retrieval alone is insufficient for direct benefit.
        if ('intradermal' in title or 'pollen' in title or 'atopic' in title or
            'cyclic vomiting syndrome' in title):
            group='unrelated' if 'pollen' in title or 'atopic' in title else 'indirect_context'
        elif any(x in title for x in ('preoperative','perioperative','anesthesia','anaesthesia','motion sickness')):
            group='indirect_context'
        elif vomiting and ('vomiting' in title or 'emesis' in title) and any(
              x in title for x in ('treatment','therapy','efficacy','control of vomiting','acute vomiting')):
            group='direct_treatment'
        else: group='indirect_context'
        paper['v27_clinical_relevance']=group
        paper['full_text_appraised']=False
        paper['regimen_verified']=False
        counts[group]+=1
    return counts


def construct_three_plans(workflow:dict[str,Any], case:dict[str,Any],analysis:dict[str,Any],
                         auto:dict[str,Any], *, protocols=None) -> dict[str,Any]:
    plan=workflow.get('plan') or {}
    fx=plan.get('exchange_rate') or {}
    research=workflow.get('research') or {}
    paper_audit=research.get('papers') or {}
    triage=_article_triage(paper_audit,case)
    indirect_links={str(p.get('url')) for p in paper_audit.get('papers') or []
        if p.get('v27_clinical_relevance')!='direct_treatment' and p.get('url')}
    base=deepcopy((plan.get('first_choice') or {}).get('lines') or [])
    # v30: previously vetted local formulary protocols can be the FIRST choice
    # even when the old hard-coded maropitant source row is absent. No AI dose.
    if not base and not _safety_first(plan):
        stored=protocols if protocols is not None else _load_list(PROTOCOLS_FILE,'protocols')
        base=_first_from_formulary(case,stored)
    # v26 attached any paper matching species+"vomit" to the Rx. Remove papers
    # whose objective is perioperative prevention, skin testing or cyclic disease.
    for row in base:
        if isinstance(row,dict):
            row['evidence']=[item for item in row.get('evidence') or []
                if not (isinstance(item,dict) and item.get('url') in indirect_links
                        and item.get('screening_status')=='not_dose_verified')]
    reasons=[]
    for item in base:
        if isinstance(item,dict) and item.get('dose_context')=='source_row_review_not_prescription':
            item['why']='Source-matched Plumb canine indication; requires diagnostic exclusion and veterinarian review. Article relevance is not a dosing authorization.'
    if _safety_first(plan): base=[]
    first,first_price=_pricing_for_lines(base,auto,fx)
    if base:
        plan['first_choice']={**plan.get('first_choice',{}), 'lines':first,
            'total_toman':first_price['cost_toman'],
            'cost_scope':'one_administration_acquisition_unless_course_specified',
            'status':'review_draft_with_automatic_price_attempt',
            'detail':'Source-backed, conditional; missing patient checks prevent a signed order.'}
    else:
        plan['first_choice']={**plan.get('first_choice',{}),'lines':[], 'total_toman':None}
    other=_alternatives_from_formulary(case,analysis,base,protocols=protocols)
    if other:
        alt,alt_price=_pricing_for_lines(other,auto,fx)
        plan['alternative']={'status':'clinician_reviewed_formulary_alternative_requires_patient_signoff',
            'lines':alt,'total_toman':alt_price['cost_toman'],
            'detail':'Alternative matches a clinician-reviewed substitution group, not an AI-invented substitute.'}
    else:
        plan['alternative']=_empty('No different case-matched, clinician-reviewed regimen is verified yet. Drug mentions alone cannot be converted into an alternative prescription.')
    econom=_economic_prices(first,auto,fx) if first else []
    # A clinically approved alternative can also compete on price, but ONLY
    # when all its lines have exact-SKU vendor offers.
    if other:
        alternative_costed=_economic_prices(other,auto,fx)
        if alternative_costed and (not econom or
                (_total(alternative_costed) is not None and _total(econom) is not None and
                 _total(alternative_costed) < _total(econom))):
            econom=alternative_costed
    if econom:
        total=_total(econom); baseline=_total(first)
        savings=baseline-total if total is not None and baseline is not None and baseline>=total else None
        plan['economic']={'status':'automated_exact_ingredient_supplier_comparison_not_approved_equivalence',
            'lines':econom,'total_toman':total,
            'indicative_savings_toman':savings,
            'verified_savings_toman':None, 'cost_scope':'one_administration_purchase_not_course',
            'detail':'Cheapest complete supplier-priced regimen among this case’s clinically reviewed choices; equivalence and supply still require veterinarian review.'}
    else:
        plan['economic']=_empty('Automatic Iranian supplier searches returned no complete price-supported regimen. No drug or price has been invented.',status='automatic_price_not_found')
    for plan_key in ('first_choice','alternative','economic'):
        entry=plan[plan_key]
        entry['review_required']=True
        entry['clinical_authorization']=False
        entry['medication_count']=len(entry.get('lines') or [])
        line_scopes={x.get('cost_scope') for x in entry.get('lines') or [] if x.get('cost_toman') is not None}
        entry['cost_scope']=(next(iter(line_scopes)) if len(line_scopes)==1 else
                             'mixed_or_unknown_scope_no_total')
        entry['total_usd_approx']=round(entry['total_toman']/fx['toman_per_usd'],2) if (
            isinstance(entry.get('total_toman'),(float,int)) and fx.get('status')=='current' and
            isinstance(fx.get('toman_per_usd'),(float,int)) and fx['toman_per_usd']>0) else None
    if case.get('clinical'):
        reasons=['Assess hydration and ongoing losses before selecting serum or an IV-fluid rate.',
            'Treat the identified cause; antiemetics do not exclude gastrointestinal obstruction.',
            'Review interaction, liver status, body weight and follow-up before signing.']
    plan.update(schema_version=27,workspace_mode='three_patient_specific_review_plans',
        automatic_prices={'status':auto.get('status'),'checked_at':auto.get('checked_at'),
            'offers_count':auto.get('offers_count'), 'by_drug':first_price['price_audit'],
            'note':'Product prices sourced automatically from exact supplier listings where possible; no manual entry required.'},
        clinician_care_considerations=reasons,
        approval_allowed=False, not_signed=True,
        economic_policy='Never optimize price before clinical suitability; unknown prices do not rank drug alternatives.')
    if workflow.get('research'):
        workflow['research']['article_relevance_v27']=triage
        workflow['research'].setdefault('limits',[]).append('Perioperative or skin-test articles are not proof of active acute-emesis efficacy.')
    workflow['plan']=plan
    workflow['workflow_version']=27
    return workflow
