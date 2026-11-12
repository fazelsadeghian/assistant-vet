from __future__ import annotations

import json
import os
import re
from typing import Any, Dict, List, Tuple

import httpx

from app.config import settings
from app.providers.base import AIProvider


def _env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


_FAST_SCHEMA_BASE: Dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "required": ["d", "miss", "tests", "tx", "u"],
    "properties": {
        "d": {
            "type": "array",
            "minItems": 1,
            "maxItems": 3,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["dx", "conf", "pro", "con", "src"],
                "properties": {
                    "dx": {"type": "string", "maxLength": 100},
                    "conf": {
                        "type": "string",
                        "enum": ["high", "moderate", "low"],
                    },
                    "pro": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 4,
                    },
                    "con": {
                        "type": "array",
                        "items": {"type": "string", "maxLength": 120},
                        "maxItems": 2,
                    },
                    "src": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 2,
                    },
                },
            },
        },
        "miss": {
            "type": "array",
            "items": {"type": "string", "maxLength": 110},
            "maxItems": 3,
        },
        "tests": {
            "type": "array",
            "maxItems": 3,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["t", "why", "src"],
                "properties": {
                    "t": {"type": "string", "maxLength": 90},
                    "why": {"type": "string", "maxLength": 130},
                    "src": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 2,
                    },
                },
            },
        },
        "tx": {
            "type": "array",
            "maxItems": 2,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["line", "why", "src"],
                "properties": {
                    "line": {"type": "string", "maxLength": 100},
                    "why": {"type": "string", "maxLength": 120},
                    "src": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 2,
                    },
                },
            },
        },
        "u": {"type": "string", "maxLength": 140},
    },
}


