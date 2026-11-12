"""Assistant Vet v26: integrated scientific REVIEW pipeline, not autonomous prescribing.

Order: clinician case -> local book coverage -> primary paper screen -> bounded AI
case reasoning -> source-row validated drafts -> price provenance and safety audit.
The AI is not permitted to enter a dose, price, approved status or new Rx drug.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import json
import inspect
import os
import re
from typing import Any, Dict, Optional

import httpx

from app.services.treatment_evidence import discover_treatment_evidence
from app.services.rx_integrated import build_integrated_plan, fetch_usd_toman
from app.services.rx_research_v26 import audit_indexed_books, choose_topic, search_veterinary_articles
from app.services.rx_pricing_v26 import comparable_quotes

MAX_AI_PREDICT = 500


def _compact(x: Any, n: int = 250) -> str:
    return re.sub(r'\s+', ' ', str(x or '')).strip()[:n]


def _safe_list(items: Any, count: int = 7) -> list[str]:
    if not isinstance(items, list):
        return []
    return [_compact(x, 170) for x in items[:count] if isinstance(x, str) and x.strip()
            and not re.search(r'\b\d+(?:[.,]\d+)?\s*(?:mg|mcg|ml|units|iu)\s*(?:/\s*kg|/\s*day|\b)', x, re.I)
            and not re.search(r'\b(?:administer|inject|prescribe)\b', x, re.I)]


def _patient_gaps(case: dict[str, Any]) -> list[dict[str, str]]:
    """Checks are clinician verification, not just a keyword in the narrative.

    A sentence like "hydration unknown" must never be parsed as completed care.
    """
    patient = case.get('patient') or {}
    clinic = case.get('clinical') or {}
    checks = case.get('prescription_checks') or {}
    if not isinstance(checks,dict):checks={}
    narrative = ' '.join(str(v) for v in clinic.values() if isinstance(v,(str,int,float))).lower()
    gaps: list[dict[str,str]] = []
    def missing(code: str, message: str, cond: bool) -> None:
        if cond:
            gaps.append({'code': code, 'question': message, 'status': 'requires_veterinarian_input'})
    missing('body_weight','Confirm current measured weight and units.',not patient.get('weight_kg'))
    missing('age','Document age including age units.',patient.get('age_years') is None)
    missing('vitals','Document T/P/R, mucous membranes and abdominal exam.',
            checks.get('veterinarian_examined') is not True)
    missing('hydration','Assess hydration, fluid deficit, ongoing losses and electrolytes if indicated.',
            checks.get('hydration_assessed') is not True)
    missing('drugs','Document concurrent drugs, allergies and interactions.',
            checks.get('medications_reviewed') is not True)
    missing('red_flags','Evaluate foreign body, obstruction and toxic exposure when clinically indicated.',
            bool(re.search(r'vomit|emesis|استفراغ|abdominal pain|درد شکم',narrative)) and
            not (checks.get('obstruction_ruled_out') is True and checks.get('toxin_ruled_out') is True))
    return gaps

def evidence_decisions(discovery: dict[str, Any], plan: dict[str, Any],
                       papers: dict[str, Any], case: dict[str, Any]) -> list[dict[str, Any]]:
    selected = {str(p.get('ingredient') or '').lower() for p in
                (plan.get('first_choice') or {}).get('lines',[]) if isinstance(p, dict)}
    handbook = {str(x.get('drug_name') or '').lower(): x for x in
                discovery.get('handbook_references',[]) if isinstance(x, dict)}
    candidates = []
    for candidate in discovery.get('candidates',[])[:25]:
        if not isinstance(candidate, dict): continue
        name = _compact(candidate.get('drug_name'),80).lower()
        if not name: continue
        ref = handbook.get(name) or {}
        review = ref.get('monograph_review') or {}
        rows = review.get('source_label_rows') or []
        related = [x for x in papers.get('papers', []) if name in x.get('ingredients_mentioned', [])
                   and x.get('relevance_status') == 'population_topic_overlap']
        status = 'source_row_arithmetic_for_vet_review' if name in selected else 'not_selected_source_mention_only'
        detail = ('Matched specific source row; clinical examination and sign-off still required.'
                  if name in selected else
                  'Text mention/possible handbook entry is not a case-specific treatment protocol.')
        if name == 'sucralfate' and choose_topic(case)['topic']=='vomiting':
            detail += ' Mucosal protection is not routinely indicated solely from vomiting.'
        if name in ('prednisolone','prednisone','budesonide') and choose_topic(case)['topic']=='vomiting':
            detail += ' Chronic inflammatory indications are not established by acute emesis.'
        candidates.append({'ingredient':name, 'status':status, 'why':detail,
             'handbook_locator':ref.get('locator'), 'handbook_entry_status':ref.get('status'),
             'unverified_dose_row_count':len(rows), 'matched_paper_count':len(related),
             'matched_papers':[{'title':x['title'],'url':x['url'],'design':x['reported_design']}
                               for x in related[:3]],
             'decision_scope':'triage_for_clinician_not_authorized_rx'})
    return candidates


async def _ollama_json(request: dict[str, Any], *, timeout_s: float = 165) -> dict[str, Any]:
    """Compatibility shim: all production and legacy AI callers use one runtime.

    A 21-second legacy timeout must never be reinstated for 9B inference.
    """
    from app.services.rx_ai_runtime_v29 import case_screen
    result = await case_screen(request)
    if result.get('status') != 'ai_hypotheses_for_clinician_only':
        raise ValueError(result.get('error_type') or result.get('status') or 'ai_unavailable')
    return result.get('items') or {}


async def optional_local_reasoning(case: dict[str, Any], book_audit: dict[str, Any],
                                   paper_audit: dict[str, Any], *,
                                   run_model=None) -> dict[str, Any]:
    if os.getenv('AV_RX_AI_SCREENING','1').lower() in ('0','false','off'):
        return {'status':'disabled', 'note':'No AI conclusions used; deterministic checks remain active.'}
    # No patient name/identifying data are needed by the local model.
    patient = case.get('patient') or {}
    clinical = case.get('clinical') or {}
    input_data = {'species': patient.get('species'), 'weight_kg': patient.get('weight_kg'),
        'age_years':patient.get('age_years'),
        'clinical_narrative': {key:_compact(val,350) for key,val in clinical.items()
                               if isinstance(val,(str,int,float)) and key not in ('patient_name','owner_name')},
        'indexed_books': [
            {'source':b['title'], 'excerpt':(b.get('sampled_hits') or [{}])[0].get('passage','')}
            for b in book_audit.get('books',[]) if b.get('sampled_hits')][:7],
        'papers':[{'title':p.get('title'), 'abstract':p.get('abstract_excerpt','')[:380]}
                  for p in paper_audit.get('papers',[])[:4]]}
    if run_model is None:
        # Production path: real Qwen generation with adaptive GPU-friendly
        # timeout, response diagnostics and fail-closed clinical semantics.
        from app.services.rx_ai_runtime_v29 import case_screen
        return await case_screen(input_data)
    try:
        # Backward-compatible injectable test hook: useful for deterministic
        # regression tests without a running Ollama model.
        data = await asyncio.wait_for(run_model(input_data), timeout=30)
        if not isinstance(data, dict):
            raise ValueError('AI result is not an object')
        return {'status':'ai_hypotheses_for_clinician_only',
                'model':os.getenv('OLLAMA_MODEL','qwen3:8b'),
                'items':{key:_safe_list(data.get(key)) for key in
                    ('differential_questions','safety_concerns','additional_clinical_data','research_conflicts')},
                'dosing_or_prescribing_authority':False,
                'warning':'Generated clinical questions require independent veterinarian review.'}
    except (asyncio.TimeoutError, TypeError, ValueError) as exc:
        return {'status':'unavailable', 'error_type':type(exc).__name__,
                'note':'Injected AI reviewer failed; no drug orders created.'}


async def run_integrated_workflow(case: dict[str, Any], analysis: dict[str, Any], *,
     discovery=None, books_fn=None, articles_fn=None, model_fn=None, fx_fn=None,
     legacy_protocols=None, quotes=None) -> dict[str, Any]:
    """Parallel bounded retrieval; failed integrations cannot create invented Rx rows."""
    started = datetime.now(timezone.utc)
    async def get_discovery():
        if discovery is not None:
            return discovery
        try:
            return await asyncio.wait_for(discover_treatment_evidence(case, analysis), timeout=42)
        except (Exception, asyncio.TimeoutError):
            return {'status':'unavailable','candidates':[],'handbook_references':[],
                    'sources_examined':[],'warnings':['Local search failed; no drug inference.']}
    discovery_task = asyncio.create_task(get_discovery())
    async def safe_books():
        try:
            if books_fn is not None:
                value = books_fn(case)
                if inspect.isawaitable(value):
                    return await asyncio.wait_for(value, timeout=15)
                return value
            return await asyncio.wait_for(asyncio.to_thread(audit_indexed_books, case),timeout=15)
        except Exception as exc:
            return {'status':'unavailable','books':[],'books_checked':0,'error_type':type(exc).__name__}
    async def safe_papers():
        try:
            return await asyncio.wait_for((articles_fn or search_veterinary_articles)(case,d),timeout=28)
        except Exception as exc:
            return {'status':'unavailable','papers':[],'error_type':type(exc).__name__}
    async def safe_fx():
        try:
            if fx_fn:
                return await fx_fn()
            return await asyncio.wait_for(asyncio.to_thread(fetch_usd_toman),timeout=6)
        except Exception:
            return {'status':'unavailable','toman_per_usd':None}
    # The local book index and FX check are independent of drug discovery.
    # Start them early so the UI is not delayed by serial service requests.
    books_task = asyncio.create_task(safe_books())
    fx_task = asyncio.create_task(safe_fx())
    d = await discovery_task
    books, papers, fx = await asyncio.gather(books_task, safe_papers(), fx_task)
    ai = await optional_local_reasoning(case,books,papers,run_model=model_fn)
    plan = build_integrated_plan(case,analysis,d,fx=fx,legacy_protocols=legacy_protocols,quotes=quotes)
    # Replace canned study statements with findings from THIS query. An article
    # record supports contextual relevance only; no automatic dose validation.
    for line in (plan.get('first_choice') or {}).get('lines', []):
        if not isinstance(line, dict) or line.get('dose_context') != 'source_row_review_not_prescription':
            continue
        name = str(line.get('ingredient') or '').lower()
        screened = [p for p in papers.get('papers', []) if name in p.get('ingredients_mentioned', [])
                    and p.get('relevance_status') == 'population_topic_overlap']
        old_evidence = [e for e in line.get('evidence', []) if isinstance(e, dict)]
        # Keep the Plumb excerpt and official label locator; remove the fixed
        # 2007/2008 trial entries unless they were independently retrieved.
        originals = [e for e in old_evidence if not any(
            str(e.get('url') or '').endswith('/' + pmid + '/') for pmid in ('19000277','17286662'))]
        originals += [{'title':p['title'], 'locator':'PMID '+str(p.get('pmid') or '')+' · abstract screen only',
                       'url':p['url'], 'screening_status':'not_dose_verified'}
                      for p in screened[:4] if p.get('url')]
        line['evidence'] = originals
        line['why'] = ('Canine acute vomiting: source-matched NK1 antiemetic reference row. '
            + (str(len(screened))+' relevant article abstract(s) screened, not dose-approved. '
               if screened else 'No independent case-relevant article abstract verified in this run. ')
            + 'Exclude obstruction, toxin exposure and other dangerous causes.')
        line['article_review_status'] = 'population_screen_only'
    decisions = evidence_decisions(d,plan,papers,case)
    gaps = _patient_gaps(case)
    plan.update(schema_version=26, workspace_mode='literature_to_clinical_to_dual_rx',
        clinical_data_gaps=gaps, evidence_decisions=decisions,
        independent_article_screen={'status':papers.get('status'), 'count':len(papers.get('papers',[]))},
        local_book_audit={'status':books.get('status'), 'books_checked':books.get('books_checked'),
                         'books_with_hits':books.get('books_with_hits')},
        source_review_status='source_evidence_not_a_signed_prescription',
        clinician_cannot_skip_safety_review=True)
    # Generic product observations provide ONLY provisional purchasing comparisons.
    # The price never changes the drug, route, source dose, or diagnosis.
    pricing = []
    for line in (plan.get('first_choice') or {}).get('lines', []):
        item = comparable_quotes(line)
        pricing.append({'ingredient': line.get('ingredient'), **item})
        if item['status'] != 'indicative_manual_quotes_only' or line.get('dose_context') != 'source_row_review_not_prescription':
            continue
        offers = item['quotes']
        preferred = next((q for q in offers if q.get('preferred')), None)
        if preferred is not None:
            line.update(brand=preferred.get('brand') or preferred['product_name'],
                        product_name=preferred['product_name'],
                        cost_toman=preferred['purchase_cost_one_administration_toman'],
                        packages_needed=round(preferred['purchase_cost_one_administration_toman'] / preferred['price_toman']),
                        price_evidence={'status':'clinician_recorded_not_confirmed',
                                        'source_id':preferred['source_id'],
                                        'url':preferred['url'],
                                        'observed_at':preferred['observed_at']})
            plan['first_choice']['total_toman'] = line['cost_toman'] if len(plan['first_choice']['lines']) == 1 else None
            cheapest = next((q for q in offers if
                q['source_id'] != preferred['source_id'] and
                q['purchase_cost_one_administration_toman'] < preferred['purchase_cost_one_administration_toman']), None)
            if cheapest is not None and len(plan['first_choice']['lines']) == 1:
                econom = dict(line)
                econom.update(brand=cheapest.get('brand') or cheapest['product_name'],
                    product_name=cheapest['product_name'],
                    cost_toman=cheapest['purchase_cost_one_administration_toman'],
                    packages_needed=round(cheapest['purchase_cost_one_administration_toman'] / cheapest['price_toman']),
                    price_evidence={'status':'clinician_recorded_cheaper_sku_unverified',
                                    'source_id':cheapest['source_id'], 'url':cheapest['url'],
                                    'observed_at':cheapest['observed_at']},
                    dose_context='same_ingredient_price_option_not_approved_equivalence')
                plan['economic'] = {'status':'provisional_same_ingredient_sku_comparison_only',
                    'lines':[econom], 'total_toman':econom['cost_toman'],
                    'indicative_savings_toman':line['cost_toman']-econom['cost_toman'],
                    'verified_savings_toman':None,
                    'equivalent_clinical_substitute_verified':False,
                    'detail':'Manual price claims only; confirm legal product, equivalence, cold chain and stock.',
                    'pricing_scope':'purchase one administration, NOT course'}
    # Conversion uses a currently stamped source rate; absence never means zero.
    rate = (fx or {}).get('toman_per_usd') if (fx or {}).get('status') == 'current' else None
    if isinstance(rate, (float, int)) and rate > 0:
        for option in ('first_choice', 'economic'):
            for line in (plan.get(option) or {}).get('lines', []):
                if isinstance(line, dict) and isinstance(line.get('cost_toman'), (int,float)):
                    line['cost_usd_approx'] = round(line['cost_toman']/rate,2)
    plan['price_comparison_audit'] = pricing
    plan['currency_explanation'] = 'Seller prices are in toman; USD uses a timestamped Tehran open-market rate.'
    plan['clinical_review_note'] = ('Proposed Rx lines are conditional review drafts. Clinical exam, '
        'patient suitability, regulatory approval and ingredient/product equivalence are not verified.')
    elapsed = round((datetime.now(timezone.utc)-started).total_seconds(),2)
    research = {'books':books, 'papers':papers, 'ai_reasoning':ai,
        'patient_gaps':gaps, 'evidence_decisions':decisions,
        'retrieval_time_s':elapsed,
        'approvals':{'automatic_rx':False,'automatic_medication_substitution':False,
                     'article_doses_used_without_primary_label':False},
        'limits':['Book review samples indexed topic passages; not every textbook page.',
                  'Article review screens abstracts/metadata; full methods need clinical review.',
                  'No trustworthy Iranian medicine SKU price is invented if sellers do not provide it.',
                  'AI suggestions are hypotheses and cannot supply a prescription dose.']}
    return {'workflow_version':26,'discovery':d,'research':research,'plan':plan,
            'safety':'review_only_no_automatic_prescription'}
