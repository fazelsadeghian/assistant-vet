import asyncio
from typing import Any, Dict
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app.models import CaseInput
from app.services.book_ingest import ingest_pdf
from app.services.evidence_search import EvidenceSearch
from app.services.knowledge_store import KnowledgeStore
from app.services.orchestrator import BrainOrchestrator
from app.services.prescription_engine import PrescriptionPlanRequest, make_prescription_plan, PRICE_SOURCES
from app.services.treatment_evidence import discover_treatment_evidence
from app.services.rx_integrated import (build_integrated_plan, fetch_usd_toman, save_quote, _read_quotes, preview_iranian_listing)
from app.services.rx_workspace_v26 import run_integrated_workflow
from app.services.rx_workspace_v28 import run_clinical_workflow
from app.services.rx_ai_runtime_v29 import probe_ai, _model as _rx_ai_model, _timeout as _rx_ai_timeout
from app.services.rx_pricing_v26 import (audit_supplier_websites, _read_offers, save_product_quote, preview_exact_supplier_offer)

app = FastAPI(title="Assistant Vet Brain", version="0.29.0")

# Equine knowledge bridge; does not change prescription routes.
from app.services.equine_knowledge_v34 import router as equine_knowledge_router
app.include_router(equine_knowledge_router)
brain = BrainOrchestrator()
knowledge = KnowledgeStore()
evidence = EvidenceSearch()

class EvidenceRequest(BaseModel):
    query: str
    limit: int = Field(default=8, ge=1, le=20)

class KnowledgeSearchRequest(BaseModel):
    query: str
    limit: int = Field(default=8, ge=1, le=30)

class IngestBookRequest(BaseModel):
    pdf_path: str
    book_key: str
    title: str
    edition: str | None = None
    year: int | None = None

@app.get("/health")
async def health():
    return {
        "ok": True,
        "service": "assistant-vet-brain",
        "version": "0.29.0",
        "local_ai_ready": await brain.provider.available(),
        "local_ai_provider": brain.provider.name,
        "local_ai_model": brain.provider.model or None,
    }

@app.post("/analyze-case")
async def analyze_case(case: CaseInput):
    return await brain.analyze(case)

@app.post("/evidence/search")
async def search_evidence(request: EvidenceRequest):
    return {"query":request.query, "results":await evidence.combined(request.query, limit=request.limit)}

@app.post("/knowledge/search")
async def search_knowledge(request: KnowledgeSearchRequest):
    return {"query":request.query, "results":knowledge.search(request.query, limit=request.limit)}

@app.post("/knowledge/ingest-pdf")
async def knowledge_ingest(request: IngestBookRequest):
    try:
        return ingest_pdf(
            request.pdf_path,
            book_key=request.book_key,
            title=request.title,
            edition=request.edition,
            year=request.year,
        )
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=f"PDF not found: {exc}") from exc


@app.get("/prescription/price-sources")
async def get_price_sources():
    return {"sources": PRICE_SOURCES, "site_product_api_integration_verified": False,
            "usd_fx_api_integrated": True}

@app.post("/prescription/plan")
async def prescription_plan(request: PrescriptionPlanRequest):
    # Concurrent local evidence scan and bounded public USD/IRT rate lookup.
    # Any failure degrades to explicit 'no verified Rx / no FX' states.
    async def safe_discover():
        try:
            return await asyncio.wait_for(
                discover_treatment_evidence(request.case_payload, request.analysis_result), 35)
        except Exception:
            return {'status': 'source_search_unavailable', 'handbook_references':[],
                    'sources_examined':[], 'warnings':['Source search could not complete']}
    data, fx = await asyncio.gather(safe_discover(), asyncio.to_thread(fetch_usd_toman))
    return build_integrated_plan(request.case_payload, request.analysis_result, data, fx=fx)


class PriceQuoteRequest(BaseModel):
    quote: Dict[str, Any]


@app.post('/prescription/workflow')
async def prescription_workflow(request: PrescriptionPlanRequest):
    """Case -> books -> live paper screening -> local AI questions -> dual review drafts.

    All drug evidence is retrieved on the server, not trusted from UI input.
    This endpoint never signs, authorizes or dispatches medication orders.
    """
    return await run_clinical_workflow(request.case_payload, request.analysis_result)


