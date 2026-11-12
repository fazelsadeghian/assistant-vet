"""Case-aware clinical *review* paths, intentionally separate from drug orders.

v28 safety contract:
 - An indexed word match or AI differential can NEVER authorize a medication.
 - An unlabeled/unsupported treatment is NOT an alternative prescription.
 - Explicitly patient-specific unknowns are visible in structured fields.
 - A later human-approved formulary can fill multiple therapeutic slots without
   changing the interface or fabricating clinician approvals.
"""
from __future__ import annotations

import re
from typing import Any

from app.services.rx_research_v26 import choose_topic

TOPICS = {
    'vomiting': {
        'assessment': [
            ('assess_urgent_cause', 'Investigate urgency and cause',
             'Abdominal examination, foreign-body/obstruction and toxin history; consider imaging/labs when indicated.'),
            ('assess_hydration', 'Hydration and perfusion',
             'Assess mucous membranes, perfusion, body weight changes, losses and electrolytes before deciding any fluid regimen.'),
            ('assess_antiemetic', 'Symptom relief after safety review',
             'Assess antiemetic suitability and ability to tolerate oral medication. A dose shown in Rx is a reference, not patient authorization.'),
            ('assess_recheck', 'Reassessment and follow-up',
             'Document persistence, repeated emesis, blood, pain, and return precautions; diagnose persistent signs.'),
        ],
        'differentials': ['Dietary indiscretion or acute gastritis',
                          'Foreign body / obstruction', 'Toxin exposure',
                          'Pancreatic, metabolic or infectious disease'],
        'disallow_without_indication': ['corticosteroid','routine_antimicrobial','routine_anthelmintic','ulcer_medication'],
    },
    'diarrhea': {
        'assessment': [
            ('assess_hydration','Assess hydration and shock','Examine perfusion, body weight, losses, electrolyte abnormalities and systemic illness.'),
            ('assess_etiology','Determine acute vs chronic and red flags','Blood in stool, vomiting, diet change, travel, infectious risk, drug exposures and abdominal findings.'),
            ('assess_tests','Select diagnostics if justified','Fecal testing, parvoviral testing, laboratory testing or imaging according to the specific patient.'),
            ('assess_followup','Monitor response','Recheck worsening, dehydration, lethargy and persistent signs.'),
        ],
        'differentials': ['Dietary cause','Infectious/parasite disease','Inflammatory or metabolic disease'],
        'disallow_without_indication':['empiric_antimicrobial','corticosteroid'],
    },
    'seizure': {
        'assessment': [
            ('assess_emergency','Assess seizure emergency','Current status, duration, recurrence, temperature and airway.'),
            ('assess_neurologic','Neurologic/metabolic examination','Glucose, toxin/medication exposures, neurologic and systemic abnormalities as indicated.'),
            ('assess_history','Clarify event','Witness/video history, prior events, age, recovery and medications.'),
        ],
        'differentials':['Reactive/metabolic seizure','Toxic exposure','Structural or idiopathic neurologic disease'],
        'disallow_without_indication':['long_term_antiepileptic'],
    },
    'urinary': {
        'assessment': [
            ('assess_obstruction','Exclude urinary obstruction','Confirm urine passage, bladder assessment and immediate care if obstructed.'),
            ('assess_sampling','Evaluate urinary tract','Urinalysis, sediment, culture, imaging when indicated.'),
            ('assess_systemic','Assess systemic risk','Hydration, kidney function, pain, fever, concurrent disease.'),
        ],
        'differentials':['Lower urinary tract disease','Urolithiasis / obstruction','Infection or systemic cause'],
        'disallow_without_indication':['empiric_antimicrobial'],
    },
    'cough': {
        'assessment': [
            ('assess_respiratory_stability','Assess airway and breathing urgency',
             'Respiratory rate/effort, oxygenation, cyanosis, fever and hemodynamic status.'),
            ('assess_cause','Evaluate respiratory versus cardiac causes',
             'Auscultation, thoracic imaging and testing guided by examination.'),
            ('assess_infectious_risk','Evaluate infectious risk',
             'History of exposure, vaccination and clinical signs, if relevant.'),
        ],
        'differentials':['Infectious tracheobronchitis','Airway disease','Pneumonia or cardiopulmonary disease'],
        'disallow_without_indication':['empiric_antimicrobial','corticosteroid','cough_suppressant'],
    },
    'lameness': {
        'assessment': [
            ('assess_orthopedic','Localize and grade lameness',
             'History, gait evaluation, palpation and neurologic screening as indicated.'),
            ('assess_imaging','Check trauma and imaging indications',
             'Evaluate fractures, neurologic deficits, joint disease and pain before treatment.'),
            ('assess_analgesic_safety','Assess analgesic risk',
             'Renal/GI/hepatic status, hydration, concurrent medicines and prior NSAIDs.'),
        ],
        'differentials':['Soft-tissue injury','Arthritis or joint disease','Fracture or neurologic cause'],
        'disallow_without_indication':['nsaid','corticosteroid'],
    },
    'pruritus': {
        'assessment': [
            ('assess_dermatology','Dermatologic examination','Parasites, infection, distribution, cytology and skin lesions.'),
            ('assess_allergy','Investigate underlying drivers','Flea control, diet history, seasonal environment and secondary infection.'),
        ],
        'differentials':['Ectoparasites','Secondary infection','Atopic or food-related skin disease'],
        'disallow_without_indication':['systemic_steroid','antimicrobial'],
    },
}

