from __future__ import annotations
from typing import Any, Dict, List, Literal, Optional, Union
from pydantic import BaseModel, Field

class Patient(BaseModel):
    name: Optional[str] = None
    species: Literal["dog", "cat"]
    breed: Optional[str] = None
    sex: Optional[str] = None
    age_years: Optional[float] = None
    weight_kg: Optional[float] = None

class ClinicalData(BaseModel):
    chief_complaint: Optional[str] = None
    history: Optional[str] = None
    temperature_c: Optional[float] = None
    heart_rate_bpm: Optional[int] = None
    respiratory_rate_bpm: Optional[int] = None
    dehydration_percent: Optional[float] = None
    mucous_membrane: Optional[str] = None
    crt_seconds: Optional[float] = None
    exam_notes: Optional[str] = None

class CaseInput(BaseModel):
    case_id: str
    patient: Patient
    clinical: Optional[ClinicalData] = None
    cbc: Optional[Dict[str, Any]] = None
    biochemistry: Optional[Dict[str, Any]] = None
    urinalysis: Optional[Dict[str, Any]] = None
    blood_smear: Optional[Dict[str, Any]] = None
    skin_cytology: Optional[Dict[str, Any]] = None
    fecal: Optional[Dict[str, Any]] = None
    radiography: Optional[Dict[str, Any]] = None
    ultrasound: Optional[Dict[str, Any]] = None
    other_tests: Optional[Union[List[Dict[str, Any]], Dict[str, Any], str]] = None
    current_medications: Optional[Union[List[Dict[str, Any]], Dict[str, Any], str]] = None
    veterinarian_notes: Optional[str] = None
    requested_article_search: bool = True
    max_evidence_results: int = Field(default=8, ge=1, le=20)
