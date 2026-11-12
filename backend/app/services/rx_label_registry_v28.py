"""Small explicitly audited official-label *reference* registry (NOT approvals).

These transcriptions were cross-checked against DailyMed's updated 2025-08-07
Cerenia veterinary injection label. Not a source of off-label extrapolation.
No reviewer signature is fabricated. Every row must remain a review-only draft.
Additional medications require an independently verified protocol/reviewer,
not an AI or unverified textbook name match.
"""
from __future__ import annotations

import math
import re
from typing import Any, Optional

FDA_CERENIA='https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=6aeda328-97c9-4868-8ecb-b3a4dcdbc0a0'


def official_label_reference(case:dict[str,Any], safety:dict[str,Any]) -> Optional[dict[str,Any]]:
    """Only dogs/cats >=4 mo with clinician-recorded active emesis and valid kg.

    Source row: Dogs >=4 months prevention/treatment acute vomiting; Cats >=4
    months treatment vomiting; injectable 10 mg/mL 1 mg/kg SC or IV 1-2 min
    once daily up to 5 days (not an individualized treatment duration).
    """
    patient=case.get('patient') or {}
    clinical=case.get('clinical') or {}
    if not isinstance(patient,dict) or not isinstance(clinical,dict):return None
    if safety.get('red_flags'):return None
    species=str(patient.get('species') or '').lower().strip()
    if species not in ('dog','cat'):return None
    try:
        age=float(patient.get('age_years'))
        kg=float(patient.get('weight_kg'))
    except (TypeError,ValueError):return None
    if not math.isfinite(kg) or kg<=0 or kg>250 or not math.isfinite(age) or age<1/3:return None
    narrative=' '.join(str(v) for v in clinical.values() if isinstance(v,str)).lower()
    if not re.search(r'vomit|emesis|استفراغ|تهوع',narrative):return None
    if re.search(r'\b(?:no|without|denies|not)\s+(?:active\s+)?(?:vomit|emesis)|بدون استفراغ',narrative):
        return None
    amount=round(kg,3) # 1mg/kg
    indication='prevention/treatment of acute vomiting' if species=='dog' else 'treatment of vomiting'
    return {'ingredient':'maropitant','form':'Inj. / Vial','rx_abbreviation':'Inj.',
            'therapeutic_slot':'antiemetic',
            'substitution_group':('canine_acute_vomiting' if species=='dog' else 'feline_vomiting'),
            'unit_kind':'ml','reference_strength_mg_per_ml':10.0,
            'dose_mg_per_kg':1.0,'dose_mg':amount,'units_per_dose':round(kg/10,4),
            'administrations_per_day':1,'reference_max_duration_days':5,
            'duration_days':None,'route':'SC or IV over 1–2 minutes (veterinarian to choose)',
            'why':('Official veterinary injectable label matches '+species+' '+indication+
                   '; assess underlying cause, contraindications and hepatic status before ordering.'),
            'evidence':[{'title':'DailyMed / CERENIA injection official veterinary label',
                         'locator':species+' ≥4 months · dosage and administration · 2025-08-07',
                         'url':FDA_CERENIA, 'source_type':'regulatory_label'}],
            'dose_context':'official_label_transcription_not_patient_authorization',
            'prescription_ready':False, 'patient_approved':False,
            'needs_vet_signoff':True,'cost_toman':None,'price_evidence':{'status':'no_verified_offer'},
            'product_id':'cerenia_inj_10mg_ml_reference',
            'notes':'For licensed veterinarian case review only; not a selected treatment or course duration.',
            'label_indication':indication,'label_validated_for_species':species,
            'reference_label_2025_08_07':True}
