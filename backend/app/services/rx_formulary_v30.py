"""Evidence-linked, read-only clinical review queue for veterinary medications.

This is NOT an approved drug formulary. It exposes a small curated reference
catalog so clinicians can examine genuine options while reviewed protocols
are being populated. No catalog entries are accepted as medication orders,
and no patient-specific dose can be derived from a catalog entry.

Sources: MSD Veterinary Manual (antiemetics), Zoetis Cerenia US PI,
AAHA 2024 fluid guidelines. Each is a web URL for human appraisal.
"""
from __future__ import annotations

from typing import Any
import re

MSD = 'https://www.msdvetmanual.com/pharmacology/systemic-pharmacotherapeutics-of-the-digestive-system/drugs-used-to-control-or-stimulate-vomiting-in-monogastric-animals'
CERENIA = 'https://www.zoetisus.com/products/pages/cerenia/cerenia_tablets_and_injectable_marketing_package_insert.pdf'
AAHA = 'https://www.aaha.org/resources/2024-aaha-fluid-therapy-guidelines-for-dogs-and-cats/'

# Static reference notes, with NO model-supplied additions. Full dose
# parameters deliberately excluded: a human must check original source,
# formulation, route, indication and patient before approving a protocol.
_CATALOG = (
    {'id': 'maropitant_antiemetic_review', 'ingredient': 'maropitant',
     'slot': 'antiemetic', 'species': ('dog', 'cat'),
     'why_consider': 'NK1 antiemetic; approved animal-label indications differ by species, age, route and formulation.',
     'needs': ('confirm_cause_of_emesis', 'confirm_patient_age', 'confirm_formulation', 'assess_hydration'),
     'important_caution': 'Treat the underlying cause; review hepatic status, interactions and product age restrictions.',
     'source_title': 'CERENIA US prescribing information — injection and tablets',
     'source_url': CERENIA, 'source_scope': 'official_product_label_not_automatically_local_authorization'},
    {'id': 'ondansetron_antiemetic_review', 'ingredient': 'ondansetron',
     'slot': 'antiemetic', 'species': ('dog',),
     'why_consider': '5-HT3 antiemetic option listed in MSD Veterinary Manual. Specific clinical context and route require review.',
     'needs': ('confirm_cause_of_emesis', 'review_concurrent_medicines', 'confirm_formulation'),
     'important_caution': 'Check patient cardiac/electrolyte risks and drug interactions; not automatically equivalent to maropitant.',
     'source_title': 'MSD Veterinary Manual — Drugs Used to Control or Stimulate Vomiting',
     'source_url': MSD, 'source_scope': 'published_veterinary_reference_not_regulatory_approval'},
    {'id': 'metoclopramide_antiemetic_review', 'ingredient': 'metoclopramide',
     'slot': 'antiemetic_prokinetic', 'species': ('dog',),
     'why_consider': 'Dopamine antagonist/prokinetic; may be relevant in selected vomiting or impaired gastric-emptying contexts.',
     'needs': ('confirm_cause_of_emesis', 'rule_out_obstruction_or_perforation', 'review_concurrent_medicines'),
     'important_caution': 'DO NOT USE if GI obstruction or perforation is suspected; monitor for CNS and other adverse effects.',
     'source_title': 'MSD Veterinary Manual — Drugs Used to Control or Stimulate Vomiting',
     'source_url': MSD, 'source_scope': 'published_veterinary_reference_not_regulatory_approval'},
)


def _vomiting_case(case: dict[str, Any]) -> bool:
    clinical = case.get('clinical') or {}
    if not isinstance(clinical, dict):
        return False
    # Only clinician-entered narrative, never unverified AI diagnoses.
    text = ' '.join(str(clinical.get(k) or '') for k in
        ('chief_complaint', 'history', 'presenting_complaint', 'clinical_notes')).lower()
    return bool(re.search(r'vomit|emesis|استفراغ', text))


def build_formulary_review(case: dict[str, Any], approved_rows: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    """Candidate OPTIONS to review, not source of approved patient prescriptions."""
    patient = case.get('patient') or {}
    species = str(patient.get('species') or '').strip().lower()
    summary: dict[str, Any] = {
        'status': 'reference_review_only', 'topic': 'vomiting' if _vomiting_case(case) else None,
        'entries': [], 'reviewed_protocols_present': 0,
        'requires_veterinarian_protocol_approval': True,
        'may_become_a_prescription_automatically': False,
        'dose_calculations_authorized': False,
        'message': 'Published options are not signed, case-specific orders. Check original monograph, local authorization and patient safety.',
    }
    if species not in ('dog', 'cat') or not _vomiting_case(case):
        summary['status'] = 'no_case_matched_reference_topic'
        return summary
    approved_rows = approved_rows or []
    summary['reviewed_protocols_present'] = sum(1 for p in approved_rows if isinstance(p, dict) and p.get('review_status') == 'approved')
    checks = case.get('prescription_checks') or {}
    if not isinstance(checks, dict):
        checks = {}
    for item in _CATALOG:
        if species not in item['species']:
            continue
        barriers = list(item['needs'])
        status = 'clinical_reference_pending_review'
        if item['ingredient'] == 'metoclopramide' and checks.get('obstruction_ruled_out') is not True:
            status = 'withheld_possible_obstruction'
        entry = {k: list(v) if isinstance(v, tuple) else v for k, v in item.items()}
        entry.update(status=status, review_status='not_approved_by_clinician',
                     can_enter_first_choice=False, can_enter_alternative=False,
                     can_enter_economic=False, patient_specific_dose=None,
                     clinician_review_barriers=barriers)
        summary['entries'].append(entry)
    summary['reference_options_found'] = len(summary['entries'])
    summary['clinical_options_approved_for_patient'] = 0
    return summary


def build_supportive_care_review(case: dict[str, Any]) -> list[dict[str, Any]]:
    """Potential supportive care as clinical *assessment*, never IV fluid Rx."""
    if not _vomiting_case(case):
        return []
    checks = case.get('prescription_checks') or {}
    hydration_assessed = isinstance(checks, dict) and checks.get('hydration_assessed') is True
    return [{
        'id': 'individualized_fluid_assessment',
        'title': 'Fluid and electrolyte assessment (NOT an automatic serum order)',
        'status': 'awaiting_patient_fluid_assessment' if not hydration_assessed else 'clinical_review_required',
        'why': 'Vomiting can create losses; determine perfusion, dehydration, ongoing losses and ability to drink before prescribing fluids.',
        'source_title': '2024 AAHA Fluid Therapy Guidelines for Dogs and Cats',
        'source_url': AAHA,
        'automatic_volume_ml': None,
        'automatic_rate_ml_hr': None,
        'is_drug_order': False,
    }]