# These terms signify a *possible* hazard and are not a definitive diagnosis.
_RED_FLAG_TERMS = (
    ('possible_gi_obstruction', r'\b(?:suspected obstruction|bowel obstruction|foreign body|ileus)\b|انسداد|جسم خارجی',
     'Suspected intestinal obstruction or foreign body: immediate examination before symptomatic drug decisions.'),
    ('possible_poisoning', r'\b(?:poisoning|toxin ingestion|toxic exposure|rodenticide)\b|مسموم|بلع سم',
     'Possible toxin exposure: identify agent/time and assess urgency.'),
    ('blood_loss', r'\b(?:hematemesis|melena|coffee.ground vomit)\b|استفراغ خونی|مدفوع قیری',
     'Evidence of GI bleeding: urgent evaluation of severity and cause.'),
)


def _description(case: dict[str, Any]) -> str:
    clinical = case.get('clinical') if isinstance(case.get('clinical'), dict) else {}
    # Keep clinician-entered history only. AI differential is not proven fact.
    return ' '.join(str(v) for v in clinical.values() if isinstance(v,(str,int,float))).lower()[:8000]


def build_clinical_paths(case: dict[str,Any], discovery:dict[str,Any], plan:dict[str,Any]) -> dict[str,Any]:
    topic_info=choose_topic(case)
    topic=topic_info.get('topic','')
    profile=TOPICS.get(topic)
    narrative=_description(case)
    flags=[{'code':code,'message':detail,'trigger':'clinician_history_word_match_not_confirmed'}
           for code,regex,detail in _RED_FLAG_TERMS if re.search(regex,narrative,re.I)]
    safety=plan.get('clinical_safety') or {}
    if safety.get('red_flags') and not flags:
        flags=[{'code':'existing_safety_block','message':str(flag),'trigger':'existing_safety_engine'}
               for flag in safety['red_flags'][:4]]
    checks=case.get('prescription_checks') or {}
    checks=checks if isinstance(checks,dict) else {}
    paths=[]
    if profile:
        for code,title,rationale in profile['assessment']:
            # Cross-reference existing clinician checks where available.
            marker={'assess_hydration':'hydration_assessed','assess_antiemetic':'medications_reviewed'} .get(code)
            verified=bool(marker and checks.get(marker) is True)
            paths.append({'id':code, 'title':title, 'why':rationale,
                          'status':'reviewed_checkpoint_not_full_authorization' if verified else 'clinician_action_needed',
                          'kind':'non_drug_clinical_action', 'medication_order':False})
    else:
        paths=[{'id':'general_exam','title':'Clarify presenting problem and examine patient',
                'why':'No condition-specific decision pathway can be selected from the recorded complaint.',
                'status':'clinician_action_needed','kind':'non_drug_clinical_action','medication_order':False}]
    # Distinguish a label-described sequential option from an interchangeable
    # new prescription. The US label describes oral prevention AFTER initial
    # injectable therapy in actively vomiting dogs; it is not a cat option or
    # a substitute for clinical judgment.
    patient=case.get('patient') or {}
    try: adult_dog=str(patient.get('species') or '').lower()=='dog' and float(patient.get('age_years'))>=1/3
    except (ValueError,TypeError): adult_dog=False
    if topic=='vomiting' and adult_dog:
        paths.append({'id':'conditional_oral_stepdown','title':'Possible oral step-down after initial control (dogs only)',
            'why':'The official Cerenia label describes oral tablets for prevention after injection in actively vomiting dogs. Confirm oral tolerance, product label and patient suitability; not a second simultaneous drug.',
            'source_url':'https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=3bc065ce-09d6-4131-a5a0-dca3909e0bc8',
            'status':'conditional_future_option_not_a_prescription','kind':'sequential_management_option',
            'medication_order':False})
    names=[]
    selected={str(line.get('ingredient') or '').lower() for line in
              (plan.get('first_choice') or {}).get('lines',[]) if isinstance(line,dict)}
    for row in discovery.get('candidates') or []:
        if not isinstance(row,dict):continue
        ingredient=str(row.get('drug_name') or '').lower().strip()
        if ingredient and ingredient not in names and ingredient not in selected:
            names.append(ingredient)
    source_rows=sum(len(((ref.get('monograph_review') or {}).get('source_label_rows') or []))
                    for ref in discovery.get('handbook_references') or [] if isinstance(ref,dict))
    source_only=[{'ingredient':name,'reason':'Found in literature, but no separately patient-matched verified protocol; NOT an Rx line.'}
                 for name in names[:10]]
    if topic=='vomiting':
        for row in source_only:
            if row['ingredient'] in ('prednisone','prednisolone','budesonide'):
                row['reason']='Corticosteroid context is not an indication for undifferentiated acute vomiting.'
            elif row['ingredient'] in ('fenbendazole','pyrantel'):
                row['reason']='Anthelmintic use requires a compatible parasite indication and species-specific verification.'
            elif row['ingredient']=='sucralfate':
                row['reason']='Mucosal protectant is not routine for vomiting without ulcer/erosion indications.'
    current_lines=(plan.get('first_choice') or {}).get('lines') or []
    registry_lines=[x for x in current_lines if x.get('protocol_id') and x.get('reviewer')]
    inferred_lines=[x for x in current_lines if x not in registry_lines]
    return {
        'version':28,'topic':topic or 'unclassified',
        'recognized_topics':topic_info.get('recognized_topics',[]),
        'source':'clinician_recorded_history_only',
        'potential_differentials_to_examine':profile['differentials'] if profile else [],
        'review_actions':paths,
        'case_alerts':flags,
        'discovered_drugs_not_prescribed':source_only,
        'literature_source_rows_found':source_rows,
        'reviewed_formulary_lines':len(registry_lines),
        'reference_only_lines':len(inferred_lines),
        'reason_for_missing_alternative':(
            'No separate clinician-approved indication-matched regimen in the local formulary. '
            'Reference label data and AI drug mentions cannot act as signatures or replacement protocols.'),
        'reason_for_missing_prices':(
            'Automatic supplier checks may fail or return products without exact form, strength, pack size, currency and stock.'),
        'no_extra_drugs_to_fill_plan':True,
        'not_a_signed_prescription':True,
        'review_summary':(
            f'{len(current_lines)} reference/approved treatment line(s), '
            f'{len(source_only)} other drug mention(s) withheld, '
            f'{len(paths)} case-specific review action(s).'),
    }