class OllamaProvider(AIProvider):
    name = "ollama-local"

    def __init__(self) -> None:
        self.base_url = (
            os.getenv("OLLAMA_BASE_URL")
            or getattr(settings, "ollama_base_url", None)
            or "http://127.0.0.1:11434"
        ).rstrip("/")

        self.model = (
            os.getenv("OLLAMA_MODEL")
            or getattr(settings, "ollama_model", None)
            or "qwen3:8b"
        )

        self.timeout = float(os.getenv("OLLAMA_TIMEOUT", "600"))
        self.num_ctx = int(os.getenv("OLLAMA_FAST_NUM_CTX", "4096"))
        self.num_predict = int(os.getenv("OLLAMA_FAST_NUM_PREDICT", "900"))
        self.deep_num_ctx = int(os.getenv("OLLAMA_DEEP_NUM_CTX", "8192"))
        self.deep_num_predict = int(os.getenv("OLLAMA_DEEP_NUM_PREDICT", "1500"))
        self.keep_alive = os.getenv("OLLAMA_KEEP_ALIVE", "30m")
        self.think = _env_bool("OLLAMA_THINK", False)

    def _mode(self) -> str:
        value = os.getenv("ASSISTANT_VET_MODE", "fast").strip().lower()
        return "deep" if value == "deep" else "fast"

    def _active_num_ctx(self) -> int:
        return self.deep_num_ctx if self._mode() == "deep" else self.num_ctx

    def _active_num_predict(self) -> int:
        if self._mode() == "deep":
            return self.deep_num_predict
        # Qwen3:8B stays unchanged. Fast mode only removes redundant prose
        # that the deterministic layer can build itself.
        return min(self.num_predict, 650)

    async def available(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{self.base_url}/api/tags")
                response.raise_for_status()

            models = response.json().get("models", []) or []
            names = {
                str(item.get("name") or "")
                for item in models
                if isinstance(item, dict)
            }

            return (
                self.model in names
                or any(
                    name.startswith(self.model)
                    or self.model.startswith(name)
                    for name in names
                )
            )
        except Exception:
            return False

    async def warmup(self) -> Dict[str, Any]:
        body = {
            "model": self.model,
            "prompt": "",
            "stream": False,
            "keep_alive": self.keep_alive,
            "options": {"num_ctx": self._active_num_ctx()},
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    f"{self.base_url}/api/generate",
                    json=body,
                )
                response.raise_for_status()
            return {"ok": True, **self._metrics(response.json())}
        except Exception as exc:
            return {"ok": False, "error": str(exc)}

    @staticmethod
    def _metrics(payload: Dict[str, Any]) -> Dict[str, Any]:
        if not isinstance(payload, dict):
            return {}

        result: Dict[str, Any] = {}
        for key in (
            "total_duration",
            "load_duration",
            "prompt_eval_count",
            "prompt_eval_duration",
            "eval_count",
            "eval_duration",
            "done_reason",
        ):
            if key in payload:
                result[key] = payload.get(key)

        try:
            if payload.get("total_duration") is not None:
                result["total_seconds"] = round(
                    float(payload["total_duration"]) / 1_000_000_000,
                    3,
                )
        except Exception:
            pass

        try:
            count = float(payload.get("eval_count") or 0)
            duration = float(payload.get("eval_duration") or 0)
            if count > 0 and duration > 0:
                result["generation_tokens_per_second"] = round(
                    count / (duration / 1_000_000_000),
                    2,
                )
        except Exception:
            pass

        return result

    @staticmethod
    def _clean_text(value: Any, limit: int) -> str:
        text = re.sub(r"<[^>]+>", " ", str(value or ""))
        text = " ".join(text.split())
        return text[:limit]

    def _compact_sources(
        self,
        sources: Any,
    ) -> Tuple[List[Dict[str, Any]], Dict[str, str]]:
        if not isinstance(sources, list):
            return [], {}

        compact: List[Dict[str, Any]] = []
        aliases: Dict[str, str] = {}

        for index, source in enumerate(sources, start=1):
            if not isinstance(source, dict):
                continue

            real_id = str(source.get("source_id") or "")
            if not real_id:
                continue

            alias = f"S{len(compact) + 1}"
            aliases[alias] = real_id
            source_type = str(source.get("source_type") or "")

            row: Dict[str, Any] = {
                "id": alias,
                "type": source_type,
                "title": self._clean_text(source.get("title"), 180),
            }

            if source_type == "textbook":
                row["loc"] = self._clean_text(
                    " | ".join(
                        str(x)
                        for x in (
                            source.get("chapter"),
                            source.get("section"),
                        )
                        if x
                    ),
                    180,
                )
                row["text"] = self._clean_text(source.get("snippet"), 480)
            else:
                row["year"] = source.get("year")
                row["text"] = self._clean_text(source.get("abstract"), 720)

            compact.append(row)

        return compact, aliases

    @staticmethod
    def _case_facts(
        case: Any,
    ) -> Tuple[List[Dict[str, str]], Dict[str, str]]:
        if not isinstance(case, dict):
            return [], {}

        skip_exact = {
            "case_id",
            "veterinarian_notes",
            "requested_article_search",
            "max_evidence_results",
        }
        skip_fragments = {
            "base64",
            "bytes",
            "binary",
            "image_data",
            "dicom_data",
            "file_path",
        }

        raw_facts: List[Tuple[str, Any]] = []

        def walk(value: Any, path: str = "case") -> None:
            if isinstance(value, dict):
                for key, item in value.items():
                    key_s = str(key)
                    key_l = key_s.lower()

                    if key_s in skip_exact:
                        continue
                    if path == "case.patient" and key_s == "name":
                        continue
                    if any(fragment in key_l for fragment in skip_fragments):
                        continue
                    if item is None or item == "" or item == [] or item == {}:
                        continue

                    walk(item, f"{path}.{key_s}")
                return

            if isinstance(value, list):
                for index, item in enumerate(value[:8]):
                    if item is None or item == "" or item == {}:
                        continue
                    walk(item, f"{path}[{index}]")
                return

            raw_facts.append((path, value))

        walk(case)

        facts: List[Dict[str, str]] = []
        aliases: Dict[str, str] = {}

        for path, value in raw_facts[:28]:
            alias = f"F{len(facts) + 1}"
            display = f"{path} = {value}"
            short_path = path.removeprefix("case.")
            fact_text = f"{short_path}={value}"
            facts.append({"id": alias, "fact": fact_text})
            aliases[alias] = display

        return facts, aliases

    @staticmethod
    def _schema_for_aliases(
        source_aliases: Dict[str, str],
        fact_aliases: Dict[str, str],
    ) -> Dict[str, Any]:
        schema = json.loads(json.dumps(_FAST_SCHEMA_BASE))

        source_enum = list(source_aliases.keys())
        fact_enum = list(fact_aliases.keys())

        for section in ("d", "tests", "tx"):
            item = schema["properties"][section]["items"]
            src_items = item["properties"]["src"]["items"]
            if source_enum:
                src_items["enum"] = source_enum

        pro_items = schema["properties"]["d"]["items"]["properties"]["pro"]["items"]
        if fact_enum:
            pro_items["enum"] = fact_enum

        return schema

    @staticmethod
    def _extract_json_object(raw: str) -> Dict[str, Any]:
        text = (raw or "").strip()

        if text.startswith("```"):
            text = text.strip("`")
            if text.lower().startswith("json"):
                text = text[4:].lstrip()

        start = text.find("{")
        end = text.rfind("}")

        if start >= 0 and end > start:
            try:
                parsed = json.loads(text[start:end + 1])
                if isinstance(parsed, dict):
                    return parsed
            except Exception:
                pass

        return {
            "error": "invalid_json_from_model",
            "raw_response": text[:1600],
        }

    async def _chat(
        self,
        system_prompt: str,
        user_payload: Dict[str, Any],
        *,
        format_spec: Any,
        num_predict: int,
    ) -> Dict[str, Any]:
        body = {
            "model": self.model,
            "stream": False,
            "format": format_spec,
            "keep_alive": self.keep_alive,
            "think": self.think,
            "messages": [
                {"role": "system", "content": system_prompt},
                {
                    "role": "user",
                    "content": json.dumps(
                        user_payload,
                        ensure_ascii=False,
                        separators=(",", ":"),
                    ),
                },
            ],
            "options": {
                "temperature": 0.0,
                "num_ctx": self._active_num_ctx(),
                "num_predict": int(num_predict),
            },
        }

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{self.base_url}/api/chat",
                json=body,
            )

            if response.status_code >= 400 and isinstance(format_spec, dict):
                body["format"] = "json"
                response = await client.post(
                    f"{self.base_url}/api/chat",
                    json=body,
                )

            response.raise_for_status()

        payload = response.json()
        raw = payload.get("message", {}).get("content", "")

        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = self._extract_json_object(raw)

        if not isinstance(parsed, dict):
            parsed = {
                "error": "non_object_model_response",
                "raw_response": str(raw)[:1600],
            }

        parsed["_ollama_metrics"] = self._metrics(payload)
        return parsed

    @staticmethod
    def _expand(
        raw: Dict[str, Any],
        source_aliases: Dict[str, str],
        fact_aliases: Dict[str, str],
    ) -> Dict[str, Any]:
        if not isinstance(raw, dict):
            return {}

        def srcs(values: Any) -> List[str]:
            if not isinstance(values, list):
                return []
            out: List[str] = []
            for value in values:
                resolved = source_aliases.get(str(value))
                if resolved and resolved not in out:
                    out.append(resolved)
            return out[:2]

        def facts(values: Any) -> List[str]:
            if not isinstance(values, list):
                return []
            out: List[str] = []
            for value in values:
                resolved = fact_aliases.get(str(value))
                if resolved and resolved not in out:
                    out.append(resolved)
            return out[:4]

        differentials: List[Dict[str, Any]] = []
        for item in raw.get("d", []) or []:
            if not isinstance(item, dict):
                continue
            differentials.append(
                {
                    "diagnosis": str(item.get("dx") or "").strip(),
                    "confidence": item.get("conf", "low"),
                    "supporting_case_facts": facts(item.get("pro")),
                    "against_or_uncertain": [
                        str(x).strip()
                        for x in (item.get("con") or [])
                        if str(x).strip()
                    ][:2],
                    "source_ids": srcs(item.get("src")),
                }
            )

        most_probable: List[Dict[str, Any]] = []
        if differentials:
            first = differentials[0]
            rationale_facts = first.get("supporting_case_facts", [])[:3]
            most_probable.append(
                {
                    "diagnosis": first.get("diagnosis", ""),
                    "confidence": first.get("confidence", "low"),
                    "rationale": "; ".join(rationale_facts),
                    "source_ids": list(first.get("source_ids", [])),
                }
            )

        tests: List[Dict[str, Any]] = []
        for item in raw.get("tests", []) or []:
            if not isinstance(item, dict):
                continue
            tests.append(
                {
                    "test": str(item.get("t") or "").strip(),
                    "rationale": str(item.get("why") or "").strip(),
                    "source_ids": srcs(item.get("src")),
                }
            )

        treatments: List[Dict[str, Any]] = []
        for item in raw.get("tx", []) or []:
            if not isinstance(item, dict):
                continue
            treatments.append(
                {
                    "line": str(item.get("line") or "").strip(),
                    "details": str(item.get("why") or "").strip(),
                    "source_ids": srcs(item.get("src")),
                }
            )

        return {
            "modality_interpretations": {},
            "problem_list": [],
            "ranked_differentials": differentials,
            "most_probable_diagnoses": most_probable,
            "conflicts": [],
            "missing_data": [
                str(x).strip()
                for x in (raw.get("miss") or [])
                if str(x).strip()
            ][:3],
            "next_best_tests": tests,
            "treatment_lines": treatments,
            "red_flags": [],
            "uncertainty": str(raw.get("u") or "").strip(),
        }

    async def reason(
        self,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        rules = payload.get("rule_engine")
        if isinstance(rules, dict):
            compact_rules = {
                key: rules.get(key)
                for key in ("conflicts", "warnings", "red_flags")
                if rules.get(key)
            }
        else:
            compact_rules = rules

        compact_sources, source_aliases = self._compact_sources(
            payload.get("source_context")
        )
        compact_facts, fact_aliases = self._case_facts(
            payload.get("case") or {}
        )

        compact_payload = {
            "facts": compact_facts,
            "rules": compact_rules,
            "sources": compact_sources,
        }

        system_prompt = """
You are the clinical reasoning engine for a veterinarian-only dog/cat
decision-support system. Return ONLY JSON matching the schema.

Alias rules are strict:
- F1/F2/... are PATIENT FACT IDs. They may appear ONLY in d[].pro.
- S1/S2/... are SOURCE IDs. They may appear ONLY in src arrays.
- Never write an F# or S# alias inside diagnosis, uncertainty, missing data,
  test names/rationales, treatment text, or against/uncertain prose.

Clinical rules:
- Patient-specific claims come only from supplied facts/rules.
- Sources are GENERAL evidence, never source-patient facts.
- Platelet clumping makes an automated low platelet result unreliable.
  Do not treat true thrombocytopenia as confirmed and do not use it as
  positive IMHA evidence.
- Pseudothrombocytopenia is a data-quality/measurement issue, NOT an
  etiologic disease differential.
- Differential diagnoses must be etiologic possibilities; do not list
  "regenerative anemia", "hemolysis", or other restatements of the syndrome
  as standalone differentials.
- Never combine unrelated etiologic categories into one diagnosis such as
  "infectious or neoplastic cause". Each differential must be one clinically
  coherent etiologic possibility.
- If the submitted anemia pattern is explicitly regenerative, do not rank
  anemia of chronic disease unless the case also contains a separate, clear
  chronic inflammatory/renal/neoplastic context that makes a mixed process
  plausible.
- Do not diagnose anemia, hemolysis, IMHA, blood-loss anemia, or anemia of
  chronic disease from an "anemia_pattern" label alone. When HCT/PCV is
  supplied and does not indicate anemia, treat the pattern label as potentially
  inconsistent and prioritize non-anemia explanations for the presenting
  complaint.
- Chief complaint, history, examination, and objective abnormalities outrank
  generic analyzer labels. A normal platelet flag is not evidence for IMHA.
- Do not assign a specific infectious or viral gastrointestinal etiology from
  acute vomiting alone. Viral/infectious gastroenteritis should require
  supporting anchors such as diarrhea, compatible exposure/outbreak,
  vaccination/age context, fever/systemic infectious evidence, or a relevant
  diagnostic test. Without such anchors, keep infectious etiologies low or omit
  them and prefer a broader nonspecific gastrointestinal differential.
- Avoid redundant overlapping differentials such as "viral gastroenteritis" and
  "infectious gastroenteritis" in the same ranked list.
- For an adult dog with acute vomiting and no specific etiologic anchor, prefer
  appropriately cautious possibilities such as nonspecific acute gastritis/
  gastrointestinal disease, dietary indiscretion, pancreatitis, or
  gastrointestinal obstruction/foreign body when supported by the history and
  unresolved data. Do not give high confidence to an unconfirmed etiology.
- In vomiting cases without objective anemia, do not populate missing-data with
  erythrogram indices such as MCV/MCHC/RBC unless they are independently
  relevant to a real hematologic abnormality.
- Do not output duplicate next tests that are the same clinical action under
  different wording, such as "serum biochemical profile" and "serum
  biochemistry and electrolytes".
- When hemolysis/IMHA is suspected, next tests should be discriminating and
  should prioritize unresolved questions such as platelet-count reliability,
  saline agglutination, and targeted infectious/vector-borne assessment when
  appropriate to exposure/geography. Do not simply repeat already-known data.
- Missing-data items must name clinically important unknowns; do not leave
  miss empty when major diagnostic uncertainties remain.
- Serum bilirubin is not bilirubinuria.
- DAT/Coombs may support an immune-mediated mechanism but does not by itself
  confirm or exclude IMHA.
- Do not recommend repeating information already supplied unless repetition
  is specifically needed to resolve unreliability or trend disease.
- Do not invent findings, doses, thresholds, citations, PMID or DOI.
- Use IMHA terminology.
- Rank at most 3 differentials, 3 discriminating next tests, and 2 treatment
  considerations.
- Treatment is veterinarian decision support. No numeric drug dose unless an
  exact retrieved source explicitly supports it.
- Keep prose very short. Complete the JSON before adding detail.
""".strip()

        schema = self._schema_for_aliases(
            source_aliases,
            fact_aliases,
        )

        raw = await self._chat(
            system_prompt,
            compact_payload,
            format_spec=schema,
            num_predict=self._active_num_predict(),
        )

        metrics = raw.get("_ollama_metrics", {}) if isinstance(raw, dict) else {}
        valid = (
            isinstance(raw, dict)
            and not raw.get("error")
            and isinstance(raw.get("d"), list)
            and bool(raw.get("d"))
        )

        # Fast mode never silently performs a second full 8B generation.
        # This keeps latency bounded and prevents the v0.3.7 double-generation
        # behavior. Deep mode may retry once if the first result is unusable.
        if not valid and self._mode() == "deep":
            recovery_prompt = system_prompt + (
                "\nThe previous response was unusable. Use minimal phrases and "
                "finish the JSON object."
            )
            raw = await self._chat(
                recovery_prompt,
                compact_payload,
                format_spec=schema,
                num_predict=self._active_num_predict(),
            )
            metrics = raw.get("_ollama_metrics", {}) if isinstance(raw, dict) else {}
            if isinstance(metrics, dict):
                metrics["automatic_recovery_retry"] = True
        else:
            if isinstance(metrics, dict):
                metrics["automatic_recovery_retry"] = False

        metrics["model_output_valid"] = bool(valid)
        metrics["fast_output_token_cap"] = (
            self._active_num_predict()
            if self._mode() == "fast"
            else None
        )

        if isinstance(raw, dict):
            raw.pop("_ollama_metrics", None)

        expanded = self._expand(
            raw if isinstance(raw, dict) else {},
            source_aliases,
            fact_aliases,
        )
        expanded["_ollama_metrics"] = metrics
        return expanded

    async def review(
        self,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        system_prompt = """
You are a strict veterinary safety auditor. Return ONLY JSON:
{"status":"pass|revise","unsupported_patient_facts":[],
"source_leakage":[],"citation_mismatches":[],
"missed_or_underweighted_case_facts":[],
"treatment_review":{"issues":[]},"safe_summary":""}
Never invent a source id. If uncertain, return revise.
""".strip()

        compact_sources, _ = self._compact_sources(
            payload.get("source_context")
        )

        review_payload = {
            "case": payload.get("case"),
            "rules": payload.get("rule_engine"),
            "sources": compact_sources,
            "proposed_analysis": payload.get("proposed_analysis"),
            "clinical_gate": payload.get("clinical_gate"),
        }

        return await self._chat(
            system_prompt,
            review_payload,
            format_spec="json",
            num_predict=min(self._active_num_predict(), 600),
        )