@app.get('/prescription/source-connectors/audit')
async def prescription_connector_audit():
    """Read-only connectivity checks: site reachability is not a drug price API."""
    return await audit_supplier_websites()


@app.get('/prescription/prices/products-v26')
async def prescription_product_quotes():
    return {'offers': _read_offers(),
            'verification':'source_linked_clinician_observations_not_independently_verified'}


@app.post('/prescription/prices/products-v26')
async def prescription_store_product_quote(request: PriceQuoteRequest):
    try:
        return {'ok':True, 'observation':save_product_quote(request.quote)}
    except ValueError as exc:
        raise HTTPException(status_code=422,detail=str(exc)) from exc


@app.post('/prescription/prices/preview-v26')
async def prescription_preview_product_quote(request: PriceQuoteRequest):
    try:
        return await preview_exact_supplier_offer(request.quote)
    except ValueError as exc:
        raise HTTPException(status_code=422,detail=str(exc)) from exc






@app.get('/prescription/ai/probe')
async def prescription_ai_generation_probe():
    """Real, non-patient inference. /health checks model listing only."""
    return await probe_ai()


@app.get('/prescription/ai/config')
async def prescription_ai_runtime_config():
    return {'configured_model': _rx_ai_model(), 'rx_inference_timeout_seconds': _rx_ai_timeout(),
            'output_mode': 'structured_review_only', 'real_inference_verified_here': False,
            'verification_endpoint': '/prescription/ai/probe'}


@app.get('/prescription/diagnostics-v28')
async def prescription_diagnostics_v28():
    """Non-destructive local integration status; never claims treatment readiness."""
    from pathlib import Path
    import os
    import httpx
    from app.services.rx_research_v26 import _book_database_path
    from app.services.prescription_engine import PROTOCOLS_FILE, _load_list
    books_path=_book_database_path()
    books_present=bool(books_path and Path(books_path).is_file())
    protocols=_load_list(PROTOCOLS_FILE,'protocols')
    model=os.getenv('OLLAMA_MODEL','qwen3:8b')
    url=os.getenv('OLLAMA_BASE_URL','http://127.0.0.1:11434').rstrip('/')+'/api/tags'
    ai={'status':'unavailable','configured_model':model,'available_models':[]}
    try:
        async with httpx.AsyncClient(timeout=3.0,trust_env=False) as client:
            r=await client.get(url)
            r.raise_for_status()
            models=r.json().get('models',[])
            names=[str(m.get('name') or '') for m in models if isinstance(m,dict)]
            ai.update(status='configured_model_found' if model in names else 'model_not_downloaded',
                      available_models=names[:15])
    except (httpx.HTTPError,ValueError,OSError) as exc:
        ai['error_type']=type(exc).__name__
    return {'version':28,'local_ai':ai,
            'book_index':{'status':'file_present' if books_present else 'not_found',
                          'full_index_retrieval_verified':False},
            'clinician_formulary':{'stored_protocol_rows':len(protocols),
                                  'approved_eligibility_requires_individual_validation':True},
            'iranian_suppliers':{'pricing_mode':'automatic_exact_sku_per_supported_retailer',
                                'live_success_not_guaranteed':True},
            'clinical_authorization':False}


@app.get('/prescription/fx')
async def prescription_fx():
    return await asyncio.to_thread(fetch_usd_toman)


@app.get('/prescription/prices')
async def prescription_prices():
    return {'observations': _read_quotes(), 'verification': 'clinician_entered_unverified_external'}


@app.post('/prescription/prices/preview')
async def prescription_price_preview(request: PriceQuoteRequest):
    try:
        return await asyncio.to_thread(preview_iranian_listing, request.quote)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.post('/prescription/prices/observe')
async def prescription_price_observe(request: PriceQuoteRequest):
    try:
        return {'ok': True, 'observation': save_quote(request.quote)}
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.post("/prescription/discover")
async def prescription_discover(request: PrescriptionPlanRequest):
    # Use the discovery service's own indexed textbook lookup and saved-
    # article reuse. Passing the legacy search callbacks here bypasses both
    # fast paths and makes every request repeat slow semantic/online searches.
    return await discover_treatment_evidence(
        request.case_payload,
        request.analysis_result,
    )
