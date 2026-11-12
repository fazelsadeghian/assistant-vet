from typing import Any, Dict, List
from app.models import CaseInput

RULES_VERSION = "rules-0.1.0"

def _lower(value: Any) -> str:
    return str(value or "").strip().lower()

def run_rule_engine(case: CaseInput) -> Dict[str, Any]:
    conflicts: List[Dict[str, Any]] = []
    warnings: List[Dict[str, Any]] = []
    red_flags: List[Dict[str, Any]] = []

    cbc = case.cbc or {}
    smear = case.blood_smear or {}

    platelet_flag = _lower(cbc.get("platelet_flag"))
    clumping = _lower(smear.get("platelet_clumping"))

    if ("low" in platelet_flag or "thrombocyt" in platelet_flag) and clumping in {
        "yes", "present", "true", "marked"
    }:
        conflicts.append({
            "severity": "high",
            "title": "Possible pseudothrombocytopenia",
            "finding_a": "Automated platelet result/flag suggests thrombocytopenia.",
            "finding_b": "Platelet clumping is reported on the blood smear.",
            "interpretation": "Clumping can artifactually lower automated platelet counts.",
            "next_check": "Review smear manually and consider repeat sampling if clinically indicated."
        })

    if case.clinical and case.clinical.dehydration_percent:
        warnings.append({
            "severity": "info",
            "source": "clinical",
            "message": "Dehydration may affect concentration-dependent laboratory values.",
            "recommended_action": "Interpret laboratory results in the context of hydration status."
        })

    return {
        "version": RULES_VERSION,
        "conflicts": conflicts,
        "warnings": warnings,
        "red_flags": red_flags,
    }
