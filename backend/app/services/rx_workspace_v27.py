"""v27 one-click clinical workflow with automatic price discovery for each Rx SKU.
Separate read-only diagnostic and commercial data from clinical authorization.
"""
from __future__ import annotations
from typing import Any

from app.services.rx_workspace_v26 import run_integrated_workflow
from app.services.rx_autoprice_v27 import automatic_price_batch
from app.services.rx_treatment_v27 import construct_three_plans, _alternatives_from_formulary


async def run_three_choice_workflow(case:dict[str,Any], analysis:dict[str,Any], *,
     auto_price_fn=None, protocols=None, **v26_inputs) -> dict[str,Any]:
    response = await run_integrated_workflow(case, analysis, **v26_inputs)
    base = (response.get('plan') or {}).get('first_choice') or {}
    lines = base.get('lines') or []
    if (response.get('plan') or {}).get('clinical_safety',{}).get('red_flags'):
        lines = []
    # Also price eligible, clinician-reviewed alternative formulations. An
    # unreviewed literature mention never becomes a shopping/prescribing line.
    alternatives=_alternatives_from_formulary(case,analysis,lines,protocols=protocols)
    to_price=lines+alternatives
    try:
        auto = await (auto_price_fn(to_price) if auto_price_fn else automatic_price_batch(to_price))
    except Exception as exc:
        auto = {'status':'pricing_source_unavailable','offers_count':0,'by_sku':{},
                'checked_at':None, 'note':'Automatic supplier check failed; no price inferred.',
                'error_type':type(exc).__name__}
    return construct_three_plans(response,case,analysis,auto,protocols=protocols)
