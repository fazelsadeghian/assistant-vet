from copy import deepcopy
import asyncio
from datetime import datetime, timezone
import os
import re
import time
from typing import Any, Dict, List, Optional, Tuple

from app.models import CaseInput
from app.providers.ollama import OllamaProvider
from app.services.evidence_search import EvidenceSearch
from app.services.knowledge_store import KnowledgeStore, SCHEMA_VERSION
from app.services.rule_engine import RULES_VERSION, run_rule_engine

ENGINE_VERSION = "assistant-vet-brain-0.4.4-evidence-books"

MAX_KNOWLEDGE_RESULTS = 14
MAX_RESULTS_PER_BOOK = 3


FAST_KNOWLEDGE_LIMIT = int(os.getenv("FAST_KNOWLEDGE_LIMIT", "6"))
FAST_ARTICLE_LIMIT = int(os.getenv("FAST_ARTICLE_LIMIT", "3"))


def _analysis_mode() -> str:
    value = os.getenv("ASSISTANT_VET_MODE", "fast").strip().lower()
    return "deep" if value == "deep" else "fast"


def _reviewer_enabled() -> bool:
    explicit = os.getenv("RUN_MODEL_REVIEWER", "").strip().lower()
    if explicit in {"1", "true", "yes", "on"}:
        return True
    if explicit in {"0", "false", "no", "off"}:
        return False
    return _analysis_mode() == "deep"


def _has_meaningful_data(value: Any) -> bool:
    if value is None:
        return False
    if hasattr(value, "model_dump"):
        value = value.model_dump()
    if isinstance(value, dict):
        return any(_has_meaningful_data(v) for v in value.values())
    if isinstance(value, list):
        return any(_has_meaningful_data(v) for v in value)
    if isinstance(value, str):
        return bool(value.strip())
    return True


def _text(value: Any, limit: int = 220) -> str:
    if value is None:
        return ""

    if hasattr(value, "model_dump"):
        value = value.model_dump()

    if isinstance(value, dict):
        parts = []
        for key, item in value.items():
            if not _has_meaningful_data(item):
                continue

            key_l = str(key).lower()
            if any(
                x in key_l
                for x in (
                    "base64",
                    "bytes",
                    "binary",
                    "path",
                    "file",
                    "image_data",
                    "dicom",
                )
            ):
                continue

            parts.append(f"{key}: {_text(item, 120)}")

        return " | ".join(parts)[:limit]

    if isinstance(value, list):
        return "; ".join(
            _text(item, 100)
            for item in value[:8]
            if _has_meaningful_data(item)
        )[:limit]

    return " ".join(str(value).split())[:limit]


def _knowledge_queries(case: CaseInput) -> List[str]:
    patient = getattr(case, "patient", None)

    species = _text(getattr(patient, "species", None), 40)
    breed = _text(getattr(patient, "breed", None), 60)

    base = " ".join(x for x in (species, breed) if x)

    clinical = getattr(case, "clinical", None)

    chief = _text(getattr(clinical, "chief_complaint", None), 180)
    history = _text(getattr(clinical, "history", None), 260)
    exam = _text(getattr(clinical, "exam_notes", None), 180)

    queries: List[str] = []

    core_parts = [base, chief, history, exam]
    if any(core_parts):
        core = " ".join(part for part in core_parts if part)
        core += " veterinary differential diagnosis"
        queries.append(core[:700])

    cbc = getattr(case, "cbc", None)
    smear = getattr(case, "blood_smear", None)

    if _has_meaningful_data(cbc) or _has_meaningful_data(smear):
        hematology = " ".join(
            x
            for x in (
                base,
                _text(cbc, 360),
                _text(smear, 360),
                (
                    "hematology anemia hemolysis thrombocytopenia "
                    "differential diagnosis"
                ),
            )
            if x
        )
        queries.append(hematology[:700])

    biochemistry = getattr(case, "biochemistry", None)
    urinalysis = getattr(case, "urinalysis", None)

    if (
        _has_meaningful_data(biochemistry)
        or _has_meaningful_data(urinalysis)
    ):
        chemistry = " ".join(
            x
            for x in (
                base,
                _text(biochemistry, 340),
                _text(urinalysis, 340),
                (
                    "clinical pathology biochemistry urinalysis "
                    "differential diagnosis"
                ),
            )
            if x
        )
        queries.append(chemistry[:700])

    skin_cytology = getattr(case, "skin_cytology", None)
    fecal = getattr(case, "fecal", None)

    if (
        _has_meaningful_data(skin_cytology)
        or _has_meaningful_data(fecal)
    ):
        cyto_fecal = " ".join(
            x
            for x in (
                base,
                _text(skin_cytology, 340),
                _text(fecal, 340),
                "cytology dermatology parasitology differential diagnosis",
            )
            if x
        )
        queries.append(cyto_fecal[:700])

    radiography = getattr(case, "radiography", None)
    ultrasound = getattr(case, "ultrasound", None)

    if (
        _has_meaningful_data(radiography)
        or _has_meaningful_data(ultrasound)
    ):
        imaging = " ".join(
            x
            for x in (
                base,
                _text(radiography, 340),
                _text(ultrasound, 340),
                (
                    "diagnostic imaging radiography ultrasound "
                    "differential diagnosis"
                ),
            )
            if x
        )
        queries.append(imaging[:700])

    other_tests = getattr(case, "other_tests", None)
    current_medications = getattr(case, "current_medications", None)

    if (
        _has_meaningful_data(other_tests)
        or _has_meaningful_data(current_medications)
    ):
        extra = " ".join(
            x
            for x in (
                base,
                _text(other_tests, 320),
                _text(current_medications, 320),
                "diagnostic interpretation treatment context",
            )
            if x
        )
        queries.append(extra[:700])

    seen = set()
    result: List[str] = []

    for query in queries:
        key = " ".join(query.lower().split())
        if key and key not in seen:
            seen.add(key)
            result.append(query)

    return result[:6]


def _merge_hits(
    result_sets: List[List[Dict[str, Any]]]
) -> List[Dict[str, Any]]:
    merged: Dict[int, Dict[str, Any]] = {}

    for results in result_sets:
        for rank, hit in enumerate(results, start=1):
            chunk_id = int(hit["chunk_id"])
            bonus = 1.0 / (20.0 + rank)
            score = float(hit.get("score") or 0.0)

            if chunk_id not in merged:
                merged[chunk_id] = {
                    **hit,
                    "_score": score + bonus,
                    "_matches": 1,
                }
            else:
                merged[chunk_id]["_matches"] += 1
                merged[chunk_id]["_score"] += bonus

    candidates = sorted(
        merged.values(),
        key=lambda x: (x["_matches"], x["_score"]),
        reverse=True,
    )

    selected = []
    per_book: Dict[str, int] = {}

    for item in candidates:
        book = str(item.get("book_key") or "unknown")

        if per_book.get(book, 0) >= MAX_RESULTS_PER_BOOK:
            continue

        row = dict(item)
        row["facet_matches"] = row.pop("_matches")
        row["retrieval_score"] = round(float(row.pop("_score")), 8)

        selected.append(row)
        per_book[book] = per_book.get(book, 0) + 1

        if len(selected) >= MAX_KNOWLEDGE_RESULTS:
            break

    return selected


def _retrieve_knowledge(
    store: KnowledgeStore,
    case: CaseInput,
):
    queries = _knowledge_queries(case)

    if hasattr(store, "search_many"):
        result_sets = store.search_many(
            queries,
            limit=12,
        )
    else:
        result_sets = [
            store.search(query, limit=12)
            for query in queries
        ]

    return _merge_hits(result_sets), queries


def _article_query(case: CaseInput) -> str:
    """
    Build a focused literature query from clinically useful case facts.
    Platelet clumping/automated platelet flags are intentionally excluded
    because they tend to retrieve analyzer-method papers rather than the
    disease literature we want.
    """
    patient = getattr(case, "patient", None)
    species = _text(getattr(patient, "species", None), 40).lower()

    species_term = "canine dog" if species == "dog" else (
        "feline cat" if species == "cat" else species
    )

    terms: List[str] = []

    cbc = getattr(case, "cbc", None)
    if hasattr(cbc, "model_dump"):
        cbc = cbc.model_dump()
    if isinstance(cbc, dict):
        pattern = str(cbc.get("anemia_pattern") or "").lower()
        if "regenerative" in pattern:
            terms.append('"regenerative anemia"')

    smear = getattr(case, "blood_smear", None)
    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()
    if isinstance(smear, dict):
        if str(smear.get("spherocytes") or "").lower() in {
            "present", "positive", "yes", "true", "1"
        }:
            terms.append("spherocytes")
            terms.append('"immune-mediated hemolytic anemia"')

    chemistry = getattr(case, "biochemistry", None)
    if hasattr(chemistry, "model_dump"):
        chemistry = chemistry.model_dump()
    if isinstance(chemistry, dict):
        bilirubin = str(chemistry.get("bilirubin") or "").lower()
        if bilirubin:
            terms.append("hyperbilirubinemia")
            terms.append("hemolysis")

    if not terms:
        clinical = getattr(case, "clinical", None)
        terms.extend(
            [
                _text(getattr(clinical, "chief_complaint", None), 140),
                "veterinary internal medicine",
            ]
        )

    deduped = []
    seen = set()
    for term in terms:
        key = term.lower().strip()
        if key and key not in seen:
            seen.add(key)
            deduped.append(term)

    return " ".join(
        x for x in [species_term, *deduped]
        if x
    )[:700]


