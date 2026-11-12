"""Assistant Vet clinical evidence workflow v28.

Single endpoint: recorded case -> indexed evidence + article triage + local
AI questions -> source-checked / clinician-reviewed choices -> automatic exact
retailer SKU pricing -> explicit provenance and actionable clinical pathways.

Never authorizes a medical order, signature, product equivalence or missing price.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.services.rx_workspace_v26 import run_integrated_workflow
from app.services.rx_autoprice_v28 import automatic_price_batch
from app.services.rx_treatment_v27 import construct_three_plans, _alternatives_from_formulary
from app.services.rx_clinical_v28 import build_clinical_paths
from app.services.rx_label_registry_v28 import official_label_reference
from app.services.prescription_engine import _load_list, PROTOCOLS_FILE
from app.services.rx_formulary_v30 import build_formulary_review, build_supportive_care_review


async def run_clinical_workflow(case:dict[str,Any], analysis:dict[str,Any], *,
                               auto_price_fn=None, protocols=None, **v26_inputs) -> dict[str, Any]:
    """Supports offline, deterministic injections for tests."""
    baseline=await run_integrated_workflow(case,analysis,**v26_inputs)
    old_plan=baseline.get('plan') or {}
    line_candidates=(old_plan.get('first_choice') or {}).get('lines') or []
    clinical_safety=old_plan.get('clinical_safety') or {}
    if clinical_safety.get('red_flags'):
        line_candidates=[]
    elif not line_candidates:
        # Primary local book search may be incomplete or temporarily offline.
        # An explicit FDA veterinary label is a permissible *reference-only*
        # fallback for the narrow approved species/age/indication, NOT Rx approval.
        candidate=official_label_reference(case,clinical_safety)
        if candidate is not None:
            line_candidates=[candidate]
            old_plan['first_choice']={'status':'official_label_reference_review',
                                      'lines':line_candidates,'total_toman':None,
                                      'detail':'Official animal-label transcription only; no local Plumb row presumed.'}
            old_plan['source_review_status']='official_label_reference_not_signed'
            old_plan['clinical_review_note']='Source label is not a patient-specific treatment order.'
            case_review=old_plan.get('case_review') or {}
            case_review['selected_ingredients']=['maropitant']
            case_review['reasons']=[
                'Official veterinary label matches recorded species/age/complaint. '
                'The locally indexed Plumb dose row was not verified in this run.',
                'Clinical examination, formulation authorization, contraindications and course duration are still unverified.']
            old_plan['case_review']=case_review
            baseline['plan']=old_plan
    # v26 can inject historical *manually typed* observations into a line.
    # They are not live site results. Carry their provenance in a separate
    # field but do not display them as current automatic prices in v28.
    for line in line_candidates:
        if not isinstance(line,dict):continue
        if line.get('cost_toman') is not None:
            line['prior_price_evidence_not_live']=line.get('price_evidence')
            line['cost_toman']=None
            line['cost_usd_approx']=None
            line['packages_needed']=None
            line['price_evidence']={'status':'awaiting_automatic_exact_sku_check'}
    verified_formulary=protocols if protocols is not None else _load_list(PROTOCOLS_FILE,'protocols')
    alternatives=_alternatives_from_formulary(case,analysis,line_candidates,protocols=verified_formulary)
    try:
        to_price=line_candidates+alternatives
        automatic=await (auto_price_fn(to_price) if auto_price_fn else automatic_price_batch(to_price))
        if not isinstance(automatic,dict):raise ValueError('Invalid retailer discovery response')
    except Exception as exc:
        automatic={'status':'automatic_supplier_failure','offers_count':0,'by_sku':{},
                   'checked_at':None, 'error_type':type(exc).__name__,
                   'note':'Supplier search failed: no product price inferred.'}
    result=construct_three_plans(baseline,case,analysis,automatic,protocols=verified_formulary)
    plan=result.get('plan') or {}
    clinical_paths=build_clinical_paths(case,result.get('discovery') or {},plan)
    plan['clinical_pathways']=clinical_paths
    # Read-only, source-linked options for clinical review: never passed to Rx building.
    plan['formulary_review']=build_formulary_review(case, verified_formulary)
    plan['supportive_care_review']=build_supportive_care_review(case)
    ai_review=(result.get('research') or {}).get('ai_reasoning') or {}
    plan['ai_clinical_review']={
        'status':ai_review.get('status','not_run'),
        'model':ai_review.get('model',''),
        'duration_s':ai_review.get('duration_s'),
        'tokens_per_second':ai_review.get('tokens_per_second'),
        'error_type':ai_review.get('error_type'),
        'http_status':ai_review.get('http_status'),
        'timeout_setting_s':ai_review.get('timeout_setting_s'),
        'items':ai_review.get('items',{}),
        'dosing_or_prescribing_authority':False,
        'human_review_required':True,
    }
    plan['automatic_prices']['retail_price_verified_at_checkout']=False
    plan['automatic_prices']['attempted_for_line_count']=len(line_candidates+alternatives)
    plan['automatic_prices']['all_offers_need_seller_recheck']=True
    # Prevent a price-only regimen from being portrayed as an approved medicine.
    for key in ('first_choice','alternative','economic'):
        option=plan.get(key) or {}
        for line in option.get('lines') or []:
            if not isinstance(line,dict):continue
            line['patient_approved']=False
            line['requires_veterinarian_confirmation']=True
            price=line.get('price_evidence') or {}
            if price.get('status')=='automated_vendor_listed_not_clinician_verified':
                line['price_verification']='seller_listed_not_checkout_verified'
            elif line.get('cost_toman') is None:
                line['price_verification']='no_exact_retailer_listing'
    plan['clinical_plans_available']=sum(bool((plan.get(k) or {}).get('lines'))
                                        for k in ('first_choice','alternative','economic'))
    plan['clinical_plan_distinction']=(
        'Economy may use the same active ingredient; three cards do not imply '
        'three independent approved treatment regimens.')
    plan['source_truthfulness']={
        'veterinarian_signed':False,
        'all_book_pages_appraised':False,
        'full_study_methods_verified':False,
        'all_supplier_prices_available':False,
        'source_matched_dose_is_not_patient_authorization':True,
        'approved_formulary_count':len(verified_formulary),
    }
    plan['schema_version']=28
    plan['workspace_mode']='evidence_first_patient_context_auto_iran_prices'
    result['plan']=plan
    result['workflow_version']=28
    result['generated_at']=datetime.now(timezone.utc).isoformat()
    return result