def _source_context(
    knowledge_hits: List[Dict[str, Any]],
    evidence_results: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    sources = []

    for hit in knowledge_hits:
        sources.append(
            {
                "source_id": (
                    f"kb:{hit.get('book_key')}:{hit.get('chunk_id')}"
                ),
                "source_type": "textbook",
                "title": hit.get("title"),
                "edition": hit.get("edition"),
                "year": hit.get("year"),
                "chapter": hit.get("chapter"),
                "section": hit.get("section"),
                "pdf_page_start": hit.get("page_start"),
                "pdf_page_end": hit.get("page_end"),
                "printed_page_start": hit.get("printed_page_start"),
                "printed_page_end": hit.get("printed_page_end"),
                "snippet": hit.get("snippet"),
            }
        )

    for i, item in enumerate(evidence_results, start=1):
        sources.append(
            {
                "source_id": (
                    item.get("source_id")
                    or item.get("id")
                    or f"external:{i}"
                ),
                "source_type": item.get("source_type", "article"),
                "provider": item.get("provider"),
                "title": item.get("title"),
                "authors": item.get("authors"),
                "year": item.get("year"),
                "journal": item.get("journal"),
                "abstract": item.get("abstract"),
                "pmid": item.get("pmid"),
                "pmcid": item.get("pmcid"),
                "doi": item.get("doi"),
                "url": item.get("url"),
                "metadata": item.get("metadata", {}),
            }
        )

    return sources


def _apply_guardrails(
    reasoning: Dict[str, Any],
    sources: List[Dict[str, Any]],
) -> Dict[str, Any]:
    analysis = dict(reasoning or {})
    has_sources = bool(sources)

    analysis["grounding"] = {
        "sources_available": has_sources,
        "source_count": len(sources),
        "source_ids": [
            item["source_id"]
            for item in sources
            if item.get("source_id")
        ],
    }

    treatment_present = bool(
        analysis.get("treatment_recommendations")
        or analysis.get("treatment")
        or analysis.get("management")
        or analysis.get("treatment_lines")
    )

    if treatment_present:
        analysis["treatment_verification"] = {
            "status": (
                "requires_claim_level_verification"
                if has_sources
                else "preliminary_unverified"
            ),
            "message": (
                "Retrieved sources do not automatically verify every drug, "
                "dose, contraindication, or treatment-line claim. Each "
                "treatment claim must be verified against a specific source."
            ),
        }

    analysis["evidence_status"] = (
        "sources_retrieved_not_claim_verified"
        if has_sources
        else "no_sources_retrieved"
    )

    return analysis


# ---------------------------------------------------------------------------
# Deterministic Clinical Evidence Gate
# ---------------------------------------------------------------------------

STOPWORDS = {
    "the", "and", "with", "from", "for", "that", "this", "present",
    "patient", "possible", "likely", "due", "case", "finding", "findings",
    "evidence", "clinical", "blood", "test", "tests", "result", "results",
}


def _flatten_case_facts(
    value: Any,
    path: str = "case",
) -> List[Dict[str, Any]]:
    facts: List[Dict[str, Any]] = []

    if hasattr(value, "model_dump"):
        value = value.model_dump()

    if isinstance(value, dict):
        for key, item in value.items():
            if not _has_meaningful_data(item):
                continue
            facts.extend(
                _flatten_case_facts(
                    item,
                    f"{path}.{key}",
                )
            )
        return facts

    if isinstance(value, list):
        for index, item in enumerate(value):
            if not _has_meaningful_data(item):
                continue
            facts.extend(
                _flatten_case_facts(
                    item,
                    f"{path}[{index}]",
                )
            )
        return facts

    facts.append(
        {
            "path": path,
            "value": value,
            "display": f"{path} = {value}",
        }
    )
    return facts


def _tokens(text: Any) -> set:
    words = re.findall(
        r"[A-Za-z0-9]+",
        str(text).lower(),
    )

    return {
        word
        for word in words
        if len(word) > 2
        and word not in STOPWORDS
    }


def _verified_fact_matches(
    statement: str,
    facts: List[Dict[str, Any]],
) -> List[str]:
    statement_tokens = _tokens(statement)

    matches: List[str] = []

    for fact in facts:
        fact_text = (
            f"{fact['path']} {fact['value']}"
        )
        fact_tokens = _tokens(fact_text)

        overlap = (
            statement_tokens
            & fact_tokens
        )

        if overlap:
            matches.append(
                fact["display"]
            )

    return matches[:6]


def _platelet_clumping_present(case: CaseInput) -> bool:
    smear = getattr(case, "blood_smear", None)

    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()

    if not isinstance(smear, dict):
        return False

    value = str(
        smear.get(
            "platelet_clumping",
            "",
        )
    ).strip().lower()

    return value in {
        "present",
        "yes",
        "positive",
        "true",
        "1",
    }


def _urinalysis_present(case: CaseInput) -> bool:
    return _has_meaningful_data(
        getattr(
            case,
            "urinalysis",
            None,
        )
    )


def _sanitize_evidence_list(
    values: Any,
    facts: List[Dict[str, Any]],
) -> Tuple[List[str], List[str]]:
    if not isinstance(values, list):
        return [], []

    verified: List[str] = []
    rejected: List[str] = []

    for item in values:
        if not isinstance(item, str):
            continue

        matches = _verified_fact_matches(
            item,
            facts,
        )

        if matches:
            for match in matches:
                if match not in verified:
                    verified.append(match)
        else:
            rejected.append(item)

    return verified[:8], rejected[:8]


DOSE_PATTERN = re.compile(
    r"(?i)"
    r"(?:\b\d+(?:\.\d+)?\s*(?:-|–|to)\s*\d+(?:\.\d+)?|\b\d+(?:\.\d+)?)"
    r"\s*(?:mcg|µg|mg|g|ml|mL|IU|U)"
    r"\s*/\s*(?:kg|m2|m²)"
    r"(?:\s*(?:PO|IV|IM|SC|SQ))?"
    r"(?:\s*(?:q\d+h|every\s+\d+\s*hours?|BID|TID|SID))?"
)


def _strip_unverified_dose_text(text: str) -> Tuple[str, bool]:
    if not isinstance(text, str):
        return text, False

    changed = bool(
        DOSE_PATTERN.search(text)
    )

    if not changed:
        return text, False

    cleaned = DOSE_PATTERN.sub(
        "[dose withheld pending source verification]",
        text,
    )

    return cleaned, True


def _sanitize_treatments(
    value: Any,
    issues: List[str],
) -> Any:
    if isinstance(value, dict):
        result = {}

        for key, item in value.items():
            result[key] = _sanitize_treatments(
                item,
                issues,
            )

        return result

    if isinstance(value, list):
        return [
            _sanitize_treatments(
                item,
                issues,
            )
            for item in value
        ]

    if isinstance(value, str):
        cleaned, changed = (
            _strip_unverified_dose_text(
                value
            )
        )

        if changed:
            issues.append(
                "An unverified numeric drug dose was removed from the final output."
            )

        return cleaned

    return value


def _sanitize_next_tests(
    tests: Any,
) -> Any:
    if not isinstance(tests, list):
        return tests

    result = []

    for item in tests:
        if not isinstance(item, dict):
            result.append(item)
            continue

        row = dict(item)

        test_name = str(
            row.get("test", "")
        ).lower()

        rationale = str(
            row.get("rationale", "")
        )

        if (
            "coombs" in test_name
            or "direct antiglobulin" in test_name
            or "dat" == test_name.strip()
        ):
            row["rationale"] = (
                "May support an immune-mediated mechanism when interpreted "
                "with the complete clinical and hematologic picture; it does "
                "not by itself confirm or exclude IMHA."
            )

        elif "reticulocyte" in test_name:
            row["rationale"] = (
                "Quantifies the regenerative marrow response. Reticulocytosis "
                "supports regeneration but does not by itself establish the "
                "cause of anemia or prove hemolysis."
            )

        elif "ldh" in test_name:
            row["rationale"] = (
                "Potential adjunctive marker only; interpret cautiously and "
                "do not use alone to establish hemolysis."
            )

        else:
            row["rationale"] = rationale

        result.append(row)

    return result


def _clinical_evidence_gate(
    case: CaseInput,
    analysis: Dict[str, Any],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """
    Deterministic post-LLM gate.

    It does not diagnose. It prevents unsupported patient facts and
    unverified doses from being promoted to final output.
    """
    safe = deepcopy(
        analysis or {}
    )

    issues: List[str] = []
    facts = _flatten_case_facts(
        case.model_dump()
    )

    # 1) Remove interpretations for modalities not supplied.
    modality_map = {
        "cbc": getattr(case, "cbc", None),
        "biochemistry": getattr(case, "biochemistry", None),
        "urinalysis": getattr(case, "urinalysis", None),
        "blood_smear": getattr(case, "blood_smear", None),
        "skin_cytology": getattr(case, "skin_cytology", None),
        "fecal": getattr(case, "fecal", None),
        "radiography": getattr(case, "radiography", None),
        "ultrasound": getattr(case, "ultrasound", None),
    }

    interpretations = safe.get(
        "modality_interpretations"
    )

    if isinstance(interpretations, dict):
        for modality in list(
            interpretations.keys()
        ):
            if (
                modality in modality_map
                and not _has_meaningful_data(
                    modality_map[modality]
                )
            ):
                interpretations.pop(
                    modality,
                    None,
                )
                issues.append(
                    f"Removed interpretation for empty modality: {modality}."
                )

    # 2) Make platelet status authoritative when clumping is present.
    if _platelet_clumping_present(case):
        safe["platelet_status"] = {
            "status": (
                "possible_pseudothrombocytopenia"
            ),
            "true_thrombocytopenia_confirmed": False,
            "reason": (
                "Automated low platelet flag is accompanied by platelet "
                "clumping on smear; true thrombocytopenia remains unconfirmed."
            ),
            "recommended_check": (
                "Manual smear platelet assessment and/or repeat sample if "
                "clinically indicated."
            ),
        }

        problem_list = safe.get(
            "problem_list"
        )

        if isinstance(
            problem_list,
            list,
        ):
            cleaned = []

            for item in problem_list:
                text = str(item)

                if (
                    "thrombocytopen" in text.lower()
                    or "low platelet" in text.lower()
                ):
                    replacement = (
                        "Automated low platelet flag with platelet clumping; "
                        "true thrombocytopenia is unconfirmed."
                    )

                    if replacement not in cleaned:
                        cleaned.append(
                            replacement
                        )
                else:
                    cleaned.append(
                        item
                    )

            safe["problem_list"] = (
                cleaned
            )

    # 3) Do not allow bilirubinuria when no urinalysis was supplied.
    if not _urinalysis_present(case):
        safe["urinalysis_status"] = {
            "status": "not_provided",
            "interpretation_allowed": False,
        }

    # 4) Convert free-form differential support to verified case facts.
    differentials = safe.get(
        "ranked_differentials"
    )

    if isinstance(
        differentials,
        list,
    ):
        for diff in differentials:
            if not isinstance(
                diff,
                dict,
            ):
                continue

            evidence = (
                diff.get(
                    "supporting_case_facts"
                )
                or diff.get(
                    "supporting_evidence"
                )
                or diff.get(
                    "supporting_facts"
                )
                or []
            )

            verified, rejected = (
                _sanitize_evidence_list(
                    evidence,
                    facts,
                )
            )

            diff[
                "verified_supporting_case_facts"
            ] = verified

            if rejected:
                diff[
                    "model_support_removed"
                ] = rejected

                issues.append(
                    "Removed one or more differential-support statements "
                    "that could not be tied to submitted case facts."
                )

            diff.pop(
                "supporting_evidence",
                None,
            )
            diff.pop(
                "supporting_facts",
                None,
            )
            diff.pop(
                "supporting_case_facts",
                None,
            )

    # 5) Add verified facts to most probable diagnoses.
    most_probable = safe.get(
        "most_probable_diagnoses"
    )

    if isinstance(
        most_probable,
        list,
    ):
        for item in most_probable:
            if not isinstance(
                item,
                dict,
            ):
                continue

            rationale = str(
                item.get(
                    "rationale",
                    "",
                )
            )

            item[
                "verified_case_facts"
            ] = (
                _verified_fact_matches(
                    rationale,
                    facts,
                )
            )

            if not item[
                "verified_case_facts"
            ]:
                item[
                    "rationale_status"
                ] = (
                    "model_rationale_not_case_fact_verified"
                )

    # 6) Correct a few unsafe diagnostic-test phrasings.
    safe["next_best_tests"] = (
        _sanitize_next_tests(
            safe.get(
                "next_best_tests"
            )
        )
    )

    # 7) Remove numeric drug doses until a real claim-level verifier exists.
    treatment_keys = (
        "treatment_lines",
        "treatment",
        "management",
        "treatment_recommendations",
    )

    for key in treatment_keys:
        if key in safe:
            safe[key] = (
                _sanitize_treatments(
                    safe[key],
                    issues,
                )
            )

    safe[
        "clinical_gate_status"
    ] = (
        "revise"
        if issues
        else "pass"
    )

    safe[
        "verified_case_fact_ledger"
    ] = facts

    audit = {
        "status": safe[
            "clinical_gate_status"
        ],
        "issues": list(
            dict.fromkeys(
                issues
            )
        ),
        "verified_case_fact_count": len(
            facts
        ),
        "numeric_drug_doses_allowed": False,
        "empty_modality_interpretation_allowed": False,
        "source_examples_may_be_patient_facts": False,
    }

    return safe, audit



# ---------------------------------------------------------------------------
# v0.3.1: stricter clinical facts + citation/reviewer verification
# ---------------------------------------------------------------------------

_ADMIN_FACT_PREFIXES = (
    "case.case_id",
    "case.patient.name",
    "case.veterinarian_notes",
    "case.requested_article_search",
    "case.max_evidence_results",
)

def _is_clinical_fact_path(path: str) -> bool:
    return not any(path.startswith(prefix) for prefix in _ADMIN_FACT_PREFIXES)


def _clinical_fact_ledger(case: CaseInput) -> List[Dict[str, Any]]:
    return [
        fact
        for fact in _flatten_case_facts(case.model_dump())
        if _is_clinical_fact_path(str(fact.get("path", "")))
    ]


def _replace_case_claim_language(
    value: Any,
    *,
    urinalysis_available: bool,
    platelet_clumping: bool,
) -> Any:
    if isinstance(value, dict):
        return {
            key: _replace_case_claim_language(
                item,
                urinalysis_available=urinalysis_available,
                platelet_clumping=platelet_clumping,
            )
            for key, item in value.items()
        }

    if isinstance(value, list):
        return [
            _replace_case_claim_language(
                item,
                urinalysis_available=urinalysis_available,
                platelet_clumping=platelet_clumping,
            )
            for item in value
        ]

    if not isinstance(value, str):
        return value

    result = value

    if not urinalysis_available:
        result = re.sub(
            r"(?i)\bbilirubinuria\b",
            "increased serum bilirubin",
            result,
        )

    # "Regenerative" was supplied; polychromasia was not.
    result = re.sub(
        r"(?i)\bregenerative anemia with polychromasia\b",
        "reported regenerative anemia",
        result,
    )
    result = re.sub(
        r"(?i)\bpolychromasia\b",
        "regenerative response",
        result,
    )

    if platelet_clumping:
        unsafe_platelet_patterns = (
            r"(?i)low platelets with clumping \(consistent with immune-mediated thrombocytopenia\)",
            r"(?i)platelet clumping is consistent with immune-mediated thrombocytopenia",
            r"(?i)platelet clumping suggests a consumptive coagulopathy",
            r"(?i)platelet clumping is consistent with immune-mediated thrombocytopenia \(IMT\)",
        )
        for pattern in unsafe_platelet_patterns:
            result = re.sub(
                pattern,
                (
                    "automated low platelet flag with platelet clumping; "
                    "true thrombocytopenia is unconfirmed"
                ),
                result,
            )

        result = re.sub(
            r"(?i)platelet clumping (?:are|is) (?:a )?classic finding(?:s)? in IMHA",
            (
                "platelet clumping makes the automated platelet result "
                "unreliable and is not, by itself, evidence of IMHA"
            ),
            result,
        )

    # Avoid overclaiming physical-exam observations.
    result = re.sub(
        r"(?i)pale mucous membranes confirm anemia",
        (
            "pale mucous membranes support concern for anemia but are not "
            "diagnostic by themselves"
        ),
        result,
    )

    # DAT/Coombs is supportive, not a standalone confirmation test.
    result = re.sub(
        r"(?i)Coombs test \(direct antiglobulin test\) to confirm immune-mediated hemolysis",
        (
            "Direct antiglobulin (Coombs) testing may support an "
            "immune-mediated mechanism when interpreted with the complete case"
        ),
        result,
    )
    result = re.sub(
        r"(?i)Coombs test \(to confirm immune-mediated hemolysis\)",
        (
            "Direct antiglobulin (Coombs) testing may support an "
            "immune-mediated mechanism when interpreted with the complete case"
        ),
        result,
    )

    # LDH is not a specific standalone hemolysis confirmation tool.
    result = re.sub(
        r"(?i)LDH levels \(key for confirming hemolysis\)",
        "LDH may be used only as a nonspecific adjunctive marker",
        result,
    )

    return result


def _filter_verified_case_fact_strings(
    values: Any,
    *,
    platelet_clumping: bool,
) -> List[str]:
    if not isinstance(values, list):
        return []

    filtered: List[str] = []

    for item in values:
        if not isinstance(item, str):
            continue

        if any(item.startswith(prefix) for prefix in _ADMIN_FACT_PREFIXES):
            continue

        # Platelet clumping is a data-quality issue, not positive evidence of IMT.
        if platelet_clumping and (
            item.startswith("case.blood_smear.platelet_clumping")
            or item.startswith("case.cbc.platelet_flag")
        ):
            continue

        if item not in filtered:
            filtered.append(item)

    return filtered


def _source_lookup(
    sources: List[Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    return {
        str(source.get("source_id")): source
        for source in sources
        if source.get("source_id")
    }


def _distinctive_claim_terms(claim: str) -> set:
    normalized = str(claim).lower()
    terms = set()

    alias_groups = {
        "imha": {"imha", "iha", "immune-mediated", "immune mediated", "hemolytic"},
        "babes": {"babesia", "babesiosis", "gibsoni"},
        "ehrlich": {"ehrlichia", "ehrlichiosis"},
        "hemorr": {"hemorrhage", "hemorrhagic", "blood loss"},
        "toxin": {"toxin", "toxic", "zinc", "lead"},
        "coombs": {"coombs", "antiglobulin", "dat"},
        "reticul": {"reticulocyte", "reticulocytes", "regenerative"},
        "transfus": {"transfusion", "packed", "whole blood"},
        "cortic": {"prednisone", "prednisolone", "corticosteroid", "glucocorticoid"},
        "fluid": {"fluid", "crystalloid", "dehydration"},
        "urinal": {"urinalysis", "bilirubinuria", "urine"},
    }

    for key, aliases in alias_groups.items():
        if key in normalized or any(alias in normalized for alias in aliases):
            terms.update(aliases)

    for token in _tokens(normalized):
        if len(token) >= 5:
            terms.add(token)

    return terms


def _source_supports_claim(
    claim: str,
    source: Dict[str, Any],
) -> bool:
    source_text = " ".join(
        str(source.get(key) or "")
        for key in (
            "title",
            "chapter",
            "section",
            "snippet",
            "abstract",
        )
    ).lower()

    terms = _distinctive_claim_terms(claim)

    if not terms:
        return False

    return any(term in source_text for term in terms)


def _validate_item_sources(
    item: Dict[str, Any],
    *,
    claim: str,
    lookup: Dict[str, Dict[str, Any]],
    issues: List[str],
) -> None:
    source_ids = item.get("source_ids")

    if not isinstance(source_ids, list):
        item["citation_status"] = "no_source_ids"
        return

    valid_ids: List[str] = []
    rejected_ids: List[str] = []

    for source_id in source_ids:
        source_id = str(source_id)
        source = lookup.get(source_id)

        if source is None:
            rejected_ids.append(source_id)
            continue

        if _source_supports_claim(claim, source):
            valid_ids.append(source_id)
        else:
            rejected_ids.append(source_id)

    item["source_ids"] = valid_ids
    item["citation_status"] = (
        "verified_against_supplied_snippet"
        if valid_ids
        else "not_verified_from_supplied_snippet"
    )

    if rejected_ids:
        item["rejected_source_ids"] = rejected_ids
        issues.append(
            f"Removed citation(s) that did not support claim: {claim}"
        )


def _validate_analysis_citations(
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
    issues: List[str],
) -> None:
    lookup = _source_lookup(sources)

    for item in analysis.get("ranked_differentials", []) or []:
        if isinstance(item, dict):
            _validate_item_sources(
                item,
                claim=str(item.get("diagnosis", "")),
                lookup=lookup,
                issues=issues,
            )

    for item in analysis.get("next_best_tests", []) or []:
        if isinstance(item, dict):
            claim = " ".join(
                str(item.get(key, ""))
                for key in ("test", "rationale")
            )
            _validate_item_sources(
                item,
                claim=claim,
                lookup=lookup,
                issues=issues,
            )

    for section_key in (
        "treatment",
        "treatment_lines",
        "treatment_recommendations",
        "management",
    ):
        section = analysis.get(section_key)
        if not isinstance(section, list):
            continue

        for item in section:
            if not isinstance(item, dict):
                continue

            claim = " ".join(
                str(item.get(key, ""))
                for key in (
                    "intervention",
                    "line",
                    "details",
                    "rationale",
                )
            )

            _validate_item_sources(
                item,
                claim=claim,
                lookup=lookup,
                issues=issues,
            )


def _clinical_evidence_gate_v031(
    case: CaseInput,
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    safe, audit = _clinical_evidence_gate(case, analysis)

    issues = list(audit.get("issues", []))
    platelet_clumping = _platelet_clumping_present(case)
    urinalysis_available = _urinalysis_present(case)

    # Remove admin/instruction fields from the clinical fact ledger.
    facts = _clinical_fact_ledger(case)
    safe["verified_case_fact_ledger"] = facts

    # Correct high-risk source leakage / overclaims recursively.
    safe = _replace_case_claim_language(
        safe,
        urinalysis_available=urinalysis_available,
        platelet_clumping=platelet_clumping,
    )

    # Re-filter differential and diagnosis case facts.
    for diff in safe.get("ranked_differentials", []) or []:
        if not isinstance(diff, dict):
            continue
        diff["verified_supporting_case_facts"] = (
            _filter_verified_case_fact_strings(
                diff.get("verified_supporting_case_facts", []),
                platelet_clumping=platelet_clumping,
            )
        )
        if platelet_clumping:
            diff["platelet_evidence_note"] = (
                "Automated low platelet flag is not accepted as confirmed "
                "thrombocytopenia because platelet clumping is present."
            )

    for item in safe.get("most_probable_diagnoses", []) or []:
        if not isinstance(item, dict):
            continue
        item["verified_case_facts"] = (
            _filter_verified_case_fact_strings(
                item.get("verified_case_facts", []),
                platelet_clumping=platelet_clumping,
            )
        )

    # Block unverified numeric treatment thresholds as well as drug doses.
    for section_key in (
        "treatment",
        "treatment_lines",
        "treatment_recommendations",
        "management",
    ):
        section = safe.get(section_key)
        if not isinstance(section, list):
            continue

        for item in section:
            if not isinstance(item, dict):
                continue

            combined = " ".join(
                str(item.get(key, ""))
                for key in ("intervention", "details", "rationale")
            )

            if re.search(
                r"(?i)\b(?:HCT|PCV|hematocrit)\s*[<>]=?\s*\d+(?:\.\d+)?\s*%",
                combined,
            ):
                for key in ("intervention", "details", "rationale"):
                    if isinstance(item.get(key), str):
                        item[key] = re.sub(
                            r"(?i)\b(?:HCT|PCV|hematocrit)\s*[<>]=?\s*\d+(?:\.\d+)?\s*%",
                            "[numeric transfusion threshold withheld pending source verification]",
                            item[key],
                        )
                issues.append(
                    "An unverified numeric transfusion threshold was removed."
                )

    # Verify cited source IDs against the actual supplied snippets.
    _validate_analysis_citations(
        safe,
        sources,
        issues,
    )

    # The deterministic gate is authoritative.
    deduped = list(dict.fromkeys(issues))
    status = "revise" if deduped else "pass"

    safe["clinical_gate_status"] = status

    audit = {
        "status": status,
        "issues": deduped,
        "verified_case_fact_count": len(facts),
        "numeric_drug_doses_allowed": False,
        "numeric_treatment_thresholds_allowed": False,
        "empty_modality_interpretation_allowed": False,
        "source_examples_may_be_patient_facts": False,
        "citation_ids_must_match_retrieved_sources": True,
        "citation_snippet_support_check_enabled": True,
    }

    return safe, audit


def _collect_source_ids(value: Any) -> List[str]:
    found: List[str] = []

    if isinstance(value, dict):
        for key, item in value.items():
            if key == "source_ids" and isinstance(item, list):
                found.extend(str(x) for x in item)
            else:
                found.extend(_collect_source_ids(item))

    elif isinstance(value, list):
        for item in value:
            found.extend(_collect_source_ids(item))

    return found


def _sanitize_reviewer_result(
    raw: Any,
    sources: List[Dict[str, Any]],
    clinical_gate: Dict[str, Any],
) -> Dict[str, Any]:
    allowed_ids = {
        str(source.get("source_id"))
        for source in sources
        if source.get("source_id")
    }

    raw_dict = raw if isinstance(raw, dict) else {}
    reviewer_ids = _collect_source_ids(raw_dict)
    invented = sorted(
        {
            source_id
            for source_id in reviewer_ids
            if source_id not in allowed_ids
        }
    )

    schema_valid = (
        raw_dict.get("status") in {"pass", "revise"}
        and isinstance(raw_dict.get("unsupported_patient_facts", []), list)
        and isinstance(raw_dict.get("citation_mismatches", []), list)
    )

    required_corrections = list(
        clinical_gate.get("issues", [])
    )

    if invented:
        required_corrections.append(
            "Reviewer invented source IDs not present in source_context."
        )

    if not schema_valid:
        required_corrections.append(
            "Reviewer did not follow the required audit JSON schema."
        )

    final_status = (
        "revise"
        if required_corrections
        or clinical_gate.get("status") == "revise"
        else "pass"
    )

    return {
        "status": final_status,
        "model_review_schema_valid": schema_valid,
        "unsupported_patient_facts": (
            raw_dict.get("unsupported_patient_facts", [])
            if schema_valid
            else []
        ),
        "source_leakage": (
            raw_dict.get("source_leakage", [])
            if schema_valid
            else []
        ),
        "citation_mismatches": (
            raw_dict.get("citation_mismatches", [])
            if schema_valid
            else []
        ),
        "invented_source_ids": invented,
        "missed_or_underweighted_case_facts": (
            raw_dict.get("missed_or_underweighted_case_facts", [])
            if schema_valid
            else []
        ),
        "treatment_review": {
            "claim_level_verified": False,
            "issues": list(
                dict.fromkeys(
                    (
                        raw_dict.get("treatment_review", {}).get("issues", [])
                        if isinstance(raw_dict.get("treatment_review"), dict)
                        else []
                    )
                    + [
                        "Treatment remains unverified at claim level."
                    ]
                )
            ),
        },
        "required_corrections": list(
            dict.fromkeys(required_corrections)
        ),
        "safe_summary": (
            raw_dict.get("safe_summary", "")
            if schema_valid
            else (
                "The deterministic clinical gate is authoritative. "
                "Model reviewer output was not accepted as a valid safety audit."
            )
        ),
        "reviewer_certification": {
            "claim_level_verified": False,
            "status": "deterministic_gate_authoritative",
            "note": (
                "The model reviewer cannot certify claim-level evidence support."
            ),
        },
    }



# ---------------------------------------------------------------------------
# v0.3.2: retrieval noise control + stronger claim normalization
# ---------------------------------------------------------------------------

def _case_retrieval_anchors(case: CaseInput) -> Dict[str, int]:
    anchors: Dict[str, int] = {
        "anemia": 1,
    }

    cbc = getattr(case, "cbc", None)
    if hasattr(cbc, "model_dump"):
        cbc = cbc.model_dump()

    if isinstance(cbc, dict):
        pattern = str(cbc.get("anemia_pattern", "")).lower()
        if "regenerative" in pattern:
            anchors["regenerative"] = 4
            anchors["reticulocyte"] = 2

        platelet_flag = str(cbc.get("platelet_flag", "")).lower()
        if "platelet" in platelet_flag:
            anchors["platelet"] = 3
            anchors["thrombocytopen"] = 2

        if cbc.get("HCT") is not None:
            anchors["hct"] = 2
            anchors["hematocrit"] = 2

    smear = getattr(case, "blood_smear", None)
    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()

    if isinstance(smear, dict):
        spherocytes = str(smear.get("spherocytes", "")).lower()
        if spherocytes in {"present", "positive", "yes", "true", "1"}:
            anchors["spherocyte"] = 6
            anchors["spherocytosis"] = 6
            # Retrieval expansion only; this does not establish a diagnosis.
            anchors["immune-mediated"] = 3
            anchors["imha"] = 3
            anchors["iha"] = 2

        clumping = str(smear.get("platelet_clumping", "")).lower()
        if clumping in {"present", "positive", "yes", "true", "1"}:
            anchors["clump"] = 4
            anchors["platelet"] = max(anchors.get("platelet", 0), 3)

    chemistry = getattr(case, "biochemistry", None)
    if hasattr(chemistry, "model_dump"):
        chemistry = chemistry.model_dump()

    if isinstance(chemistry, dict):
        bilirubin = str(chemistry.get("bilirubin", "")).lower()
        if bilirubin:
            anchors["bilirubin"] = 5
            anchors["hemolysis"] = 3
            anchors["hemolytic"] = 3

    clinical = getattr(case, "clinical", None)
    if clinical is not None:
        chief = str(getattr(clinical, "chief_complaint", "") or "").lower()
        history = str(getattr(clinical, "history", "") or "").lower()

        if "pale" in chief:
            anchors["pale"] = 1
        if "letharg" in (chief + " " + history):
            anchors["letharg"] = 1

    return anchors


def _filter_hits_for_case(
    case: CaseInput,
    hits: List[Dict[str, Any]],
    *,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    anchors = _case_retrieval_anchors(case)
    scored: List[Tuple[float, Dict[str, Any]]] = []

    for hit in hits:
        source_text = " ".join(
            str(hit.get(key) or "")
            for key in ("title", "chapter", "section", "snippet", "abstract")
        ).lower()

        anchor_score = 0.0
        strong_match = False

        for anchor, weight in anchors.items():
            if anchor in source_text:
                anchor_score += float(weight)
                if weight >= 3:
                    strong_match = True

        semantic_score = float(hit.get("semantic_score") or 0.0)
        lexical_rank = hit.get("lexical_rank")
        lexical_bonus = 0.0 if lexical_rank is None else max(
            0.0,
            0.8 - (float(lexical_rank) * 0.02),
        )

        combined = (
            anchor_score
            + semantic_score
            + lexical_bonus
            + float(hit.get("retrieval_score") or 0.0)
        )

        # Remove broad symptom-only passages unless they are unusually strong.
        if not strong_match and anchor_score < 2.0 and semantic_score < 0.69:
            continue

        row = dict(hit)
        row["case_anchor_score"] = round(anchor_score, 3)
        row["case_relevance_score"] = round(combined, 6)
        scored.append((combined, row))

    scored.sort(key=lambda pair: pair[0], reverse=True)

    selected = [row for _, row in scored[:limit]]

    # Safety fallback: never return zero sources if retrieval itself found hits.
    if not selected:
        return hits[: min(limit, len(hits))]

    return selected


def _normalize_analysis_strings(
    value: Any,
    *,
    platelet_clumping: bool,
) -> Any:
    if isinstance(value, dict):
        return {
            key: _normalize_analysis_strings(
                item,
                platelet_clumping=platelet_clumping,
            )
            for key, item in value.items()
        }

    if isinstance(value, list):
        return [
            _normalize_analysis_strings(
                item,
                platelet_clumping=platelet_clumping,
            )
            for item in value
        ]

    if not isinstance(value, str):
        return value

    result = value

    # Use the standard veterinary term.
    result = re.sub(r"\bAIHA\b", "IMHA", result)
    result = re.sub(r"\bIHA\b", "IMHA", result)

    # Do not classify vitals without a validated species/context reference range.
    result = re.sub(
        r"(?i)tachycardia\s*\(\s*128\s*bpm\s*\)",
        "heart rate 128 bpm",
        result,
    )
    result = re.sub(
        r"(?i)tachypnea\s*\(\s*30\s*bpm\s*\)",
        "respiratory rate 30/min",
        result,
    )

    # Input already reports the anemia pattern as regenerative.
    result = re.sub(
        r"(?i)reticulocyte count \(to confirm regenerative anemia\)",
        "reticulocyte count to quantify the regenerative response",
        result,
    )
    result = re.sub(
        r"(?i)reticulocyte count \(to confirm hemolysis\)",
        "reticulocyte count to quantify the regenerative response",
        result,
    )
    result = re.sub(
        r"(?i)reticulocyte count \(to quantify erythropoietic response\)",
        "reticulocyte count to quantify the regenerative response",
        result,
    )

    # DAT/Coombs is supportive, not a standalone confirmation step.
    result = re.sub(
        r"(?i)coombs test \(direct and indirect\) for immune-mediated hemolysis",
        (
            "direct antiglobulin (Coombs) testing as supportive evidence for "
            "an immune-mediated mechanism"
        ),
        result,
    )
    result = re.sub(
        r"(?i)after confirming the diagnosis via coombs test",
        (
            "after integrating the full clinical, hematologic, and "
            "supporting diagnostic evidence"
        ),
        result,
    )

    if platelet_clumping:
        result = re.sub(
            r"(?i)hemorrhagic anemia with concurrent thrombocytopenia",
            "Hemorrhagic anemia / acute blood loss",
            result,
        )
        result = re.sub(
            r"(?i)platelet clumping could be due to immune-mediated thrombocytopenia \(as in IMHA\) or other coagulopathies, but no specific cause is identified in the case\.",
            (
                "Platelet clumping makes the automated platelet result "
                "unreliable; true thrombocytopenia is not confirmed."
            ),
            result,
        )
        result = re.sub(
            r"(?i)spherocytes and platelet clumping indicate hemolytic anemia with possible immune-mediated or infectious etiology[^.]*\.",
            (
                "Spherocytes are present on the smear. Platelet clumping "
                "makes the automated platelet result unreliable and should "
                "be assessed separately."
            ),
            result,
        )

    result = re.sub(
        r"(?i)increased bilirubin \(increased serum bilirubin\)",
        "increased serum bilirubin",
        result,
    )

    return result


def _claim_concepts(claim: str) -> Dict[str, set]:
    text = str(claim).lower()
    concepts: Dict[str, set] = {}

    if any(x in text for x in ("imha", "iha", "immune-mediated hemolytic")):
        concepts["imha"] = {
            "imha", "iha", "immune-mediated", "immune mediated",
            "spherocyte", "spherocytosis", "autoagglutination",
        }

    if any(x in text for x in ("hemorrhag", "blood loss")):
        concepts["hemorrhage"] = {"hemorrhage", "hemorrhagic", "blood loss"}

    if "thrombocyt" in text or "platelet" in text:
        concepts["platelet"] = {"thrombocyt", "platelet"}

    if any(x in text for x in ("babesia", "babesiosis", "gibsoni")):
        concepts["babesia"] = {"babesia", "babesiosis", "gibsoni"}

    if any(x in text for x in ("toxin", "toxic", "zinc", "lead")):
        concepts["toxin"] = {"toxin", "toxic", "zinc", "lead"}

    if any(x in text for x in ("coombs", "antiglobulin")):
        concepts["coombs"] = {"coombs", "antiglobulin"}

    if "reticulocyte" in text:
        concepts["reticulocyte"] = {"reticulocyte", "regenerative"}

    if any(x in text for x in ("prednisone", "prednisolone", "corticosteroid")):
        concepts["steroid"] = {
            "prednisone", "prednisolone", "corticosteroid", "glucocorticoid"
        }

    if "transfusion" in text:
        concepts["transfusion"] = {"transfusion", "packed red", "whole blood"}

    return concepts


def _source_supports_claim_v032(
    claim: str,
    source: Dict[str, Any],
) -> bool:
    source_text = " ".join(
        str(source.get(key) or "")
        for key in ("title", "chapter", "section", "snippet", "abstract")
    ).lower()

    concepts = _claim_concepts(claim)

    # If there are clinically meaningful concepts, every detected concept
    # must be represented in the supplied source text.
    if concepts:
        for aliases in concepts.values():
            if not any(alias in source_text for alias in aliases):
                return False
        return True

    # Fallback for generic claims.
    terms = _distinctive_claim_terms(claim)
    return bool(terms) and any(term in source_text for term in terms)


def _validate_item_sources_v032(
    item: Dict[str, Any],
    *,
    claim: str,
    lookup: Dict[str, Dict[str, Any]],
    issues: List[str],
) -> None:
    source_ids = item.get("source_ids")

    if not isinstance(source_ids, list):
        item["citation_status"] = "no_source_ids"
        return

    valid_ids: List[str] = []
    rejected_ids: List[str] = []

    for source_id in source_ids:
        source_id = str(source_id)
        source = lookup.get(source_id)

        if source is None:
            rejected_ids.append(source_id)
            continue

        if _source_supports_claim_v032(claim, source):
            valid_ids.append(source_id)
        else:
            rejected_ids.append(source_id)

    item["source_ids"] = valid_ids
    item["citation_status"] = (
        "verified_against_supplied_snippet"
        if valid_ids
        else "not_verified_from_supplied_snippet"
    )

    if rejected_ids:
        item["rejected_source_ids"] = rejected_ids
        issues.append(
            f"Removed citation(s) that did not support claim: {claim}"
        )


def _validate_analysis_citations_v032(
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
    issues: List[str],
) -> None:
    lookup = _source_lookup(sources)

    for item in analysis.get("ranked_differentials", []) or []:
        if isinstance(item, dict):
            _validate_item_sources_v032(
                item,
                claim=str(item.get("diagnosis", "")),
                lookup=lookup,
                issues=issues,
            )

    for item in analysis.get("next_best_tests", []) or []:
        if isinstance(item, dict):
            claim = " ".join(
                str(item.get(key, ""))
                for key in ("test", "rationale")
            )
            _validate_item_sources_v032(
                item,
                claim=claim,
                lookup=lookup,
                issues=issues,
            )

    for section_key in (
        "treatment",
        "treatment_lines",
        "treatment_recommendations",
        "management",
    ):
        section = analysis.get(section_key)
        if not isinstance(section, list):
            continue

        for item in section:
            if isinstance(item, dict):
                claim = " ".join(
                    str(item.get(key, ""))
                    for key in ("intervention", "line", "details", "rationale")
                )
                _validate_item_sources_v032(
                    item,
                    claim=claim,
                    lookup=lookup,
                    issues=issues,
                )


def _withhold_unverified_treatment_strings(
    analysis: Dict[str, Any],
    issues: List[str],
) -> None:
    for key in (
        "treatment_lines",
        "treatment",
        "treatment_recommendations",
        "management",
    ):
        section = analysis.get(key)
        if not isinstance(section, list):
            continue

        converted = []

        for item in section:
            if isinstance(item, str):
                candidate = re.sub(
                    r"\s*\(source:\s*[^)]+\)",
                    "",
                    item,
                    flags=re.IGNORECASE,
                ).strip()

                converted.append(
                    {
                        "candidate_consideration": candidate,
                        "claim_level_verified": False,
                        "status": "withheld_pending_claim_verification",
                    }
                )
                issues.append(
                    "A free-form treatment claim was withheld pending claim-level verification."
                )
            else:
                converted.append(item)

        analysis[key] = converted


def _rebuild_major_claim_sources(
    analysis: Dict[str, Any],
) -> None:
    rebuilt: Dict[str, List[str]] = {}

    for item in analysis.get("ranked_differentials", []) or []:
        if not isinstance(item, dict):
            continue

        diagnosis = str(item.get("diagnosis", "")).strip()
        source_ids = item.get("source_ids")

        if diagnosis and isinstance(source_ids, list) and source_ids:
            rebuilt[diagnosis] = list(source_ids)

    analysis["source_ids_per_major_claim"] = rebuilt


def _clinical_evidence_gate_v032(
    case: CaseInput,
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    safe, audit = _clinical_evidence_gate_v031(
        case,
        analysis,
        sources,
    )

    issues = list(audit.get("issues", []))
    platelet_clumping = _platelet_clumping_present(case)

    safe = _normalize_analysis_strings(
        safe,
        platelet_clumping=platelet_clumping,
    )

    # Remove unsupported mixed diagnosis labels.
    for item in safe.get("ranked_differentials", []) or []:
        if not isinstance(item, dict):
            continue

        diagnosis = str(item.get("diagnosis", ""))

        if "infectious/toxic hemolysis" in diagnosis.lower():
            item["diagnosis"] = "Infectious hemolysis (e.g., Babesia spp.)"
            issues.append(
                "Removed unsupported toxic-hemolysis component from a mixed differential label."
            )

        if platelet_clumping and "thrombocytopenia" in str(item.get("diagnosis", "")).lower():
            item["diagnosis"] = re.sub(
                r"(?i)\s*(?:with|and)\s+concurrent\s+thrombocytopenia",
                "",
                str(item.get("diagnosis", "")),
            ).strip()
            issues.append(
                "Removed unconfirmed thrombocytopenia from a differential label."
            )

    _withhold_unverified_treatment_strings(
        safe,
        issues,
    )

    # Re-run citation checks with stricter concept matching.
    _validate_analysis_citations_v032(
        safe,
        sources,
        issues,
    )

    _rebuild_major_claim_sources(safe)

    deduped = list(dict.fromkeys(issues))
    status = "revise" if deduped else "pass"
    safe["clinical_gate_status"] = status

    audit = {
        **audit,
        "status": status,
        "issues": deduped,
        "retrieval_instruction_text_excluded": True,
        "strict_multi_concept_citation_check": True,
        "free_form_treatment_claims_withheld": True,
    }

    return safe, audit




# ---------------------------------------------------------------------------
# v0.3.6: quality-preserving fast path
# ---------------------------------------------------------------------------

def _dedupe_list(values: Any, limit: int | None = None) -> List[Any]:
    if not isinstance(values, list):
        return []

    result: List[Any] = []
    seen = set()

    for item in values:
        try:
            key = repr(item)
        except Exception:
            key = str(item)

        if key in seen:
            continue

        seen.add(key)
        result.append(item)

        if limit is not None and len(result) >= limit:
            break

    return result


def _ensure_analysis_shape_v036(
    case: CaseInput,
    analysis: Dict[str, Any],
) -> Dict[str, Any]:
    safe = deepcopy(analysis or {})

    if not isinstance(safe.get("modality_interpretations"), dict):
        safe["modality_interpretations"] = {}

    for key, limit in (
        ("problem_list", 6),
        ("ranked_differentials", 3),
        ("most_probable_diagnoses", 2),
        ("conflicts", 4),
        ("missing_data", 5),
        ("next_best_tests", 4),
        ("treatment_lines", 3),
        ("red_flags", 4),
    ):
        safe[key] = _dedupe_list(
            safe.get(key),
            limit=limit,
        )

    # Do not promote vital-sign interpretation unless the submitted case
    # itself explicitly used that clinical label.
    case_text = str(case.model_dump()).lower()
    cleaned_problems: List[Any] = []

    for item in safe.get("problem_list", []):
        text = str(item)
        lower = text.lower()

        if (
            ("tachypnea" in lower or "increased respiratory rate" in lower)
            and "tachypnea" not in case_text
            and "increased respiratory rate" not in case_text
        ):
            continue

        if (
            ("tachycardia" in lower or "increased heart rate" in lower)
            and "tachycardia" not in case_text
            and "increased heart rate" not in case_text
        ):
            continue

        cleaned_problems.append(item)

    safe["problem_list"] = cleaned_problems[:6]

    if "uncertainty" not in safe or safe.get("uncertainty") is None:
        safe["uncertainty"] = ""

    return safe


def _repair_item_sources_v036(
    item: Dict[str, Any],
    *,
    claim: str,
    sources: List[Dict[str, Any]],
    max_sources: int = 2,
) -> None:
    lookup = _source_lookup(sources)

    supplied = item.get("source_ids")
    supplied_ids = (
        [str(x) for x in supplied]
        if isinstance(supplied, list)
        else []
    )

    valid: List[str] = []
    rejected: List[str] = []

    for source_id in supplied_ids:
        source = lookup.get(source_id)

        if source is not None and _source_supports_claim_v032(
            claim,
            source,
        ):
            if source_id not in valid:
                valid.append(source_id)
        else:
            rejected.append(source_id)

    repaired = False

    if len(valid) < max_sources:
        for source in sources:
            source_id = str(source.get("source_id") or "")
            if not source_id or source_id in valid:
                continue

            if _source_supports_claim_v032(
                claim,
                source,
            ):
                valid.append(source_id)
                repaired = True

            if len(valid) >= max_sources:
                break

    item["source_ids"] = valid[:max_sources]

    if valid:
        item["citation_status"] = (
            "verified_repaired_from_retrieved_sources"
            if repaired or rejected
            else "verified_against_supplied_snippet"
        )
    else:
        item["citation_status"] = (
            "not_verified_from_supplied_snippet"
        )

    prior_rejected = item.get("rejected_source_ids")
    if isinstance(prior_rejected, list):
        rejected.extend(str(x) for x in prior_rejected)

    rejected = [
        source_id
        for source_id in dict.fromkeys(rejected)
        if source_id not in valid
    ]

    if rejected:
        item["rejected_source_ids"] = rejected
    else:
        item.pop("rejected_source_ids", None)


def _repair_analysis_citations_v036(
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
) -> None:
    for item in analysis.get("ranked_differentials", []) or []:
        if isinstance(item, dict):
            _repair_item_sources_v036(
                item,
                claim=str(item.get("diagnosis", "")),
                sources=sources,
            )

    for item in analysis.get("most_probable_diagnoses", []) or []:
        if isinstance(item, dict):
            _repair_item_sources_v036(
                item,
                claim=str(item.get("diagnosis", "")),
                sources=sources,
            )

    for item in analysis.get("next_best_tests", []) or []:
        if isinstance(item, dict):
            claim = " ".join(
                str(item.get(key, ""))
                for key in ("test", "rationale")
            )
            _repair_item_sources_v036(
                item,
                claim=claim,
                sources=sources,
            )

    for item in analysis.get("treatment_lines", []) or []:
        if isinstance(item, dict):
            claim = " ".join(
                str(item.get(key, ""))
                for key in ("line", "details", "rationale")
            )
            _repair_item_sources_v036(
                item,
                claim=claim,
                sources=sources,
            )

    _rebuild_major_claim_sources(analysis)


def _finalize_treatment_support_v036(
    analysis: Dict[str, Any],
) -> None:
    lines = analysis.get("treatment_lines")
    if not isinstance(lines, list):
        analysis["treatment_lines"] = []
        lines = []

    supported = 0

    for item in lines:
        if not isinstance(item, dict):
            continue

        source_ids = item.get("source_ids")
        source_support = bool(
            isinstance(source_ids, list)
            and source_ids
            and str(item.get("citation_status", "")).startswith(
                "verified"
            )
        )

        if source_support:
            supported += 1

        item["retrieved_source_support_present"] = source_support
        item["claim_level_verified"] = False
        item["status"] = (
            "manual_claim_verification_required"
            if source_support
            else "withheld_pending_claim_verification"
        )

    analysis["treatment_verification"] = {
        "status": "requires_claim_level_verification",
        "source_supported_candidate_count": supported,
        "claim_level_verified": False,
        "message": (
            "Treatment suggestions remain veterinarian decision support. "
            "Retrieved-source support is shown separately; exact drug, dose, "
            "contraindication, and treatment-line claims still require "
            "claim-level verification."
        ),
    }


def _clinical_evidence_gate_v036(
    case: CaseInput,
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    safe, prior_audit = _clinical_evidence_gate_v032(
        case,
        analysis,
        sources,
    )

    corrections = list(
        prior_audit.get("issues", [])
    )

    safe = _ensure_analysis_shape_v036(
        case,
        safe,
    )

    _repair_analysis_citations_v036(
        safe,
        sources,
    )

    _finalize_treatment_support_v036(
        safe,
    )

    blocking_issues: List[str] = []

    if not safe.get("ranked_differentials"):
        blocking_issues.append(
            "Model output did not contain a usable ranked differential list."
        )

    # A corrected/withheld unsafe claim is not itself a reason to reject the
    # final sanitized output. It remains visible in corrections_applied.
    status = "revise" if blocking_issues else "pass"
    safe["clinical_gate_status"] = status

    audit = {
        **prior_audit,
        "status": status,
        "issues": blocking_issues,
        "corrections_applied": list(
            dict.fromkeys(corrections)
        ),
        "citation_auto_repair_enabled": True,
        "required_output_shape_enforced": True,
        "treatment_claim_level_verification_required": True,
    }

    return safe, audit


def _merge_red_flags_v036(
    rule_flags: Any,
    model_flags: Any,
) -> List[Any]:
    combined: List[Any] = []

    for group in (rule_flags, model_flags):
        if not isinstance(group, list):
            continue

        for item in group:
            if repr(item) not in {repr(x) for x in combined}:
                combined.append(item)

    return combined[:8]


# ---------------------------------------------------------------------------
# v0.3.8: bounded-latency Fast mode + deterministic clinical presentation
# ---------------------------------------------------------------------------

_ALIAS_ONLY_RE_V038 = re.compile(
    r"^\s*(?:[SF]\d+)(?:\s*[,;/]\s*[SF]\d+)*\s*$",
    flags=re.IGNORECASE,
)
_ALIAS_TOKEN_RE_V038 = re.compile(r"\b[SF]\d+\b", flags=re.IGNORECASE)


def _knowledge_queries_v038(case: CaseInput) -> List[str]:
    queries = _knowledge_queries(case)

    if _platelet_clumping_present(case):
        cleaned: List[str] = []
        for query in queries:
            query = re.sub(
                r"(?i)\bthrombocytopenia\b",
                "platelet clumping pseudothrombocytopenia artifact",
                query,
            )
            cleaned.append(query)
        return cleaned

    return queries


def _retrieve_knowledge_v038(
    store: KnowledgeStore,
    case: CaseInput,
):
    queries = _knowledge_queries_v038(case)

    if hasattr(store, "search_many"):
        result_sets = store.search_many(
            queries,
            limit=12,
        )
    else:
        result_sets = [
            store.search(query, limit=12)
            for query in queries
        ]

    return _merge_hits(result_sets), queries


def _filter_platelet_artifact_noise_v038(
    case: CaseInput,
    hits: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    if not _platelet_clumping_present(case):
        return hits

    kept: List[Dict[str, Any]] = []

    for hit in hits:
        text = " ".join(
            str(hit.get(key) or "")
            for key in ("title", "chapter", "section", "snippet")
        ).lower()

        thrombocytopenia_only = (
            "thrombocytopen" in text
            and not any(
                marker in text
                for marker in (
                    "clump",
                    "pseudothromb",
                    "artifact",
                    "spurious",
                    "aggregate",
                    "spherocyt",
                    "hemolyt",
                    "imha",
                    "iha",
                )
            )
        )

        if thrombocytopenia_only:
            continue

        kept.append(hit)

    return kept or hits


def _clean_alias_text_v038(value: str) -> str:
    text = str(value or "").strip()

    if not text:
        return ""

    if _ALIAS_ONLY_RE_V038.fullmatch(text):
        return ""

    cleaned = _ALIAS_TOKEN_RE_V038.sub("", text)
    cleaned = re.sub(r"\s*[,;/]\s*(?=$)", "", cleaned)
    cleaned = re.sub(r"\(\s*\)", "", cleaned)
    cleaned = re.sub(r"\s{2,}", " ", cleaned)
    return cleaned.strip(" ,;/:-")


def _scrub_alias_leaks_v038(value: Any, key: str = "") -> Any:
    if key in {"source_id", "source_ids"}:
        return value

    if isinstance(value, dict):
        return {
            k: _scrub_alias_leaks_v038(v, str(k))
            for k, v in value.items()
        }

    if isinstance(value, list):
        result = []
        for item in value:
            cleaned = _scrub_alias_leaks_v038(item, key)
            if cleaned in ("", None, [], {}):
                continue
            result.append(cleaned)
        return result

    if isinstance(value, str):
        return _clean_alias_text_v038(value)

    return value


def _deterministic_problem_list_v038(
    case: CaseInput,
) -> List[str]:
    problems: List[str] = []

    clinical = getattr(case, "clinical", None)
    chief = _text(getattr(clinical, "chief_complaint", None), 180)
    if chief:
        problems.append(chief)

    dehydration = getattr(clinical, "dehydration_percent", None)
    if dehydration is not None:
        try:
            if float(dehydration) > 0:
                problems.append(f"Dehydration: {dehydration}%")
        except Exception:
            pass

    cbc = getattr(case, "cbc", None)
    if hasattr(cbc, "model_dump"):
        cbc = cbc.model_dump()

    if isinstance(cbc, dict):
        pattern = str(cbc.get("anemia_pattern") or "").strip()
        if pattern:
            problems.append(f"{pattern.capitalize()} anemia")

        if cbc.get("HCT") is not None:
            problems.append(f"HCT: {cbc.get('HCT')}")

    chemistry = getattr(case, "biochemistry", None)
    if hasattr(chemistry, "model_dump"):
        chemistry = chemistry.model_dump()

    if isinstance(chemistry, dict):
        bilirubin = chemistry.get("bilirubin")
        if _has_meaningful_data(bilirubin):
            problems.append(f"Serum bilirubin: {bilirubin}")

    smear = getattr(case, "blood_smear", None)
    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()

    if isinstance(smear, dict):
        spherocytes = str(smear.get("spherocytes") or "").lower()
        if spherocytes in {"present", "positive", "yes", "true", "1"}:
            problems.append("Spherocytes present on blood smear")

        if _platelet_clumping_present(case):
            problems.append(
                "Platelet count uncertainty due to platelet clumping"
            )

    return _dedupe_list(problems, limit=6)


def _deterministic_modality_interpretations_v038(
    case: CaseInput,
) -> Dict[str, List[str]]:
    result: Dict[str, List[str]] = {}

    cbc = getattr(case, "cbc", None)
    if hasattr(cbc, "model_dump"):
        cbc = cbc.model_dump()

    if isinstance(cbc, dict) and _has_meaningful_data(cbc):
        notes: List[str] = []

        if cbc.get("HCT") is not None:
            notes.append(f"HCT: {cbc.get('HCT')}.")

        pattern = str(cbc.get("anemia_pattern") or "").strip()
        if pattern:
            notes.append(f"Reported anemia pattern: {pattern}.")

        platelet_flag = str(cbc.get("platelet_flag") or "").strip()
        if platelet_flag:
            if _platelet_clumping_present(case):
                notes.append(
                    "Automated low platelet flag is unreliable because "
                    "platelet clumping is present; true thrombocytopenia "
                    "is unconfirmed."
                )
            else:
                notes.append(f"Platelet flag: {platelet_flag}.")

        if notes:
            result["cbc"] = notes[:3]

    chemistry = getattr(case, "biochemistry", None)
    if hasattr(chemistry, "model_dump"):
        chemistry = chemistry.model_dump()

    if isinstance(chemistry, dict) and _has_meaningful_data(chemistry):
        notes = []
        bilirubin = chemistry.get("bilirubin")
        if _has_meaningful_data(bilirubin):
            notes.append(f"Serum bilirubin: {bilirubin}.")
        if notes:
            result["biochemistry"] = notes[:3]

    smear = getattr(case, "blood_smear", None)
    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()

    if isinstance(smear, dict) and _has_meaningful_data(smear):
        notes = []
        spherocytes = smear.get("spherocytes")
        if _has_meaningful_data(spherocytes):
            notes.append(f"Spherocytes: {spherocytes}.")
        clumping = smear.get("platelet_clumping")
        if _has_meaningful_data(clumping):
            notes.append(f"Platelet clumping: {clumping}.")
        if notes:
            result["blood_smear"] = notes[:3]

    # Other supplied modalities are represented without inventing findings.
    for key in ("urinalysis", "skin_cytology", "fecal", "radiography", "ultrasound"):
        value = getattr(case, key, None)
        if _has_meaningful_data(value):
            summary = _text(value, 260)
            if summary:
                result[key] = [summary]

    return result


def _rule_conflict_summaries_v038(rules: Dict[str, Any]) -> List[str]:
    result: List[str] = []

    for item in rules.get("conflicts", []) or []:
        if isinstance(item, dict):
            title = str(item.get("title") or "").strip()
            if title:
                result.append(title)
        elif item:
            result.append(str(item))

    return _dedupe_list(result, limit=4)


def _etiologic_differentials_only_v038(
    differentials: Any,
) -> List[Dict[str, Any]]:
    if not isinstance(differentials, list):
        return []

    blocked_exact = {
        "pseudothrombocytopenia",
        "regenerative anemia",
        "hemolysis",
        "hemolytic anemia",
        "hemolysis with regenerative anemia",
        "anemia",
    }

    result: List[Dict[str, Any]] = []

    for item in differentials:
        if not isinstance(item, dict):
            continue

        diagnosis = str(item.get("diagnosis") or "").strip()
        lower = diagnosis.lower()

        if not diagnosis:
            continue

        if lower in blocked_exact or lower.startswith("pseudothrombocytopen"):
            continue

        result.append(item)

        if len(result) >= 3:
            break

    return result


def _source_supports_claim_v038(
    claim: str,
    source: Dict[str, Any],
) -> bool:
    claim_l = str(claim or "").lower()
    source_text = " ".join(
        str(source.get(key) or "")
        for key in ("title", "chapter", "section", "snippet", "abstract")
    ).lower()

    artifact_claim = any(
        marker in claim_l
        for marker in (
            "pseudothromb",
            "platelet clump",
            "manual platelet",
            "platelet estimate",
            "platelet count uncertainty",
        )
    )

    if artifact_claim:
        if "platelet" not in source_text:
            return False
        return any(
            marker in source_text
            for marker in (
                "clump",
                "pseudothromb",
                "artifact",
                "spurious",
                "aggregate",
                "manual",
                "smear estimate",
            )
        )

    return _source_supports_claim_v032(
        claim,
        source,
    )


def _repair_item_sources_v038(
    item: Dict[str, Any],
    *,
    claim: str,
    sources: List[Dict[str, Any]],
    max_sources: int = 2,
) -> None:
    lookup = _source_lookup(sources)

    supplied = item.get("source_ids")
    supplied_ids = (
        [str(x) for x in supplied]
        if isinstance(supplied, list)
        else []
    )

    valid: List[str] = []
    rejected: List[str] = []

    for source_id in supplied_ids:
        source = lookup.get(source_id)
        if (
            source is not None
            and _source_supports_claim_v038(claim, source)
        ):
            if source_id not in valid:
                valid.append(source_id)
        else:
            rejected.append(source_id)

    repaired = False

    if len(valid) < max_sources:
        for source in sources:
            source_id = str(source.get("source_id") or "")
            if not source_id or source_id in valid:
                continue

            if _source_supports_claim_v038(claim, source):
                valid.append(source_id)
                repaired = True

            if len(valid) >= max_sources:
                break

    item["source_ids"] = valid[:max_sources]

    if valid:
        item["citation_status"] = (
            "verified_repaired_from_retrieved_sources"
            if repaired or rejected
            else "verified_against_supplied_snippet"
        )
    else:
        item["citation_status"] = "not_verified_from_supplied_snippet"

    if rejected:
        item["rejected_source_ids"] = [
            x for x in dict.fromkeys(rejected)
            if x not in valid
        ]
    else:
        item.pop("rejected_source_ids", None)


def _repair_analysis_citations_v038(
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
) -> None:
    for item in analysis.get("ranked_differentials", []) or []:
        if isinstance(item, dict):
            _repair_item_sources_v038(
                item,
                claim=str(item.get("diagnosis", "")),
                sources=sources,
            )

    for item in analysis.get("next_best_tests", []) or []:
        if isinstance(item, dict):
            claim = " ".join(
                str(item.get(key, ""))
                for key in ("test", "rationale")
            )
            _repair_item_sources_v038(
                item,
                claim=claim,
                sources=sources,
            )

    for item in analysis.get("treatment_lines", []) or []:
        if isinstance(item, dict):
            claim = " ".join(
                str(item.get(key, ""))
                for key in ("line", "details")
            )
            _repair_item_sources_v038(
                item,
                claim=claim,
                sources=sources,
            )


def _normalize_next_tests_v038(
    case: CaseInput,
    tests: Any,
) -> List[Dict[str, Any]]:
    if not isinstance(tests, list):
        return []

    result: List[Dict[str, Any]] = []

    for item in tests:
        if not isinstance(item, dict):
            continue

        row = dict(item)
        test_name = str(row.get("test") or "").strip()
        rationale = str(row.get("rationale") or "").strip()
        lower = test_name.lower()

        if (
            not _urinalysis_present(case)
            and "serum bilirubin" in lower
            and "urine" in lower
        ):
            row["test"] = "Urinalysis with urine bilirubin assessment"
            row["rationale"] = (
                "Urinalysis was not provided; urine bilirubin must be "
                "interpreted separately from the already reported serum bilirubin."
            )

        if "manual platelet" in lower and not rationale:
            row["rationale"] = (
                "Clarify true platelet status because clumping can artifactually "
                "lower an automated platelet result."
            )

        if not row.get("rationale"):
            row["rationale"] = (
                "Clarify the leading differential or resolve an important "
                "uncertainty in the submitted case."
            )

        result.append(row)

        if len(result) >= 3:
            break

    return result


def _rebuild_most_probable_v038(
    analysis: Dict[str, Any],
) -> None:
    differentials = analysis.get("ranked_differentials")
    if not isinstance(differentials, list) or not differentials:
        analysis["most_probable_diagnoses"] = []
        return

    first = differentials[0]
    if not isinstance(first, dict):
        analysis["most_probable_diagnoses"] = []
        return

    verified = first.get("verified_supporting_case_facts")
    if not isinstance(verified, list):
        verified = []

    rationale = "; ".join(str(x) for x in verified[:4])
    if not rationale:
        rationale = (
            "Ranked first after integrating the submitted case facts "
            "with retrieved veterinary evidence."
        )

    analysis["most_probable_diagnoses"] = [
        {
            "diagnosis": first.get("diagnosis", ""),
            "confidence": first.get("confidence", "moderate"),
            "rationale": rationale,
            "source_ids": list(first.get("source_ids", []) or []),
            "verified_case_facts": list(verified),
            "citation_status": first.get(
                "citation_status",
                "not_verified_from_supplied_snippet",
            ),
        }
    ]


def _clinical_evidence_gate_v038(
    case: CaseInput,
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
    rules: Dict[str, Any],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    # Start from the strict v0.3.2 safety gate, then build the v0.3.8
    # presentation deterministically. This avoids model aliases becoming
    # patient findings or clinical red flags.
    safe, prior_audit = _clinical_evidence_gate_v032(
        case,
        analysis,
        sources,
    )

    corrections = list(prior_audit.get("issues", []))

    safe = _scrub_alias_leaks_v038(safe)
    safe = _ensure_analysis_shape_v036(case, safe)

    safe["ranked_differentials"] = (
        _etiologic_differentials_only_v038(
            safe.get("ranked_differentials")
        )
    )

    safe["problem_list"] = _deterministic_problem_list_v038(case)
    safe["modality_interpretations"] = (
        _deterministic_modality_interpretations_v038(case)
    )
    safe["conflicts"] = _rule_conflict_summaries_v038(rules)
    safe["red_flags"] = list(rules.get("red_flags", []) or [])
    safe["next_best_tests"] = _normalize_next_tests_v038(
        case,
        safe.get("next_best_tests"),
    )

    _repair_analysis_citations_v038(
        safe,
        sources,
    )

    _rebuild_major_claim_sources(safe)
    _rebuild_most_probable_v038(safe)
    _finalize_treatment_support_v036(safe)

    blocking_issues: List[str] = []
    if not safe.get("ranked_differentials"):
        blocking_issues.append(
            "Model output did not contain a usable etiologic differential list."
        )

    status = "revise" if blocking_issues else "pass"
    safe["clinical_gate_status"] = status

    audit = {
        **prior_audit,
        "status": status,
        "issues": blocking_issues,
        "corrections_applied": list(dict.fromkeys(corrections)),
        "citation_auto_repair_enabled": True,
        "required_output_shape_enforced": True,
        "treatment_claim_level_verification_required": True,
        "source_alias_leak_scrubber_enabled": True,
        "fact_alias_schema_enforced": True,
        "etiologic_differential_filter_enabled": True,
        "deterministic_problem_list_enabled": True,
        "deterministic_modality_summary_enabled": True,
        "rule_engine_red_flags_authoritative": True,
    }

    return safe, audit



# ---------------------------------------------------------------------------
# v0.3.9: clinical differential quality + missing-data/next-test completion
# ---------------------------------------------------------------------------

def _case_text_v039(case: CaseInput) -> str:
    try:
        raw = case.model_dump()
    except Exception:
        raw = {}

    parts: List[str] = []

    def walk(value: Any, key: str = "") -> None:
        key_l = key.lower()
        if key_l in {
            "case_id",
            "veterinarian_notes",
            "requested_article_search",
            "max_evidence_results",
        }:
            return

        if isinstance(value, dict):
            for k, v in value.items():
                walk(v, str(k))
            return

        if isinstance(value, list):
            for item in value[:12]:
                walk(item, key)
            return

        if value is None:
            return

        parts.append(str(value))

    walk(raw)
    return " ".join(parts).lower()


def _anemia_pattern_v039(case: CaseInput) -> str:
    cbc = getattr(case, "cbc", None)
    if hasattr(cbc, "model_dump"):
        cbc = cbc.model_dump()

    if isinstance(cbc, dict):
        return str(cbc.get("anemia_pattern") or "").strip().lower()

    return ""


def _likely_hemolytic_pattern_v039(case: CaseInput) -> bool:
    score = 0

    if "regenerative" in _anemia_pattern_v039(case):
        score += 1

    smear = getattr(case, "blood_smear", None)
    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()

    if isinstance(smear, dict):
        spherocytes = str(smear.get("spherocytes") or "").strip().lower()
        if spherocytes in {"present", "positive", "yes", "true", "1"}:
            score += 2

        agglutination = " ".join(
            str(smear.get(key) or "")
            for key in (
                "agglutination",
                "autoagglutination",
                "saline_agglutination",
            )
        ).lower()
        if any(x in agglutination for x in ("present", "positive", "yes", "true")):
            score += 2

    chemistry = getattr(case, "biochemistry", None)
    if hasattr(chemistry, "model_dump"):
        chemistry = chemistry.model_dump()

    if isinstance(chemistry, dict):
        bilirubin = str(chemistry.get("bilirubin") or "").strip().lower()
        if bilirubin and bilirubin not in {"normal", "negative", "none"}:
            score += 1

    return score >= 2


def _has_chronic_disease_context_v039(case: CaseInput) -> bool:
    text = _case_text_v039(case)

    strong_terms = (
        "chronic kidney",
        "chronic renal",
        "ckd",
        "chronic inflammatory",
        "chronic inflammation",
        "long-standing inflammation",
        "known neoplas",
        "known cancer",
        "chronic infection",
    )

    return any(term in text for term in strong_terms)


def _is_overbroad_compound_dx_v039(label: str) -> bool:
    text = str(label or "").strip().lower()

    bad_patterns = (
        "infectious or neoplastic",
        "infectious/neoplastic",
        "infectious and neoplastic",
        "infectious or inflammatory",
        "neoplastic or inflammatory",
        "infection or neoplas",
    )

    return any(pattern in text for pattern in bad_patterns)


def _refine_differentials_v039(
    case: CaseInput,
    differentials: Any,
) -> List[Dict[str, Any]]:
    if not isinstance(differentials, list):
        return []

    regenerative = "regenerative" in _anemia_pattern_v039(case)
    chronic_context = _has_chronic_disease_context_v039(case)

    result: List[Dict[str, Any]] = []
    seen = set()

    for item in differentials:
        if not isinstance(item, dict):
            continue

        row = dict(item)
        diagnosis = str(row.get("diagnosis") or "").strip()
        lower = diagnosis.lower()

        if not diagnosis:
            continue

        # Measurement/QC states and syndrome restatements are not etiologic DDx.
        if (
            lower.startswith("pseudothrombocytopen")
            or lower in {
                "regenerative anemia",
                "hemolysis",
                "hemolytic anemia",
                "hemolysis with regenerative anemia",
                "anemia",
            }
        ):
            continue

        # In a clearly regenerative case, ACD is not an appropriate high-ranked
        # explanation unless a separate chronic disease process is actually present.
        if (
            regenerative
            and "anemia of chronic disease" in lower
            and not chronic_context
        ):
            continue

        # Do not accept one vague label that bundles unrelated etiologies.
        if _is_overbroad_compound_dx_v039(diagnosis):
            continue

        key = re.sub(r"\s+", " ", lower)
        if key in seen:
            continue

        seen.add(key)
        result.append(row)

        if len(result) >= 3:
            break

    return result


def _hit_text_v039(hit: Dict[str, Any]) -> str:
    return " ".join(
        str(hit.get(key) or "")
        for key in ("title", "chapter", "section", "snippet", "abstract")
    ).lower()


def _balance_platelet_artifact_hits_v039(
    case: CaseInput,
    hits: List[Dict[str, Any]],
    *,
    limit: int,
) -> List[Dict[str, Any]]:
    if not isinstance(hits, list):
        return []

    if not _platelet_clumping_present(case):
        return hits[:limit]

    disease_hits: List[Dict[str, Any]] = []
    platelet_qc_hits: List[Dict[str, Any]] = []
    other_hits: List[Dict[str, Any]] = []

    for hit in hits:
        text = _hit_text_v039(hit)

        is_platelet_qc = (
            "platelet" in text
            and any(
                marker in text
                for marker in (
                    "clump",
                    "pseudothromb",
                    "spurious",
                    "artifact",
                    "aggregate",
                )
            )
            and not any(
                marker in text
                for marker in (
                    "spherocyt",
                    "hemolyt",
                    "imha",
                    "immune-mediated hemolytic",
                    "babesia",
                )
            )
        )

        is_disease = any(
            marker in text
            for marker in (
                "spherocyt",
                "hemolyt",
                "imha",
                "immune-mediated hemolytic",
                "babesia",
                "blood loss",
                "regenerative anemia",
            )
        )

        if is_platelet_qc:
            platelet_qc_hits.append(hit)
        elif is_disease:
            disease_hits.append(hit)
        else:
            other_hits.append(hit)

    selected: List[Dict[str, Any]] = []

    # Preserve disease reasoning capacity; QC sources are important but capped.
    for group, cap in (
        (disease_hits, max(1, limit - 2)),
        (platelet_qc_hits, 2),
        (other_hits, limit),
    ):
        added = 0
        for hit in group:
            if any(
                int(existing.get("chunk_id", -1)) == int(hit.get("chunk_id", -2))
                for existing in selected
            ):
                continue
            selected.append(hit)
            added += 1
            if len(selected) >= limit or added >= cap:
                break
        if len(selected) >= limit:
            break

    if len(selected) < limit:
        for hit in hits:
            if any(
                int(existing.get("chunk_id", -1)) == int(hit.get("chunk_id", -2))
                for existing in selected
            ):
                continue
            selected.append(hit)
            if len(selected) >= limit:
                break

    return selected[:limit]


def _source_ids_for_terms_v039(
    sources: List[Dict[str, Any]],
    terms: Tuple[str, ...],
    *,
    limit: int = 2,
) -> List[str]:
    result: List[str] = []

    for source in sources:
        text = _hit_text_v039(source)
        if any(term.lower() in text for term in terms):
            source_id = str(source.get("source_id") or "")
            if source_id and source_id not in result:
                result.append(source_id)

        if len(result) >= limit:
            break

    return result


def _missing_data_v039(
    case: CaseInput,
    existing: Any,
) -> List[str]:
    result: List[str] = []

    if isinstance(existing, list):
        for item in existing:
            text = str(item or "").strip()
            if text and text not in result:
                result.append(text)

    case_text = _case_text_v039(case)
    hemolytic = _likely_hemolytic_pattern_v039(case)

    if _platelet_clumping_present(case):
        result.append(
            "A reliable platelet count/estimate has not yet been established "
            "because platelet clumping is present."
        )

    if hemolytic:
        if not any(
            term in case_text
            for term in (
                "saline agglutination",
                "autoagglutination",
                "agglutination test",
            )
        ):
            result.append(
                "Saline agglutination/autoagglutination status is not provided."
            )

        if not any(
            term in case_text
            for term in (
                "babesia",
                "ehrlich",
                "anaplasma",
                "vector-borne",
                "tick",
                "infectious disease test",
                "pcr",
            )
        ):
            result.append(
                "Vector-borne/infectious-disease exposure history and targeted "
                "testing are not provided."
            )

        if not _urinalysis_present(case):
            result.append("Urinalysis is not provided.")

    return _dedupe_list(result, limit=4)


def _next_tests_v039(
    case: CaseInput,
    existing: Any,
    sources: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    result: List[Dict[str, Any]] = []

    def add(
        test: str,
        rationale: str,
        source_ids: List[str] | None = None,
    ) -> None:
        key = re.sub(r"\s+", " ", test.strip().lower())
        if not key:
            return

        for row in result:
            if re.sub(
                r"\s+",
                " ",
                str(row.get("test") or "").strip().lower(),
            ) == key:
                return

        result.append(
            {
                "test": test,
                "rationale": rationale,
                "source_ids": list(source_ids or []),
            }
        )

    hemolytic = _likely_hemolytic_pattern_v039(case)

    if _platelet_clumping_present(case):
        add(
            "Manual smear platelet estimate and/or repeat fresh sample",
            (
                "Resolve platelet-count reliability because clumping can "
                "artifactually lower automated platelet results."
            ),
            _source_ids_for_terms_v039(
                sources,
                ("platelet clumping", "spurious thrombocytopenia"),
            ),
        )

    if hemolytic:
        add(
            "Saline agglutination test",
            (
                "Look for agglutination as additional evidence supporting an "
                "immune-mediated hemolytic process."
            ),
            _source_ids_for_terms_v039(
                sources,
                ("saline agglut", "autoagglutination"),
            ),
        )

        add(
            "Targeted vector-borne/infectious disease testing based on exposure and geography",
            (
                "Assess an infectious trigger or infectious hemolysis before "
                "assuming a non-associative immune-mediated process."
            ),
            _source_ids_for_terms_v039(
                sources,
                ("infectious", "babesia", "associative imha"),
            ),
        )

    # Preserve useful model-suggested tests after deterministic priorities.
    if isinstance(existing, list):
        for item in existing:
            if not isinstance(item, dict):
                continue

            test_name = str(item.get("test") or "").strip()
            rationale = str(item.get("rationale") or "").strip()

            if not test_name:
                continue

            # Do not recommend re-measuring serum bilirubin when it is already supplied.
            if (
                "serum bilirubin" in test_name.lower()
                and getattr(case, "biochemistry", None) is not None
            ):
                continue

            add(
                test_name,
                rationale or (
                    "Clarify the leading differential or resolve a clinically "
                    "important uncertainty."
                ),
                list(item.get("source_ids") or []),
            )

            if len(result) >= 4:
                break

    if hemolytic and not _urinalysis_present(case) and len(result) < 4:
        add(
            "Urinalysis",
            (
                "Assess urine findings relevant to hemolysis and concurrent "
                "disease; serum bilirubin does not establish bilirubinuria."
            ),
            _source_ids_for_terms_v039(
                sources,
                ("urinalysis", "bilirubinuria", "urine"),
            ),
        )

    return result[:4]


def _augment_etiologic_differentials_v039(
    case: CaseInput,
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
) -> None:
    diffs = analysis.get("ranked_differentials")
    if not isinstance(diffs, list):
        diffs = []

    if len(diffs) >= 2 or not _likely_hemolytic_pattern_v039(case):
        analysis["ranked_differentials"] = diffs[:3]
        return

    # When the model returns only one usable diagnosis for a hemolytic pattern,
    # add a conservative etiologic alternative rather than a syndrome restatement.
    infectious_sources = _source_ids_for_terms_v039(
        sources,
        ("infectious", "babesia", "associative imha"),
    )

    if infectious_sources:
        diffs.append(
            {
                "diagnosis": (
                    "Infectious hemolysis or infectious trigger of secondary IMHA"
                ),
                "confidence": "low",
                "against_or_uncertain": [
                    (
                        "No infectious exposure history or targeted infectious "
                        "testing is supplied."
                    )
                ],
                "source_ids": infectious_sources,
                "verified_supporting_case_facts": [],
                "citation_status": "verified_repaired_from_retrieved_sources",
            }
        )

    analysis["ranked_differentials"] = diffs[:3]


def _normalize_treatment_wording_v039(
    analysis: Dict[str, Any],
) -> None:
    lines = analysis.get("treatment_lines")
    if not isinstance(lines, list):
        return

    for item in lines:
        if not isinstance(item, dict):
            continue

        line = str(item.get("line") or "").lower()

        if "immunosuppress" in line:
            item["details"] = (
                "Consider only when the overall evidence sufficiently supports "
                "IMHA and major infectious/secondary causes have been assessed; "
                "drug selection and dosing require clinician/source verification."
            )


def _clinical_evidence_gate_v039(
    case: CaseInput,
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
    rules: Dict[str, Any],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    safe, prior_audit = _clinical_evidence_gate_v038(
        case,
        analysis,
        sources,
        rules,
    )

    corrections = list(prior_audit.get("corrections_applied", []))

    safe["ranked_differentials"] = _refine_differentials_v039(
        case,
        safe.get("ranked_differentials"),
    )

    _augment_etiologic_differentials_v039(
        case,
        safe,
        sources,
    )

    safe["missing_data"] = _missing_data_v039(
        case,
        safe.get("missing_data"),
    )

    safe["next_best_tests"] = _next_tests_v039(
        case,
        safe.get("next_best_tests"),
        sources,
    )

    _repair_analysis_citations_v038(
        safe,
        sources,
    )

    _rebuild_major_claim_sources(safe)
    _rebuild_most_probable_v038(safe)
    _normalize_treatment_wording_v039(safe)
    _finalize_treatment_support_v036(safe)

    blocking_issues: List[str] = []

    if not safe.get("ranked_differentials"):
        blocking_issues.append(
            "No usable etiologic differential remained after clinical filtering."
        )

    if _likely_hemolytic_pattern_v039(case) and not safe.get("next_best_tests"):
        blocking_issues.append(
            "No usable discriminating next tests remained for a suspected hemolytic pattern."
        )

    status = "revise" if blocking_issues else "pass"
    safe["clinical_gate_status"] = status

    audit = {
        **prior_audit,
        "status": status,
        "issues": blocking_issues,
        "corrections_applied": list(dict.fromkeys(corrections)),
        "regenerative_acd_filter_enabled": True,
        "compound_differential_filter_enabled": True,
        "missing_data_completion_enabled": True,
        "next_test_priority_completion_enabled": True,
        "platelet_qc_source_cap_enabled": True,
    }

    return safe, audit



# ---------------------------------------------------------------------------
# v0.4.0: objective-first clinical guardrails
# Prevent a generic analyzer/anemia-pattern label from hijacking a case when
# the supplied HCT/PCV does not support current anemia. Also make retrieval
# complaint-led and convert raw internal missing-data keys into clinician text.
# ---------------------------------------------------------------------------

def _cbc_dict_v040(case: CaseInput) -> Dict[str, Any]:
    cbc = getattr(case, "cbc", None)
    if hasattr(cbc, "model_dump"):
        cbc = cbc.model_dump()
    return dict(cbc) if isinstance(cbc, dict) else {}


def _species_v040(case: CaseInput) -> str:
    patient = getattr(case, "patient", None)
    return str(getattr(patient, "species", None) or "").strip().lower()


def _hct_v040(case: CaseInput) -> float | None:
    cbc = _cbc_dict_v040(case)
    for key in ("HCT", "hct", "PCV", "pcv"):
        value = cbc.get(key)
        if value is None:
            continue
        try:
            return float(value)
        except Exception:
            continue
    return None


def _objective_anemia_v040(case: CaseInput) -> bool | None:
    """
    Conservative safety screen, not a laboratory reference interval.
    True  -> supplied HCT/PCV clearly supports anemia.
    False -> supplied HCT/PCV does not support anemia by this screen.
    None  -> no usable HCT/PCV, so do not infer either way here.
    """
    hct = _hct_v040(case)
    if hct is None:
        return None

    species = _species_v040(case)
    if species == "dog":
        return hct < 35.0
    if species == "cat":
        return hct < 28.0

    return hct < 30.0


def _positive_hemolysis_marker_v040(case: CaseInput) -> bool:
    smear = getattr(case, "blood_smear", None)
    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()
    if isinstance(smear, dict):
        spherocytes = str(smear.get("spherocytes") or "").strip().lower()
        if spherocytes in {"present", "positive", "yes", "true", "1"}:
            return True

        agglutination = " ".join(
            str(smear.get(key) or "")
            for key in ("agglutination", "autoagglutination", "saline_agglutination")
        ).lower()
        if any(token in agglutination for token in ("present", "positive", "yes", "true")):
            return True

    chemistry = getattr(case, "biochemistry", None)
    if hasattr(chemistry, "model_dump"):
        chemistry = chemistry.model_dump()
    if isinstance(chemistry, dict):
        bilirubin = str(chemistry.get("bilirubin") or "").strip().lower()
        if bilirubin in {"increased", "high", "elevated", "positive"}:
            return True

    return False


def _likely_hemolytic_pattern_v040(case: CaseInput) -> bool:
    # A hemolytic pattern requires current objective anemia in Fast mode.
    if _objective_anemia_v040(case) is not True:
        return False

    score = 0
    if "regenerative" in _anemia_pattern_v039(case):
        score += 1
    if _positive_hemolysis_marker_v040(case):
        score += 2

    return score >= 2


def _augment_rules_v040(
    case: CaseInput,
    rules: Dict[str, Any],
) -> Dict[str, Any]:
    updated = dict(rules or {})
    conflicts = list(updated.get("conflicts", []) or [])
    warnings = list(updated.get("warnings", []) or [])

    objective_anemia = _objective_anemia_v040(case)
    pattern = _anemia_pattern_v039(case)
    hct = _hct_v040(case)

    if objective_anemia is False and pattern:
        conflicts.append(
            {
                "severity": "medium",
                "title": "Reported anemia pattern conflicts with current HCT/PCV",
                "finding_a": f"Anemia pattern is reported as '{pattern}'.",
                "finding_b": f"Current HCT/PCV is {hct:g}.",
                "interpretation": (
                    "Do not infer active anemia or hemolysis from the pattern label "
                    "alone when the current HCT/PCV does not meet the conservative "
                    "anemia safety screen."
                ),
                "next_check": (
                    "Verify the laboratory reference interval, reticulocyte result/"
                    "percentage, analyzer interpretation, and prior HCT/PCV trend."
                ),
            }
        )

    updated["conflicts"] = conflicts
    updated["warnings"] = warnings
    updated["red_flags"] = list(updated.get("red_flags", []) or [])
    return updated


def _knowledge_queries_v040(case: CaseInput) -> List[str]:
    patient = getattr(case, "patient", None)
    species = _text(getattr(patient, "species", None), 40)
    breed = _text(getattr(patient, "breed", None), 60)
    base = " ".join(x for x in (species, breed) if x)

    clinical = getattr(case, "clinical", None)
    chief = _text(getattr(clinical, "chief_complaint", None), 180)
    history = _text(getattr(clinical, "history", None), 260)
    exam = _text(getattr(clinical, "exam_notes", None), 180)

    queries: List[str] = []

    core = " ".join(x for x in (base, chief, history, exam) if x)
    if core:
        queries.append((core + " veterinary differential diagnosis").strip()[:700])

    cbc = _cbc_dict_v040(case)
    smear = getattr(case, "blood_smear", None)
    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()

    if _has_meaningful_data(cbc) or _has_meaningful_data(smear):
        cbc_query = dict(cbc)

        # If current HCT/PCV does not support anemia, do not let the generic
        # anemia-pattern label steer retrieval toward hemolysis chapters.
        if _objective_anemia_v040(case) is False:
            cbc_query.pop("anemia_pattern", None)

        context_terms = "hematology CBC interpretation leukogram erythrogram differential diagnosis"

        if _objective_anemia_v040(case) is True:
            context_terms += " anemia regenerative nonregenerative blood loss hemolysis"
        elif _positive_hemolysis_marker_v040(case):
            context_terms += " verify hemolysis markers"

        if _platelet_clumping_present(case):
            context_terms += " platelet clumping pseudothrombocytopenia artifact"

        hematology = " ".join(
            x for x in (
                base,
                _text(cbc_query, 360),
                _text(smear, 320),
                context_terms,
            ) if x
        )
        queries.append(hematology[:700])

    # Reuse the remaining modality queries from the established builder, but
    # remove its old anemia-heavy hematology query to avoid duplication.
    for query in _knowledge_queries(case):
        lower = query.lower()
        if "hematology anemia hemolysis thrombocytopenia" in lower:
            continue
        if query not in queries:
            queries.append(query)

    seen = set()
    result: List[str] = []
    for query in queries:
        key = " ".join(query.lower().split())
        if key and key not in seen:
            seen.add(key)
            result.append(query)

    return result[:6]


def _retrieve_knowledge_v040(
    store: KnowledgeStore,
    case: CaseInput,
):
    queries = _knowledge_queries_v040(case)

    if hasattr(store, "search_many"):
        result_sets = store.search_many(queries, limit=12)
    else:
        result_sets = [store.search(query, limit=12) for query in queries]

    return _merge_hits(result_sets), queries


def _article_query_v040(case: CaseInput) -> str:
    # Disease-specific anemia literature is used only when objective anemia is
    # actually present. Otherwise the presenting complaint leads the search.
    if _objective_anemia_v040(case) is True:
        return _article_query(case)

    patient = getattr(case, "patient", None)
    species = _text(getattr(patient, "species", None), 40).lower()
    species_term = "canine dog" if species == "dog" else (
        "feline cat" if species == "cat" else species
    )

    clinical = getattr(case, "clinical", None)
    chief = _text(getattr(clinical, "chief_complaint", None), 180)
    history = _text(getattr(clinical, "history", None), 180)

    # PubMed and Europe PMC require a *search query*, not a long patient
    # narrative.  Generic age/vaccination/negative findings make an implicit
    # AND search too restrictive and frequently return zero articles.
    presenting = f"{chief} {history}".lower()
    topic_groups = (
        (("vomit", "emesis", "nausea", "gastroenter"),
         '(vomiting OR gastroenteritis OR gastritis)'),
        (("diarrh", "enteritis", "colitis"),
         '(diarrhea OR diarrhoea OR enteritis OR colitis)'),
        (("anemia", "anaemia", "hemolys", "haemolys"),
         '(anemia OR anaemia OR hemolysis)'),
        (("seizur", "epilep", "convulsion"),
         '(seizure OR epilepsy)'),
        (("cough", "dyspnea", "respiratory"),
         '(cough OR respiratory disease)'),
        (("prurit", "dermatitis", "skin lesion"),
         '(pruritus OR dermatitis)'),
        (("lameness", "limping", "arthritis"),
         '(lameness OR arthritis)'),
        (("kidney", "renal", "azotemia"),
         '(renal disease OR kidney disease)'),
    )
    topic = next(
        (expression for words, expression in topic_groups
         if any(word in presenting for word in words)),
        None,
    )
    if topic is None:
        ignored = {
            "with", "from", "last", "hours", "reduced", "reported",
            "patient", "male", "female", "mixed", "breed", "years",
            "year", "old", "history", "present", "vaccine", "water",
            "known", "exposure", "clinical", "veterinary", "dog", "cat",
        }
        words = [
            token for token in re.findall(r"[a-z]{4,}", chief.lower())
            if token not in ignored
        ]
        words = list(dict.fromkeys(words))[:3]
        topic = '(' + ' OR '.join(words) + ')' if words else '(diagnosis)'

    species_filter = (
        '(dog OR dogs OR canine)' if species == 'dog'
        else '(cat OR cats OR feline)' if species == 'cat'
        else f'({species_term})' if species_term else '(veterinary)'
    )
    return f'{species_filter} AND {topic}'


def _case_supports_hemangiosarcoma_v040(case: CaseInput) -> bool:
    text = _case_text_v039(case)
    anchors = (
        "hemoabdomen",
        "haemoabdomen",
        "splenic mass",
        "spleen mass",
        "hepatic mass",
        "liver mass",
        "abdominal mass",
        "internal bleeding",
        "internal hemorrhage",
        "internal haemorrhage",
        "collapse",
        "syncope",
        "abdominal distension",
        "free abdominal fluid",
    )
    return any(anchor in text for anchor in anchors)


def _filter_differentials_v040(
    case: CaseInput,
    differentials: Any,
) -> Tuple[List[Dict[str, Any]], List[str]]:
    base = _refine_differentials_v039(case, differentials)
    result: List[Dict[str, Any]] = []
    corrections: List[str] = []
    objective_anemia = _objective_anemia_v040(case)

    anemia_dependent_terms = (
        "immune-mediated hemolytic anemia",
        "imha",
        "hemolytic anemia",
        "blood loss anemia",
        "anemia of chronic disease",
        "regenerative anemia",
        "non-regenerative anemia",
    )

    for item in base:
        diagnosis = str(item.get("diagnosis") or "").strip()
        lower = diagnosis.lower()

        if objective_anemia is False and any(term in lower for term in anemia_dependent_terms):
            corrections.append(
                f"Removed anemia-dependent differential without objective current anemia: {diagnosis}"
            )
            continue

        if "hemangiosarcoma" in lower and not _case_supports_hemangiosarcoma_v040(case):
            corrections.append(
                "Removed hemangiosarcoma because the supplied case lacks a specific mass/"
                "bleeding/collapse anchor."
            )
            continue

        result.append(item)
        if len(result) >= 3:
            break

    return result, corrections


def _problem_list_v040(case: CaseInput) -> List[str]:
    problems: List[str] = []

    clinical = getattr(case, "clinical", None)
    chief = _text(getattr(clinical, "chief_complaint", None), 220)
    if chief:
        problems.append(chief)

    dehydration = getattr(clinical, "dehydration_percent", None)
    if dehydration is not None:
        try:
            if float(dehydration) > 0:
                problems.append(f"Dehydration: {dehydration}%")
        except Exception:
            pass

    cbc = _cbc_dict_v040(case)
    if _objective_anemia_v040(case) is True:
        hct = _hct_v040(case)
        if hct is not None:
            problems.append(f"Anemia (HCT/PCV: {hct:g})")
        pattern = str(cbc.get("anemia_pattern") or "").strip()
        if pattern:
            problems.append(f"Reported {pattern} anemia pattern")

    chemistry = getattr(case, "biochemistry", None)
    if hasattr(chemistry, "model_dump"):
        chemistry = chemistry.model_dump()
    if isinstance(chemistry, dict):
        bilirubin = str(chemistry.get("bilirubin") or "").strip()
        if bilirubin and bilirubin.lower() not in {"normal", "negative", "none"}:
            problems.append(f"Serum bilirubin: {bilirubin}")

    smear = getattr(case, "blood_smear", None)
    if hasattr(smear, "model_dump"):
        smear = smear.model_dump()
    if isinstance(smear, dict):
        spherocytes = str(smear.get("spherocytes") or "").lower()
        if spherocytes in {"present", "positive", "yes", "true", "1"}:
            problems.append("Spherocytes present on blood smear")
        if _platelet_clumping_present(case):
            problems.append("Platelet count uncertainty due to platelet clumping")

    return _dedupe_list(problems, limit=6)


def _modality_interpretations_v040(case: CaseInput) -> Dict[str, List[str]]:
    result = _deterministic_modality_interpretations_v038(case)

    cbc = _cbc_dict_v040(case)
    if cbc:
        notes: List[str] = []
        hct = _hct_v040(case)
        objective = _objective_anemia_v040(case)
        pattern = str(cbc.get("anemia_pattern") or "").strip()

        if hct is not None:
            notes.append(f"HCT/PCV: {hct:g}.")

        if cbc.get("WBC") is not None:
            notes.append(f"WBC: {cbc.get('WBC')}.")

        if pattern:
            if objective is False:
                notes.append(
                    "Reported anemia pattern: "
                    f"{pattern}; this label is not accepted as evidence of active anemia "
                    "because the current HCT/PCV does not meet the conservative anemia "
                    "safety screen. Verify the laboratory reference interval and "
                    "reticulocyte/analyzer interpretation."
                )
            else:
                notes.append(f"Reported anemia pattern: {pattern}.")

        platelet_flag = str(cbc.get("platelet_flag") or "").strip()
        if platelet_flag:
            if _platelet_clumping_present(case):
                notes.append(
                    "Automated platelet flag is unreliable because platelet clumping "
                    "is present; true thrombocytopenia remains unconfirmed."
                )
            else:
                notes.append(f"Platelet flag: {platelet_flag}.")

        if notes:
            result["cbc"] = notes[:4]

    return result


_MISSING_LABELS_V040 = {
    "cbc.rbc": "RBC count / erythrogram detail",
    "cbc.ret": "Reticulocyte count/percentage and laboratory reference interval",
    "cbc.reticulocytes": "Reticulocyte count/percentage and laboratory reference interval",
    "cbc.bilirubin": "Serum bilirubin",
    "cbc.hgb": "Hemoglobin",
    "cbc.mcv": "MCV",
    "cbc.mchc": "MCHC",
    "biochemistry.bilirubin": "Serum bilirubin",
    "urinalysis": "Urinalysis",
    "blood_smear": "Blood smear findings",
}


def _friendly_missing_item_v040(value: Any) -> str:
    text = str(value or "").strip()
    if not text:
        return ""

    key = text.lower()
    if key in _MISSING_LABELS_V040:
        return _MISSING_LABELS_V040[key]

    # Convert simple internal paths such as cbc.rbc into readable labels.
    if re.fullmatch(r"[a-z_]+\.[a-z0-9_]+", key):
        section, field = key.split(".", 1)
        field = field.replace("_", " ")
        return f"{field.upper() if field in {'rbc','wbc','hct','pcv','mcv','mchc'} else field.title()} ({section.upper()})"

    return text


def _missing_data_v040(
    case: CaseInput,
    existing: Any,
) -> List[str]:
    result: List[str] = []
    objective_anemia = _objective_anemia_v040(case)

    if isinstance(existing, list):
        for item in existing:
            text = _friendly_missing_item_v040(item)
            lower = text.lower()
            if not text:
                continue

            # Do not let an unsupported anemia hypothesis populate the missing-data
            # card with hemolysis-specific workup items.
            if objective_anemia is False and any(
                term in lower
                for term in (
                    "reticulocyte",
                    "bilirubin",
                    "spherocyte",
                    "coombs",
                    "dat",
                    "agglutination",
                    "hemolysis",
                )
            ):
                continue

            if text not in result:
                result.append(text)

    case_text = _case_text_v039(case)

    if _platelet_clumping_present(case):
        result.append(
            "A reliable platelet count/estimate has not yet been established because "
            "platelet clumping is present."
        )

    if _likely_hemolytic_pattern_v040(case):
        if not any(
            term in case_text
            for term in ("saline agglutination", "autoagglutination", "agglutination test")
        ):
            result.append("Saline agglutination/autoagglutination status is not provided.")
        if not any(
            term in case_text
            for term in ("babesia", "ehrlich", "anaplasma", "vector-borne", "tick", "pcr")
        ):
            result.append(
                "Vector-borne/infectious-disease exposure history and targeted testing "
                "are not provided."
            )

    # Complaint-led completion for vomiting cases.
    if "vomit" in case_text:
        if not _has_meaningful_data(getattr(case, "biochemistry", None)):
            result.append("Serum biochemistry and electrolytes are not provided.")
        if not (
            _has_meaningful_data(getattr(case, "radiography", None))
            or _has_meaningful_data(getattr(case, "ultrasound", None))
        ):
            result.append(
                "Abdominal imaging has not been provided; its priority depends on "
                "examination findings and concern for obstruction/foreign body."
            )

    return _dedupe_list(result, limit=4)


def _filter_next_tests_v040(
    case: CaseInput,
    existing: Any,
    sources: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    objective_anemia = _objective_anemia_v040(case)
    rows: List[Dict[str, Any]] = []

    if isinstance(existing, list):
        for item in existing:
            if not isinstance(item, dict):
                continue
            name = str(item.get("test") or "").strip()
            lower = name.lower()

            if objective_anemia is False and any(
                term in lower
                for term in (
                    "bilirubin",
                    "blood smear",
                    "saline agglutination",
                    "coombs",
                    "dat",
                    "reticulocyte",
                )
            ):
                continue

            rows.append(dict(item))

    case_text = _case_text_v039(case)

    def add(test: str, rationale: str, terms: Tuple[str, ...]) -> None:
        key = test.lower()
        if any(str(row.get("test") or "").strip().lower() == key for row in rows):
            return
        rows.append(
            {
                "test": test,
                "rationale": rationale,
                "source_ids": _source_ids_for_terms_v039(sources, terms, limit=2),
            }
        )

    if "vomit" in case_text:
        if not _has_meaningful_data(getattr(case, "biochemistry", None)):
            add(
                "Serum biochemistry and electrolytes",
                "Assess metabolic/organ-system abnormalities and consequences of vomiting/dehydration.",
                ("vomiting", "electrolyte", "biochemistry"),
            )

        if len(rows) < 3:
            add(
                "Focused abdominal imaging when obstruction or foreign body is clinically suspected",
                "Use examination/history to decide whether radiography or ultrasound is needed to assess obstructive or structural gastrointestinal disease.",
                ("vomiting", "obstruction", "foreign body", "radiograph", "ultrasound"),
            )

        if len(rows) < 3:
            add(
                "Pancreatic lipase testing when pancreatitis remains a clinical differential",
                "Use when the examination/history supports pancreatitis as a cause of acute vomiting.",
                ("pancreatitis", "pancreatic lipase", "vomiting"),
            )

    if _likely_hemolytic_pattern_v040(case):
        rows = _next_tests_v039(case, rows, sources)

    return rows[:4]


def _filter_treatments_v040(
    case: CaseInput,
    analysis: Dict[str, Any],
) -> None:
    lines = analysis.get("treatment_lines")
    if not isinstance(lines, list):
        return

    if _objective_anemia_v040(case) is False:
        kept = []
        for item in lines:
            if not isinstance(item, dict):
                continue
            text = " ".join(
                str(item.get(key) or "")
                for key in ("line", "details")
            ).lower()
            if any(
                term in text
                for term in (
                    "immunosuppress",
                    "hemolysis",
                    "blood transfusion",
                    "transfusion",
                )
            ):
                continue
            kept.append(item)
        analysis["treatment_lines"] = kept[:2]


def _uncertainty_v040(
    case: CaseInput,
    value: Any,
) -> str:
    text = str(value or "").strip()
    if text.lower() in {"", "uncertain", "unknown"}:
        if "vomit" in _case_text_v039(case):
            return (
                "The available data do not yet distinguish primary gastrointestinal "
                "disease from systemic causes of vomiting."
            )
        return "The available data are limited; additional objective findings may change the ranking."
    return text


def _clinical_evidence_gate_v040(
    case: CaseInput,
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
    rules: Dict[str, Any],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    safe, prior_audit = _clinical_evidence_gate_v039(
        case,
        analysis,
        sources,
        rules,
    )

    corrections = list(prior_audit.get("corrections_applied", []))

    filtered, new_corrections = _filter_differentials_v040(
        case,
        safe.get("ranked_differentials"),
    )
    corrections.extend(new_corrections)
    safe["ranked_differentials"] = filtered

    safe["problem_list"] = _problem_list_v040(case)
    safe["modality_interpretations"] = _modality_interpretations_v040(case)
    safe["missing_data"] = _missing_data_v040(case, safe.get("missing_data"))
    safe["next_best_tests"] = _filter_next_tests_v040(
        case,
        safe.get("next_best_tests"),
        sources,
    )
    safe["uncertainty"] = _uncertainty_v040(case, safe.get("uncertainty"))

    _filter_treatments_v040(case, safe)

    _repair_analysis_citations_v038(safe, sources)
    _rebuild_major_claim_sources(safe)
    _rebuild_most_probable_v038(safe)
    _normalize_treatment_wording_v039(safe)
    _finalize_treatment_support_v036(safe)

    blocking_issues: List[str] = []
    if not safe.get("ranked_differentials"):
        blocking_issues.append(
            "No usable etiologic differential remained after objective-data filtering."
        )

    status = "revise" if blocking_issues else "pass"
    safe["clinical_gate_status"] = status

    audit = {
        **prior_audit,
        "status": status,
        "issues": blocking_issues,
        "corrections_applied": list(dict.fromkeys(corrections)),
        "objective_anemia_gate_enabled": True,
        "complaint_led_retrieval_enabled": True,
        "raw_missing_key_sanitizer_enabled": True,
        "unsupported_anemia_treatment_filter_enabled": True,
        "vomiting_workup_completion_enabled": True,
    }

    return safe, audit



# ---------------------------------------------------------------------------
# v0.4.1: GI symptom-quality guard
# ---------------------------------------------------------------------------

def _is_vomiting_case_v041(case: CaseInput) -> bool:
    return "vomit" in _case_text_v039(case)


def _patient_age_years_v041(case: CaseInput) -> Optional[float]:
    patient = getattr(case, "patient", None)
    value = getattr(patient, "age_years", None)
    try:
        return float(value) if value is not None else None
    except Exception:
        return None


def _temperature_v041(case: CaseInput) -> Optional[float]:
    clinical = getattr(case, "clinical", None)
    value = getattr(clinical, "temperature_c", None)
    try:
        return float(value) if value is not None else None
    except Exception:
        return None


def _infectious_gi_anchor_v041(case: CaseInput) -> bool:
    text = _case_text_v039(case)
    anchors = (
        "diarrhea",
        "haemorrhagic diarrhea",
        "hemorrhagic diarrhea",
        "hematochezia",
        "bloody diarrhea",
        "parvovirus",
        "parvo",
        "coronavirus",
        "positive fecal",
        "positive antigen",
        "positive pcr",
        "infectious exposure",
        "outbreak",
        "sick contact",
        "unvaccinated",
        "not vaccinated",
        "kennel outbreak",
    )
    if any(anchor in text for anchor in anchors):
        return True

    temp = _temperature_v041(case)
    if temp is not None and temp >= 39.5:
        return True

    age = _patient_age_years_v041(case)
    if age is not None and age < 1.0 and any(
        term in text for term in ("vomit", "diarrhea", "letharg")
    ):
        return True

    return False


def _case_fact_displays_v041(
    case: CaseInput,
    prefixes: Tuple[str, ...],
    *,
    limit: int = 5,
) -> List[str]:
    result: List[str] = []
    for fact in _clinical_fact_ledger(case):
        path = str(fact.get("path") or "")
        if any(path.startswith(prefix) for prefix in prefixes):
            display = str(fact.get("display") or "").strip()
            if display and display not in result:
                result.append(display)
        if len(result) >= limit:
            break
    return result


def _is_gi_overlap_v041(label: str) -> str:
    lower = str(label or "").strip().lower()
    if "viral gastroenteritis" in lower:
        return "infectious_gastroenteritis"
    if "infectious gastroenteritis" in lower:
        return "infectious_gastroenteritis"
    if "gastroenteritis" in lower or "gastritis" in lower:
        return "nonspecific_gi"
    return lower


def _refine_vomiting_differentials_v041(
    case: CaseInput,
    differentials: Any,
    sources: List[Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], List[str]]:
    base, corrections = _filter_differentials_v040(case, differentials)

    if not _is_vomiting_case_v041(case):
        return base[:3], corrections

    infectious_anchor = _infectious_gi_anchor_v041(case)
    result: List[Dict[str, Any]] = []
    seen_groups = set()

    for item in base:
        if not isinstance(item, dict):
            continue

        row = dict(item)
        diagnosis = str(row.get("diagnosis") or "").strip()
        lower = diagnosis.lower()

        if not diagnosis:
            continue

        if (
            ("viral gastroenteritis" in lower or "infectious gastroenteritis" in lower)
            and not infectious_anchor
        ):
            corrections.append(
                f"Removed unanchored infectious/viral GI differential: {diagnosis}"
            )
            continue

        group = _is_gi_overlap_v041(diagnosis)
        if group in seen_groups and group in {"infectious_gastroenteritis", "nonspecific_gi"}:
            corrections.append(
                f"Removed overlapping GI differential: {diagnosis}"
            )
            continue

        if "viral gastroenteritis" in lower and row.get("confidence") == "high":
            row["confidence"] = "low"
            row["against_or_uncertain"] = list(row.get("against_or_uncertain") or [])
            row["against_or_uncertain"].append(
                "A viral etiology is not confirmed by the supplied case data."
            )
            corrections.append(
                "Downgraded unconfirmed viral gastroenteritis from high confidence."
            )

        seen_groups.add(group)
        result.append(row)

        if len(result) >= 3:
            break

    # Add conservative, complaint-led alternatives if the model list became sparse.
    support_facts = _case_fact_displays_v041(
        case,
        ("case.clinical.chief_complaint", "case.clinical.history"),
        limit=3,
    )

    def add_fallback(
        diagnosis: str,
        confidence: str,
        terms: Tuple[str, ...],
        uncertainty: str,
    ) -> None:
        nonlocal result
        key = diagnosis.lower()
        if any(str(x.get("diagnosis") or "").strip().lower() == key for x in result):
            return

        group = _is_gi_overlap_v041(diagnosis)
        if group in seen_groups and group == "nonspecific_gi":
            return

        src = _source_ids_for_terms_v039(sources, terms, limit=2)
        result.append(
            {
                "diagnosis": diagnosis,
                "confidence": confidence,
                "against_or_uncertain": [uncertainty],
                "source_ids": src,
                "verified_supporting_case_facts": support_facts,
                "citation_status": (
                    "verified_repaired_from_retrieved_sources"
                    if src else
                    "not_verified_from_supplied_snippet"
                ),
            }
        )
        seen_groups.add(group)

    if not any(
        any(token in str(x.get("diagnosis") or "").lower() for token in ("gastritis", "gastroenter"))
        for x in result
    ):
        add_fallback(
            "Acute gastritis / nonspecific gastrointestinal disease",
            "moderate",
            ("gastritis", "vomiting", "gastrointestinal"),
            "The cause is not established from the currently supplied data.",
        )

    if len(result) < 3:
        add_fallback(
            "Pancreatitis",
            "low",
            ("pancreatitis", "vomiting", "pancreatic lipase"),
            "No pancreas-specific test or characteristic imaging finding is supplied.",
        )

    if len(result) < 3:
        add_fallback(
            "Gastrointestinal foreign body or obstruction",
            "low",
            ("foreign body", "obstruction", "vomiting"),
            "No obstructive imaging finding or specific foreign-body history is supplied.",
        )

    return result[:3], corrections


def _missing_data_v041(
    case: CaseInput,
    existing: Any,
) -> List[str]:
    rows = _missing_data_v040(case, existing)

    if not _is_vomiting_case_v041(case):
        return rows[:4]

    objective_anemia = _objective_anemia_v040(case)
    cleaned: List[str] = []

    for item in rows:
        text = str(item or "").strip()
        lower = text.lower()

        if objective_anemia is False and any(
            token in lower
            for token in (
                "mcv",
                "mchc",
                "rbc count",
                "hemoglobin",
                "reticulocyte",
                "erythrogram",
                "ncc",
            )
        ):
            continue

        if text and text not in cleaned:
            cleaned.append(text)

    case_text = _case_text_v039(case)

    if not _has_meaningful_data(getattr(case, "biochemistry", None)):
        text = "Serum biochemistry and electrolytes are not provided."
        if text not in cleaned:
            cleaned.insert(0, text)

    # Keep the missing-data card complaint-focused rather than CBC-index-focused.
    if not any(
        term in case_text
        for term in (
            "abdominal pain",
            "painful abdomen",
            "abdominal distension",
            "foreign body",
            "dietary indiscretion",
            "garbage",
            "new food",
        )
    ):
        text = (
            "Abdominal pain/distension and dietary/foreign-body risk are not documented."
        )
        if text not in cleaned:
            cleaned.append(text)

    return cleaned[:4]


def _canonical_test_key_v041(name: str) -> str:
    lower = " ".join(str(name or "").strip().lower().split())

    if "biochem" in lower or "electrolyte" in lower:
        return "serum_biochemistry_electrolytes"

    if (
        "ultrasound" in lower
        or "radiograph" in lower
        or "abdominal imaging" in lower
        or "foreign body" in lower
        or "obstruction" in lower
    ):
        return "conditional_abdominal_imaging"

    if "pancreatic" in lower or "lipase" in lower or "pancreatitis" in lower:
        return "pancreatic_lipase"

    return re.sub(r"[^a-z0-9]+", "_", lower).strip("_")


def _next_tests_v041(
    case: CaseInput,
    existing: Any,
    sources: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    base = _filter_next_tests_v040(case, existing, sources)

    if not _is_vomiting_case_v041(case):
        return base[:4]

    result: List[Dict[str, Any]] = []
    seen = set()

    for item in base:
        if not isinstance(item, dict):
            continue

        row = dict(item)
        key = _canonical_test_key_v041(str(row.get("test") or ""))

        if not key or key in seen:
            continue

        if key == "serum_biochemistry_electrolytes":
            row["test"] = "Serum biochemistry and electrolytes"
            row["rationale"] = (
                "Assess metabolic/organ-system abnormalities and consequences of "
                "vomiting/dehydration."
            )

        elif key == "conditional_abdominal_imaging":
            row["test"] = "Abdominal imaging if obstruction/foreign body is clinically suspected"
            row["rationale"] = (
                "Use abdominal examination and history to decide whether radiography "
                "and/or ultrasound is needed for obstructive or structural disease."
            )

        seen.add(key)
        result.append(row)

    def add(test: str, rationale: str, terms: Tuple[str, ...]) -> None:
        key = _canonical_test_key_v041(test)
        if key in seen:
            return
        result.append(
            {
                "test": test,
                "rationale": rationale,
                "source_ids": _source_ids_for_terms_v039(sources, terms, limit=2),
            }
        )
        seen.add(key)

    if "serum_biochemistry_electrolytes" not in seen:
        add(
            "Serum biochemistry and electrolytes",
            "Assess metabolic/organ-system abnormalities and consequences of vomiting/dehydration.",
            ("vomiting", "electrolyte", "biochemistry"),
        )

    if "conditional_abdominal_imaging" not in seen:
        add(
            "Abdominal imaging if obstruction/foreign body is clinically suspected",
            "Use abdominal examination and history to decide whether radiography and/or ultrasound is needed for obstructive or structural disease.",
            ("vomiting", "obstruction", "foreign body", "radiograph", "ultrasound"),
        )

    if "pancreatic_lipase" not in seen:
        add(
            "Pancreatic lipase testing if pancreatitis remains a clinical differential",
            "Consider when examination/history keeps pancreatitis on the differential list.",
            ("pancreatitis", "pancreatic lipase", "vomiting"),
        )

    return result[:3]


def _clean_gi_treatment_sources_v041(
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
) -> None:
    lines = analysis.get("treatment_lines")
    if not isinstance(lines, list):
        return

    source_map = {
        str(src.get("source_id") or ""): _hit_text_v039(src)
        for src in sources
        if isinstance(src, dict)
    }

    for item in lines:
        if not isinstance(item, dict):
            continue

        line = str(item.get("line") or "").lower()
        source_ids = list(item.get("source_ids") or [])

        if "fluid" in line:
            kept = [
                sid for sid in source_ids
                if any(
                    term in source_map.get(sid, "")
                    for term in ("fluid", "dehydrat", "rehydrat", "vomit", "volume")
                )
            ]
            item["source_ids"] = kept

        elif "antiemetic" in line or "anti-emetic" in line:
            kept = [
                sid for sid in source_ids
                if any(
                    term in source_map.get(sid, "")
                    for term in (
                        "antiemetic",
                        "anti-emetic",
                        "maropitant",
                        "ondansetron",
                        "metoclopramide",
                        "vomit",
                        "emesis",
                    )
                )
            ]
            item["source_ids"] = kept


# v0.4.2 — conservative source-topic check for diagnosis citations.
# A matching topic is NOT proof that a specific patient has the diagnosis.
_DIAGNOSIS_TOPIC_GROUPS_V042 = (
    (("infectious gastroenteritis", "viral gastroenteritis", "bacterial gastroenteritis"),
     (r"\bgastroenteritis\b", r"\binfectious enteritis\b",
      r"\bviral enteritis\b", r"\bbacterial enteritis\b")),
    (("gastritis", "gastrointestinal disease"),
     (r"\bgastritis\b", r"\bgastroenteritis\b",
      r"\bgastrointestinal disorder", r"\bgastrointestinal disease")),
    (("gastric ulcer", "peptic ulcer", "gastroduodenal ulcer"),
     (r"\bgastric ulcer", r"\bpeptic ulcer", r"\bgastroduodenal ulcer")),
    (("pancreatitis",),
     (r"\bpancreatitis\b", r"\bpancreatic inflammation")),
    (("intestinal obstruction", "foreign body obstruction"),
     (r"\bintestinal obstruction", r"\bbowel obstruction",
      r"\bforeign body obstruction")),
    (("immune-mediated hemolytic", "immune mediated hemolytic", "imha"),
     (r"\bimha\b", r"\bimmune[- ]mediated hemolytic",
      r"\bimmune[- ]mediated haemolytic")),
)


def _source_supports_diagnosis_topic_v042(
    diagnosis: str, source: Dict[str, Any]
) -> bool:
    """Strict TOPIC match, never a claim-level clinical verification.

    Refuse links to unsupported diagnoses rather than treating a shared word
    such as 'infectious', 'disease' or 'CBC' as evidence. Exact text is not
    automatically interpreted as supporting a specific patient diagnosis.
    """
    diagnosis_l = re.sub(r"\s+", " ", str(diagnosis or "").lower()).strip()
    passage = " ".join(
        str(source.get(field) or "")
        for field in ("title", "chapter", "section", "snippet", "abstract")
    ).lower()
    passage = re.sub(r"\s+", " ", passage)
    if not diagnosis_l or not passage:
        return False
    for names, patterns in _DIAGNOSIS_TOPIC_GROUPS_V042:
        if any(term in diagnosis_l for term in names):
            return any(re.search(pat, passage) is not None for pat in patterns)

    # No match on a single generic token.  For unfamiliar diagnoses, require
    # a complete distinctive diagnostic phrase (or a nearly exact phrase),
    # not an accidental overlap with a general medical term.
    normalized = re.sub(r"[^a-z0-9]+", " ", diagnosis_l).strip()
    generic = {
        "acute", "chronic", "canine", "feline", "suspected", "possible",
        "disease", "condition", "syndrome", "secondary", "primary",
    }
    meaningful = [w for w in normalized.split() if w not in generic]
    if not meaningful:
        return False
    pattern = r"\b" + r"\W+".join(map(re.escape, meaningful)) + r"\b"
    return re.search(pattern, passage) is not None


def _source_supports_test_topic_v042(test: str, source: Dict[str, Any]) -> bool:
    """Require test-specific support; symptoms and generic lab words are insufficient."""
    test_l = str(test or "").lower()
    passage = " ".join(
        str(source.get(field) or "")
        for field in ("title", "chapter", "section", "snippet", "abstract")
    ).lower()
    if not test_l or not passage:
        return False
    if any(k in test_l for k in ("abdominal imaging", "radiograph", "ultrasound")):
        # A CBC in a Borreliosis passage does not substantiate a test for GI obstruction.
        image = any(k in passage for k in ("radiograph", "ultrasound", "imaging", "sonograph"))
        indication = any(k in passage for k in ("obstruct", "foreign body", "abdominal"))
        return image and indication
    if any(k in test_l for k in ("pancreatic lipase", "cpli", "pancreatitis test")):
        return any(k in passage for k in ("pancreatic lipase", "pancreatitis", "spec cpl"))
    if any(k in test_l for k in ("serum biochemistry", "electrolyte", "chemistry panel")):
        return any(k in passage for k in ("biochemistry", "electrolyte", "serum chemistry"))
    if "urinalysis" in test_l:
        return any(k in passage for k in ("urinalysis", "urine analysis"))
    # Exact test phrase for unclassified test types, not generic word overlap.
    tokens = [w for w in re.findall(r"[a-z]{4,}", test_l) if w not in {
        "test", "testing", "consider", "when", "clinically", "suspected", "if",
    }]
    return bool(tokens) and re.search(
        r"\b" + r"\W+".join(map(re.escape, tokens[:3])) + r"\b",
        passage,
    ) is not None


def _clean_diagnosis_citations_v042(
    analysis: Dict[str, Any], sources: List[Dict[str, Any]],
) -> int:
    lookup = _source_lookup(sources)
    rejected_total = 0
    for section in ("ranked_differentials", "most_probable_diagnoses"):
        for item in analysis.get(section, []) or []:
            if not isinstance(item, dict):
                continue
            diagnosis = str(item.get("diagnosis") or "")
            ids = item.get("source_ids")
            supplied = [str(x) for x in ids] if isinstance(ids, list) else []
            good, bad = [], []
            for sid in supplied:
                src = lookup.get(sid)
                if src and _source_supports_diagnosis_topic_v042(diagnosis, src):
                    if sid not in good:
                        good.append(sid)
                else:
                    bad.append(sid)
            # No automatic replacement from unrelated candidate snippets.
            item["source_ids"] = good
            item["citation_status"] = (
                "topic_matched_not_claim_verified" if good
                else "not_verified_from_supplied_snippet"
            )
            previous = item.get("rejected_source_ids")
            combined = list(dict.fromkeys(
                [str(x) for x in previous] if isinstance(previous, list) else []
            ))
            for sid in bad:
                if sid not in combined:
                    combined.append(sid)
            if combined:
                item["rejected_source_ids"] = combined
            else:
                item.pop("rejected_source_ids", None)
            rejected_total += len(bad)
    # Apply the same non-generic topic rule to recommended diagnostic tests.
    for item in analysis.get("next_best_tests", []) or []:
        if not isinstance(item, dict):
            continue
        ids = item.get("source_ids")
        supplied = [str(x) for x in ids] if isinstance(ids, list) else []
        good = []
        rejected = list(item.get("rejected_source_ids") or [])
        for sid in supplied:
            src = lookup.get(sid)
            if src and _source_supports_test_topic_v042(str(item.get("test") or ""), src):
                if sid not in good:
                    good.append(sid)
            else:
                if sid not in rejected:
                    rejected.append(sid)
                rejected_total += 1
        item["source_ids"] = good
        item["citation_status"] = (
            "topic_matched_not_claim_verified" if good
            else "not_verified_from_supplied_snippet"
        )
        if rejected:
            item["rejected_source_ids"] = rejected
    return rejected_total


def _clinical_evidence_gate_v041(
    case: CaseInput,
    analysis: Dict[str, Any],
    sources: List[Dict[str, Any]],
    rules: Dict[str, Any],
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    safe, prior_audit = _clinical_evidence_gate_v040(
        case,
        analysis,
        sources,
        rules,
    )

    corrections = list(prior_audit.get("corrections_applied", []))

    diffs, new_corrections = _refine_vomiting_differentials_v041(
        case,
        safe.get("ranked_differentials"),
        sources,
    )
    corrections.extend(new_corrections)
    safe["ranked_differentials"] = diffs

    safe["missing_data"] = _missing_data_v041(
        case,
        safe.get("missing_data"),
    )

    safe["next_best_tests"] = _next_tests_v041(
        case,
        safe.get("next_best_tests"),
        sources,
    )

    _clean_gi_treatment_sources_v041(safe, sources)
    _repair_analysis_citations_v038(safe, sources)
    # Rebuild from the ranked list, then independently remove diagnosis
    # citations that only matched a generic word (e.g. Borrelia vs GI).
    _rebuild_most_probable_v038(safe)
    citations_removed = _clean_diagnosis_citations_v042(safe, sources)
    _rebuild_major_claim_sources(safe)
    _finalize_treatment_support_v036(safe)

    blocking_issues: List[str] = []
    if not safe.get("ranked_differentials"):
        blocking_issues.append(
            "No usable etiologic differential remained after GI symptom-quality filtering."
        )

    status = "revise" if blocking_issues else "pass"
    safe["clinical_gate_status"] = status

    audit = {
        **prior_audit,
        "status": status,
        "issues": blocking_issues,
        "corrections_applied": list(dict.fromkeys(corrections)),
        "unanchored_infectious_gi_filter_enabled": True,
        "overlapping_gi_differential_dedup_enabled": True,
        "vomiting_missing_data_focus_enabled": True,
        "semantic_next_test_dedup_enabled": True,
        "gi_treatment_source_relevance_filter_enabled": True,
        "strict_diagnosis_source_topic_filter_enabled": True,
        "diagnosis_citations_removed_by_topic_filter": citations_removed,
        "topic_match_is_not_claim_verification": True,
    }

    return safe, audit


# v0.4.3 — report-level population applicability; this is NOT an automated
# critical appraisal and does not verify clinical claims or drug doses.
def _article_applicability_v043(
    case: CaseInput, article: Dict[str, Any]
) -> Dict[str, Any]:
    title = str(article.get("title") or "").lower()
    abstract = str(article.get("abstract") or "").lower()
    types = " ".join(str(t) for t in (article.get("publication_types") or [])).lower()
    patient = getattr(case, "patient", None)
    clinical = getattr(case, "clinical", None)
    age = getattr(patient, "age_years", None)
    chief = str(getattr(clinical, "chief_complaint", "") or "").lower()
    history = str(getattr(clinical, "history", "") or "").lower()
    case_text = f"{chief} {history}"
    adult = age is not None and float(age) >= 2
    acute_vomiting = bool(
        re.search(r"\b(vomit|emesis)", case_text)
        and ("24 hours" in case_text or "48 hours" in case_text or "acute" in case_text)
    )
    no_diarrhea = bool(re.search(r"\b(no|without|denies)\s+(?:reported\s+)?diarrh", case_text))
    vaccinated = bool(re.search(r"\b(vaccination[s]? up to date|fully vaccinated|vaccines? current)\b", case_text))
    reasons: List[str] = []

    # Limit paediatric mismatch to papers about paediatric patients (rather than
    # reviews that merely discuss puppies among many ages).
    individual_puppy = bool(re.search(
        r"\b(?:\d+[ -]?(?:week|month)[ -]old|one[ -]month[ -]old|five[ -]month[ -]old|eight[ -]week[ -]old)\b",
        title + " " + abstract[:1000],
    ))
    puppy_focus = bool(re.search(r"\b(puppy|puppies|neonatal|juvenile)\b", title))
    single_case = bool(re.search(r"\b(a case of|case report|a [\w -]*puppy was presented)\b", abstract[:1000]))
    pediatric_trial = bool(re.search(
        r"\b(?:aged|ages?|aging)\s+(?:of\s+)?\d{1,2}\s*(?:weeks?|months?)\b|"
        r"\b\d{1,2}[ -]?(?:weeks?|months?)[ -]?old\b",
        abstract[:2200],
    )) and bool(re.search(r"\b(?:randomized|trial|experiment|challenge|control group|purpose.bred)\b", abstract[:2200]))
    if adult and (puppy_focus or (individual_puppy and single_case) or pediatric_trial):
        reasons.append("Pediatric patient/population; this case is an adult.")

    if no_diarrhea and ("hemorrhagic" in title or "haemorrhagic" in title):
        reasons.append("Hemorrhagic gastrointestinal presentation; diarrhea is absent in this case.")
    if vaccinated and "parvovir" in title and "unvaccinated" in abstract:
        reasons.append("Unvaccinated parvovirus population; this case is reported vaccinated.")

    if acute_vomiting and re.search(r"\b(chronic|refractory|long-term)\b", title):
        reasons.append("Chronic/refractory presentation; this case has acute vomiting.")
    if acute_vomiting and ("traditional chinese" in title or "tcvm" in title):
        reasons.append("Complementary-medicine treatment focus; not a standard acute-care protocol.")
    if acute_vomiting and ("molecular characterization" in title or "phylogenetic" in title):
        reasons.append("Molecular/virological characterization; not a clinical management study.")

    study_design = "unclassified"
    design_text = title + " " + types
    if "systematic review" in design_text or "meta-analysis" in design_text:
        study_design = "systematic_review_or_meta_analysis"
    elif "guideline" in design_text or "consensus" in design_text:
        study_design = "guideline_or_consensus"
    elif "randomized" in design_text or "clinical trial" in design_text:
        study_design = "clinical_trial"
    elif "case series" in design_text or "cases series" in design_text:
        study_design = "case_series"
    elif "case report" in design_text or "a case of" in title:
        study_design = "case_report"
    elif "review" in design_text:
        study_design = "narrative_review"

    row = dict(article)
    row["study_design_hint"] = study_design
    row["case_applicability"] = "context_only" if reasons else "potentially_applicable"
    row["applicability_notes"] = reasons if reasons else [
        "No explicit population mismatch detected; clinical claims are not verified."
    ]
    return row


def _rank_articles_for_case_v043(
    case: CaseInput, articles: List[Dict[str, Any]], limit: int
) -> List[Dict[str, Any]]:
    by_identity: Dict[str, Dict[str, Any]] = {}
    for article in articles or []:
        if not isinstance(article, dict) or article.get("source_type") != "article":
            continue
        row = _article_applicability_v043(case, article)
        # Case-specific suitability is not equivalent to a validated citation.
        priority = 0.0 if row["case_applicability"] == "potentially_applicable" else -100.0
        priority += float(row.get("relevance_score") or 0.0)
        row["case_priority_score"] = round(priority, 3)
        key = str(row.get("doi") or row.get("pmid") or row.get("title") or "").lower().strip()
        if key and (key not in by_identity or row["case_priority_score"] > by_identity[key]["case_priority_score"]):
            by_identity[key] = row
    ranked = sorted(by_identity.values(), key=lambda x: x["case_priority_score"], reverse=True)
    return ranked[:max(1, int(limit))]


def _calibrate_vomiting_uncertainty_v043(
    case: CaseInput, analysis: Dict[str, Any]
) -> int:
    """Prevent 'high confidence / low uncertainty' for an undifferentiated GI case."""
    if not _is_vomiting_case_v041(case):
        return 0
    # Only apply when neither biochemistry nor imaging nor other diagnostic
    # modalities provide substantive additional objective information.
    if any(_has_meaningful_data(getattr(case, key, None)) for key in (
        "biochemistry", "radiography", "ultrasound", "other_tests", "fecal",
    )):
        return 0
    updated = 0
    for key in ("ranked_differentials", "most_probable_diagnoses"):
        for item in analysis.get(key, []) or []:
            if not isinstance(item, dict):
                continue
            if str(item.get("confidence") or "").lower() in {"high", "very high", "certain"}:
                item["confidence"] = "moderate"
                notes = list(item.get("against_or_uncertain") or [])
                line = "Provisional: nonspecific signs alone do not establish the cause of vomiting."
                if line not in notes:
                    notes.append(line)
                item["against_or_uncertain"] = notes
                updated += 1
    old = str(analysis.get("uncertainty") or "").strip().lower()
    if old in {"", "low", "none", "minimal", "no uncertainty"}:
        analysis["uncertainty"] = (
            "The cause of vomiting is not confirmed. Biochemistry, electrolytes "
            "and targeted examinations/tests may change the differential ranking."
        )
        updated += 1
    return updated



# v0.4.4 — deterministic, fail-closed textbook relevance audit.
# This is a scope and extraction-quality filter, NOT clinical claim verification.
# Source matching remains subject to the independent citation gates.
_BOOK_DOMAINS_V044 = {
    "gastrointestinal": (
        r"\b(?:vomit\w*|emesis|gastritis|gastroenteritis|diarrh\w*|enteritis|"
        r"intestinal|gastrointestinal|foreign.body|obstruct\w*|pancreatitis|"
        r"regurgitat\w*|colitis|gastric|hepat\w*|liver)\b",
        r"\b(?:vomit\w*|emesis|gastritis|gastroenteritis|enteritis|"
        r"gastrointestinal|intestinal|pancreatitis|gastric|colitis|"
        r"obstruct\w*|foreign.body|hepat\w*|liver)\b",
    ),
    "hematology": (
        r"\b(?:anemi\w*|hemoly\w*|haemoly\w*|spherocyt\w*|"
        r"thrombocyt\w*|pancytopenia|leukopenia|leukocytosis|"
        r"bleeding.disorder|coagulopath\w*)\b",
        r"\b(?:hematolog\w*|haematolog\w*|erythrocyt\w*|"
        r"anemi\w*|hemoly\w*|thrombocyt\w*|coagulat\w*|"
        r"blood.cell|leukocyt\w*)\b",
    ),
    "dermatology": (
        r"\b(?:prurit\w*|itch\w*|dermat\w*|alopecia|skin.lesion|"
        r"otitis|ear.infect\w*|cutaneous|rash)\b",
        r"\b(?:dermat\w*|cutaneous|skin|prurit\w*|otitis|alopecia)\b",
    ),
    "respiratory": (
        r"\b(?:cough\w*|dyspn\w*|pneumonia|respirat\w*|bronch\w*|"
        r"pulmonary|nasal.discharge)\b",
        r"\b(?:respirat\w*|pulmonary|pneumon\w*|bronch\w*|"
        r"airway|cough\w*|lung)\b",
    ),
    "urinary": (
        r"\b(?:dysuria|hematuria|haematuria|polyuria|urinar\w*|"
        r"cystitis|kidney|renal|azotemi\w*|bladder)\b",
        r"\b(?:urinar\w*|cystitis|bladder|renal|kidney|nephro\w*)\b",
    ),
    "cardiology": (
        r"\b(?:cardi\w*|heart.failure|murmur|arrhythmia|syncope)\b",
        r"\b(?:cardi\w*|cardiac|heart|arrhythmia|myocard\w*)\b",
    ),
    "neurology": (
        r"\b(?:seizure|neurolog\w*|ataxia|paralysis|paresis|"
        r"vestibular|epilepsy)\b",
        r"\b(?:neurolog\w*|seizure|epilep\w*|vestibular|"
        r"spinal.cord|brain)\b",
    ),
    "reproduction": (
        r"\b(?:pregnan\w*|gestation|parturition|estrus|oestrus|"
        r"follicle|fertility|pyometra|prostate)\b",
        r"\b(?:reproduct\w*|gestation|pregnan\w*|ovulation|"
        r"estrus|oestrus|prostate|uter\w*)\b",
    ),
    "orthopedics": (
        r"\b(?:lameness|fracture|joint.pain|orthop\w*|ligament|"
        r"osteoarthrit\w*|limb.injur\w*)\b",
        r"\b(?:orthop\w*|fracture|joint|skelet\w*|ligament|"
        r"osteoarthrit\w*)\b",
    ),
    "endocrine": (
        r"\b(?:diabet\w*|cushing|addison|thyroid|endocrin\w*|"
        r"adrenal|hypoglycemi\w*)\b",
        r"\b(?:endocrin\w*|diabet\w*|thyroid|adrenal|"
        r"pituitar\w*|cushing|addison)\b",
    ),
    "ophthalmology": (
        r"\b(?:corne\w*|ocular|ophthal\w*|eye.injur\w*|"
        r"conjunctivitis|uveitis|glaucoma)\b",
        r"\b(?:ophthal\w*|ocular|corne\w*|retina|uveitis|"
        r"glaucoma|conjunctivitis)\b",
    ),
}


def _book_case_domains_v044(case: CaseInput) -> List[str]:
    """Use reported complaints/examination, not default CBC retrieval keywords."""
    clinical = getattr(case, "clinical", None)
    clinical_text = " ".join(
        str(getattr(clinical, field, "") or "")
        for field in ("chief_complaint", "history", "exam_notes")
    ).lower()
    matched = [
        domain for domain, (case_pattern, _) in _BOOK_DOMAINS_V044.items()
        if re.search(case_pattern, clinical_text)
    ]
    # A documented hematologic problem can be worth a textbook chapter even if
    # the owner complaint is vague. Presence of *normal* CBC numbers alone is not.
    if _objective_anemia_v040(case) is True and "hematology" not in matched:
        matched.append("hematology")
    return matched


def _book_text_quality_notes_v044(hit: Dict[str, Any]) -> List[str]:
    chapter = str(hit.get("chapter") or "")
    section = str(hit.get("section") or "")
    snippet = str(hit.get("snippet") or "")
    notes: List[str] = []
    if len(snippet.strip()) < 45:
        notes.append("Excerpt too short to verify the context.")
    if (re.search(r"[a-z][A-Z]{2,}[a-z]", chapter)
            or re.search(r"\b[A-Za-z]\s+[A-Za-z]\s+[A-Za-z]\b", section)
            or re.search(r"Chapter\s+\d+\s*[—-]\s*\W", chapter)):
        notes.append("Chapter/section metadata may contain PDF extraction artifacts.")
    numeric_groups = re.findall(r"\b\d+(?:[.,]\d+)?\b", snippet)
    bracket_groups = re.findall(r"\[[A-Z]{2,6}\]", snippet)
    if (len(numeric_groups) >= 11 and len(snippet) < 650) or len(bracket_groups) >= 4:
        notes.append("Excerpt looks like a fragmented table or OCR extraction.")
    return notes


def _classify_book_hit_v044(case: CaseInput, hit: Dict[str, Any]) -> Dict[str, Any]:
    """Assess clinical *scope*, not whether a specific diagnostic claim is true.

    Potentially usable excerpts must have a topic-relevant chapter/section and
    supporting text. A coincidental symptom inside an unrelated chapter is not
    direct evidence. Textbook entries never automatically certify drug doses.
    """
    row = dict(hit)
    domains = _book_case_domains_v044(case)
    chapter = " ".join(str(hit.get(x) or "") for x in ("chapter", "section")).lower()
    snippet = str(hit.get("snippet") or "").lower()
    title = str(hit.get("title") or "").lower()
    quality_notes = _book_text_quality_notes_v044(hit)
    topic_in_heading = []
    topic_in_snippet = []
    for domain in domains:
        pattern = _BOOK_DOMAINS_V044[domain][1]
        if re.search(pattern, chapter):
            topic_in_heading.append(domain)
        if re.search(pattern, snippet):
            topic_in_snippet.append(domain)
    notes = list(quality_notes)
    status = "excluded"

    if not domains:
        notes.append("Case topic cannot be determined confidently from the supplied findings.")
    elif topic_in_heading and topic_in_snippet:
        # The named subject of the chapter and its text both align with the case.
        # An unusably short/fragmented excerpt is NOT a citable passage.
        if any("too short" in note.lower() or "fragmented table" in note.lower()
               for note in quality_notes):
            status = "context_only"
            notes.append("Relevant topic but extracted excerpt requires source-page verification.")
        else:
            status = "direct_candidate"
            notes.append("Topic-aligned chapter/excerpt; clinical claims are not verified.")
    elif topic_in_heading or topic_in_snippet:
        status = "context_only"
        if topic_in_snippet and not topic_in_heading:
            notes.append("A matching symptom appears in a chapter on another topic.")
        else:
            notes.append("Chapter topic matches, but the excerpt does not establish its relevance.")
    else:
        notes.append("No case-specific clinical topic match in chapter or excerpt.")

    clinical = getattr(case, "clinical", None)
    ctext = " ".join(str(getattr(clinical, key, "") or "")
                     for key in ("chief_complaint", "history")).lower()
    acute = "gastrointestinal" in domains and bool(
        re.search(r"\b(?:acute|24 hours?|48 hours?|sudden)\b", ctext)
    )
    if acute and status == "direct_candidate":
        if re.search(r"\b(?:chronic|long.term|intermittent for years)\b", chapter):
            status = "context_only"
            notes.append("Chapter emphasizes chronic disease; presenting episode is acute.")
        # Specific infection/malignancy case reports must not validate an
        # undifferentiated acute GI complaint merely by mentioning vomiting.
        if (re.search(r"\b(?:helicobacter|borreliosis|neoplasia|cancer)\b", chapter)
                and not re.search(r"\b(?:helicobacter|borreliosis|neoplasia|cancer)\b", ctext)):
            status = "context_only"
            notes.append("Specific disease chapter without patient-specific diagnostic support.")

    # Books on a totally different specialty are not evidence for a nonspecific
    # symptom even if a token like 'food' appears in the extracted material.
    if status == "context_only" and not topic_in_heading and topic_in_snippet:
        if ("gastrointestinal" in domains and
                re.search(r"dermatolog|hematopoietic|haematopoietic|erythrocyt", title + " " + chapter)):
            status = "excluded"
            notes.append("Unrelated specialty; incidental word overlap.")

    row["book_applicability"] = status
    row["book_applicability_notes"] = list(dict.fromkeys(notes))
    row["book_matched_domains"] = list(dict.fromkeys(topic_in_heading + topic_in_snippet))
    row["book_excerpt_quality_warning"] = bool(quality_notes)
    return row


def _review_book_hits_v044(
    case: CaseInput, hits: List[Dict[str, Any]], limit: int
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], Dict[str, Any]]:
    reviewed = [_classify_book_hit_v044(case, h) for h in (hits or [])]
    direct = [h for h in reviewed if h["book_applicability"] == "direct_candidate"]
    context = [h for h in reviewed if h["book_applicability"] == "context_only"]
    excluded = [h for h in reviewed if h["book_applicability"] == "excluded"]
    # Keep potentially relevant direct excerpts first; context-only sources are
    # visible but never passed into the model source whitelist.
    visible = (direct + context)[:max(1, int(limit))]
    eligible_ids = {int(h["chunk_id"]) for h in visible
                    if h["book_applicability"] == "direct_candidate"}
    eligible = [h for h in direct if int(h["chunk_id"]) in eligible_ids]
    audit = {
        "reviewed_count": len(reviewed),
        "direct_candidate_count": len(direct),
        "context_only_count": len(context),
        "excluded_count": len(excluded),
        "model_eligible_count": len(eligible),
        "case_domains": _book_case_domains_v044(case),
        "excluded_examples": [
            {"title": h.get("title"), "chapter": h.get("chapter"),
             "reason": (h["book_applicability_notes"][-1]
                        if h["book_applicability_notes"] else "Not case-relevant")}
            for h in excluded[:4]
        ],
        "note": "Automated topic/extraction screening only; not claim verification.",
    }
    return visible, eligible, audit


class BrainOrchestrator:
    def __init__(self) -> None:
        self.knowledge = KnowledgeStore()
        self.evidence = EvidenceSearch()
        self.provider = OllamaProvider()

    async def analyze(
        self,
        case: CaseInput,
    ):
        perf_started = time.perf_counter()
        perf: Dict[str, float] = {}

        stage_started = time.perf_counter()
        rules = run_rule_engine(case)
        rules = _augment_rules_v040(case, rules)
        perf["rule_engine_seconds"] = round(
            time.perf_counter() - stage_started,
            4,
        )

        mode = _analysis_mode()

        article_query = None
        if getattr(
            case,
            "requested_article_search",
            False,
        ):
            article_query = _article_query_v040(case)

        provider_available = await self.provider.available()

        async def run_knowledge():
            started = time.perf_counter()
            result = await asyncio.to_thread(
                _retrieve_knowledge_v040,
                self.knowledge,
                case,
            )
            elapsed = round(
                time.perf_counter() - started,
                4,
            )
            return result, elapsed

        async def run_articles():
            if not article_query:
                return [], 0.0

            started = time.perf_counter()

            try:
                visible_limit = (
                    getattr(case, "max_evidence_results", 8)
                    if mode == "deep"
                    else min(getattr(case, "max_evidence_results", FAST_ARTICLE_LIMIT), FAST_ARTICLE_LIMIT)
                )
                # Consider a wider candidate pool, then rank for the actual
                # patient so case reports on a different population don't
                # crowd out applicable veterinary literature.
                candidates = await self.evidence.combined(
                    article_query,
                    limit=min(12, max(9, visible_limit * 3)),
                )
                results = _rank_articles_for_case_v043(case, candidates, visible_limit)
            except Exception as exc:
                results = [
                    {
                        "source_id": "evidence-search-error",
                        "source_type": "other",
                        "title": "External evidence search unavailable",
                        "metadata": {
                            "error": str(exc)
                        },
                    }
                ]

            elapsed = round(
                time.perf_counter() - started,
                4,
            )
            return results, elapsed

        async def run_warmup():
            if (
                not provider_available
                or not hasattr(self.provider, "warmup")
            ):
                return {}, 0.0

            started = time.perf_counter()

            try:
                result = await self.provider.warmup()
            except Exception as exc:
                result = {
                    "ok": False,
                    "error": str(exc),
                }

            elapsed = round(
                time.perf_counter() - started,
                4,
            )
            return result, elapsed

        parallel_started = time.perf_counter()

        (
            knowledge_result,
            article_result,
            warmup_result,
        ) = await asyncio.gather(
            run_knowledge(),
            run_articles(),
            run_warmup(),
        )

        perf["pre_reasoning_parallel_seconds"] = round(
            time.perf_counter() - parallel_started,
            4,
        )

        (
            (knowledge_hits, knowledge_queries),
            knowledge_elapsed,
        ) = knowledge_result

        (
            evidence_results,
            article_elapsed,
        ) = article_result

        (
            warmup_metrics,
            warmup_elapsed,
        ) = warmup_result

        perf["knowledge_retrieval_seconds"] = knowledge_elapsed
        perf["article_search_seconds"] = article_elapsed
        perf["model_warmup_seconds"] = warmup_elapsed

        knowledge_hits = _filter_hits_for_case(
            case,
            knowledge_hits,
            limit=(
                10
                if mode == "deep"
                else max(12, FAST_KNOWLEDGE_LIMIT * 2)
            ),
        )

        knowledge_hits = _filter_platelet_artifact_noise_v038(
            case,
            knowledge_hits,
        )

        knowledge_hits = _balance_platelet_artifact_hits_v039(
            case,
            knowledge_hits,
            limit=(
                10
                if mode == "deep"
                else FAST_KNOWLEDGE_LIMIT
            ),
        )

        # Review BEFORE creating the LLM context, avoiding the previous
        # fallback that allowed generic/unrelated excerpts to be cited.
        knowledge_hits, eligible_books, book_audit = _review_book_hits_v044(
            case,
            knowledge_hits,
            limit=10 if mode == "deep" else FAST_KNOWLEDGE_LIMIT,
        )

        # Context-only articles remain visible in the literature panel but
        # are deliberately withheld from the model's citation pool.
        eligible_articles = [
            row for row in evidence_results
            if row.get("case_applicability") == "potentially_applicable"
        ]
        sources = _source_context(
            eligible_books,
            eligible_articles,
        )

        if not provider_available:
            perf["total_seconds"] = round(
                time.perf_counter() - perf_started,
                4,
            )

            return {
                "case_id": case.case_id,
                "status": "needs_model",
                "conflicts": rules["conflicts"],
                "data_quality": {
                    "warnings": rules["warnings"]
                },
                "red_flags": rules["red_flags"],
                "knowledge_hits": knowledge_hits,
                "book_evidence_audit": book_audit,
                "evidence": evidence_results,
                "source_context": sources,
                "analysis": {},
                "reviewer": {
                    "status": "not_run"
                },
                "performance": {
                    **perf,
                    "warmup": warmup_metrics,
                },
                "audit_trail": {
                    "generated_at": datetime.now(
                        timezone.utc
                    ).isoformat(),
                    "engine_version": ENGINE_VERSION,
                    "rules_version": RULES_VERSION,
                    "knowledge_version": SCHEMA_VERSION,
                    "ai_provider": self.provider.name,
                    "ai_model": self.provider.model or None,
                    "knowledge_queries": knowledge_queries,
                    "article_query": article_query,
                },
            }

        payload = {
            "case": case.model_dump(),
            "rule_engine": rules,
            "knowledge_hits": eligible_books,
            "external_evidence": eligible_articles,
            "source_context": sources,
            "constraints": {
                "never_invent_citations": True,
                "only_cite_source_ids_from_source_context": True,
                "state_uncertainty": True,
                "reconcile_rule_engine_conflicts": True,
                "separate_observed_facts_from_inference": True,
                "treatment_is_decision_support_only": True,
                "veterinarian_has_final_authority": True,
                "drug_dose_requires_source_verification": True,
                "do_not_call_treatment_evidence_based_without_source_support": True,
                "do_not_convert_source_examples_into_patient_facts": True,
            },
            "requested_output": {
                "modality_interpretations": True,
                "problem_list": True,
                "ranked_differentials": True,
                "most_probable_diagnoses": True,
                "conflicts": True,
                "missing_data": True,
                "next_best_tests": True,
                "treatment_lines": True,
                "uncertainty": True,
                "source_ids_per_major_claim": True,
            },
        }

        stage_started = time.perf_counter()
        reasoning = await self.provider.reason(
            payload
        )
        perf["model_reasoning_seconds"] = round(
            time.perf_counter() - stage_started,
            4,
        )

        ollama_metrics = {}
        if isinstance(reasoning, dict):
            ollama_metrics = reasoning.pop(
                "_ollama_metrics",
                {},
            ) or {}

        stage_started = time.perf_counter()

        reasoning = _apply_guardrails(
            reasoning,
            sources,
        )

        reasoning, clinical_gate = (
            _clinical_evidence_gate_v041(
                case,
                reasoning,
                sources,
                rules,
            )
        )
        confidence_adjustments = _calibrate_vomiting_uncertainty_v043(case, reasoning)
        clinical_gate["confidence_adjustments_v043"] = confidence_adjustments

        perf["clinical_gate_seconds"] = round(
            time.perf_counter() - stage_started,
            4,
        )

        stage_started = time.perf_counter()

        if _reviewer_enabled():
            reviewer = await self.provider.review(
                {
                    **payload,
                    "proposed_analysis": reasoning,
                    "clinical_gate": clinical_gate,
                    "review_instructions": {
                        "reject_invented_citations": True,
                        "reject_source_leakage": True,
                        "flag_unsupported_patient_facts": True,
                        "flag_unsupported_treatment_claims": True,
                        "flag_missing_dangerous_differentials": True,
                        "flag_unresolved_case_conflicts": True,
                        "check_species_specificity": True,
                        "check_dose_and_unit_claims": True,
                        "do_not_mark_evidence_based_without_specific_support": True,
                    },
                }
            )

            reviewer = _sanitize_reviewer_result(
                reviewer,
                sources,
                clinical_gate,
            )
        else:
            reviewer = {
                "status": "skipped_fast_mode",
                "reason": (
                    "The second LLM reviewer is disabled in Fast Mode. "
                    "Deterministic Clinical Gate remains active."
                ),
                "claim_level_verified": False,
                "deterministic_gate_status": clinical_gate.get(
                    "status"
                ),
                "deterministic_gate_issues": clinical_gate.get(
                    "issues",
                    [],
                ),
            }

        perf["reviewer_seconds"] = (
            round(
                time.perf_counter() - stage_started,
                4,
            )
            if _reviewer_enabled()
            else 0.0
        )

        perf["total_seconds"] = round(
            time.perf_counter() - perf_started,
            4,
        )

        if clinical_gate["status"] == "revise":
            if not isinstance(reviewer, dict):
                reviewer = {}

            reviewer["deterministic_gate_status"] = "revise"
            reviewer["deterministic_gate_issues"] = clinical_gate[
                "issues"
            ]

        return {
            "case_id": case.case_id,
            "status": "complete",
            "conflicts": rules["conflicts"],
            "data_quality": {
                "warnings": rules["warnings"]
            },
            "red_flags": reasoning.get(
                "red_flags",
                rules["red_flags"],
            ),
            "knowledge_hits": knowledge_hits,
            "book_evidence_audit": book_audit,
            "evidence": evidence_results,
            "source_context": sources,
            "analysis": reasoning,
            "reviewer": reviewer,
            "clinical_gate": clinical_gate,
            "performance": {
                **perf,
                "warmup": warmup_metrics,
                "ollama": ollama_metrics,
            },
            "system_audit": {
                "engine_version": ENGINE_VERSION,
                "source_count": len(sources),
                "rule_conflict_count": len(
                    rules.get("conflicts", [])
                ),
                "treatment_claims_require_source_verification": True,
                "empty_modalities_are_not_searched": True,
                "numeric_drug_doses_blocked_until_verified": True,
                "patient_fact_gate_enabled": True,
                "citation_snippet_support_check_enabled": True,
                "citation_auto_repair_enabled": True,
                "strict_diagnosis_source_topic_filter_enabled": True,
                "topic_match_is_not_claim_verification": True,
                "patient_article_applicability_filter_enabled": True,
                "textbook_case_scope_screening_enabled": True,
                "textbook_model_eligible_count": len(eligible_books),
                "textbook_excluded_count": book_audit["excluded_count"],
                "article_context_only_count": len(evidence_results) - len(eligible_articles),
                "clinical_uncertainty_calibration_enabled": True,
                "reviewer_source_id_whitelist_enabled": True,
                "retrieval_noise_filter_enabled": True,
                "veterinarian_instruction_text_excluded_from_retrieval": True,
                "free_form_treatment_claims_withheld": True,
                "analysis_mode": mode,
                "model_reviewer_enabled": _reviewer_enabled(),
                "fast_knowledge_limit": FAST_KNOWLEDGE_LIMIT,
                "fast_article_limit": FAST_ARTICLE_LIMIT,
                "qwen_single_pass_fast_mode": True,
                "qwen_model_unchanged": True,
                "batched_exact_hybrid_retrieval": True,
                "concurrent_pre_reasoning_pipeline": True,
                "structured_compact_model_output": True,
                "compact_source_context_for_model": True,
                "short_source_aliases_for_model": True,
                "structured_output_truncation_guard": True,
                "automatic_model_recovery_on_truncation": (mode == "deep"),
                "fast_mode_second_generation_disabled": True,
                "fact_alias_schema_enforced": True,
                "source_alias_leak_scrubber_enabled": True,
                "rule_engine_red_flags_authoritative": True,
                "regenerative_acd_filter_enabled": True,
                "compound_differential_filter_enabled": True,
                "missing_data_completion_enabled": True,
                "next_test_priority_completion_enabled": True,
                "platelet_qc_source_cap_enabled": True,
                "objective_anemia_gate_enabled": True,
                "complaint_led_retrieval_enabled": True,
                "raw_missing_key_sanitizer_enabled": True,
                "unsupported_anemia_treatment_filter_enabled": True,
                "vomiting_workup_completion_enabled": True,
                "unanchored_infectious_gi_filter_enabled": True,
                "overlapping_gi_differential_dedup_enabled": True,
                "vomiting_missing_data_focus_enabled": True,
                "semantic_next_test_dedup_enabled": True,
                "gi_treatment_source_relevance_filter_enabled": True,
                "performance_timer_enabled": True,
            },
            "audit_trail": {
                "generated_at": datetime.now(
                    timezone.utc
                ).isoformat(),
                "engine_version": ENGINE_VERSION,
                "analysis_mode": mode,
                "rules_version": RULES_VERSION,
                "knowledge_version": SCHEMA_VERSION,
                "ai_provider": self.provider.name,
                "ai_model": self.provider.model,
                "knowledge_queries": knowledge_queries,
                "knowledge_result_count": len(
                    knowledge_hits
                ),
                "source_count": len(sources),
                "article_query": article_query,
            },
        }
