from __future__ import annotations

import asyncio
import os
import re
import xml.etree.ElementTree as ET
from typing import Any, Dict, List, Optional

import httpx


class EvidenceSearch:
    """
    Assistant Vet literature search.

    Searches PubMed + Europe PMC concurrently, de-duplicates results,
    and ranks veterinary-relevant papers. No paid API key is required
    for normal low-volume use.
    """

    PUBMED_BASE = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
    EUROPE_PMC_BASE = "https://www.ebi.ac.uk/europepmc/webservices/rest"

    def __init__(self) -> None:
        self.timeout = float(os.getenv("EVIDENCE_HTTP_TIMEOUT", "20"))
        self.ncbi_tool = os.getenv("NCBI_TOOL", "assistant_vet").strip()
        self.ncbi_email = os.getenv("NCBI_EMAIL", "").strip()
        self.ncbi_api_key = os.getenv("NCBI_API_KEY", "").strip()

    @staticmethod
    def _clean(value: Any, limit: int = 6000) -> str:
        if value is None:
            return ""
        return re.sub(r"\s+", " ", str(value)).strip()[:limit]

    @staticmethod
    def _year(value: Any) -> Optional[int]:
        match = re.search(r"(19|20)\d{2}", str(value or ""))
        return int(match.group(0)) if match else None

    @staticmethod
    def _normalize_title(value: str) -> str:
        return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()

    @staticmethod
    def _normalize_doi(value: Any) -> Optional[str]:
        if not value:
            return None
        doi = str(value).strip()
        doi = re.sub(r"^https?://(?:dx\.)?doi\.org/", "", doi, flags=re.I)
        return doi or None

    def _ncbi_params(self) -> Dict[str, str]:
        result = {"tool": self.ncbi_tool}
        if self.ncbi_email:
            result["email"] = self.ncbi_email
        if self.ncbi_api_key:
            result["api_key"] = self.ncbi_api_key
        return result

    async def pubmed(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        query = self._clean(query, 1200)
        if not query:
            return []

        retmax = max(1, min(int(limit), 20))

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            search_response = await client.get(
                f"{self.PUBMED_BASE}/esearch.fcgi",
                params={
                    "db": "pubmed",
                    "term": query,
                    "retmode": "json",
                    "retmax": retmax,
                    "sort": "relevance",
                    **self._ncbi_params(),
                },
            )
            search_response.raise_for_status()

            ids = (
                search_response.json()
                .get("esearchresult", {})
                .get("idlist", [])
            ) or []

            if not ids:
                return []

            fetch_response = await client.get(
                f"{self.PUBMED_BASE}/efetch.fcgi",
                params={
                    "db": "pubmed",
                    "id": ",".join(ids),
                    "retmode": "xml",
                    **self._ncbi_params(),
                },
            )
            fetch_response.raise_for_status()

        root = ET.fromstring(fetch_response.text)
        rows: List[Dict[str, Any]] = []

        for record in root.findall(".//PubmedArticle"):
            pmid = self._clean(record.findtext(".//PMID"), 40) or None
            article = record.find(".//Article")
            if article is None:
                continue

            title_node = article.find("ArticleTitle")
            title = (
                self._clean("".join(title_node.itertext()), 1200)
                if title_node is not None
                else ""
            )
            if not title:
                continue

            abstract_parts = []
            for node in article.findall(".//Abstract/AbstractText"):
                body = self._clean("".join(node.itertext()), 5000)
                if not body:
                    continue
                label = self._clean(node.attrib.get("Label"), 100)
                abstract_parts.append(f"{label}: {body}" if label else body)

            abstract = self._clean(" ".join(abstract_parts), 6500)
            journal = self._clean(article.findtext(".//Journal/Title"), 500)

            year = (
                self._year(article.findtext(".//JournalIssue/PubDate/Year"))
                or self._year(article.findtext(".//JournalIssue/PubDate/MedlineDate"))
            )

            authors = []
            for author in article.findall(".//AuthorList/Author"):
                collective = self._clean(author.findtext("CollectiveName"), 200)
                if collective:
                    authors.append(collective)
                    continue
                last = self._clean(author.findtext("LastName"), 100)
                initials = self._clean(author.findtext("Initials"), 50)
                full = " ".join(x for x in (last, initials) if x)
                if full:
                    authors.append(full)

            doi = None
            for node in record.findall(".//PubmedData/ArticleIdList/ArticleId"):
                if node.attrib.get("IdType", "").lower() == "doi":
                    doi = self._normalize_doi(node.text)
                    break

            publication_types = [
                self._clean(node.text, 120)
                for node in article.findall(".//PublicationTypeList/PublicationType")
                if self._clean(node.text, 120)
            ]

            rows.append(
                {
                    "publication_types": publication_types,
                    "source_id": f"pubmed:{pmid}" if pmid else f"pubmed:title:{self._normalize_title(title)[:80]}",
                    "source_type": "article",
                    "provider": "PubMed",
                    "title": title,
                    "authors": authors[:12],
                    "year": year,
                    "journal": journal,
                    "abstract": abstract,
                    "pmid": pmid,
                    "doi": doi,
                    "url": f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/" if pmid else None,
                    "metadata": {
                        "provider": "PubMed",
                        "pmid": pmid,
                        "doi": doi,
                    },
                }
            )

        return rows[:retmax]

    async def europe_pmc(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        query = self._clean(query, 1200)
        if not query:
            return []

        page_size = max(1, min(int(limit), 20))

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(
                f"{self.EUROPE_PMC_BASE}/search",
                params={
                    "query": query,
                    "format": "json",
                    "resultType": "core",
                    "pageSize": page_size,
                },
            )
            response.raise_for_status()
            payload = response.json()

        rows: List[Dict[str, Any]] = []

        for item in payload.get("resultList", {}).get("result", []) or []:
            title = self._clean(item.get("title"), 1200)
            if not title:
                continue

            pmid = self._clean(item.get("pmid"), 40) or None
            pmcid = self._clean(item.get("pmcid"), 40) or None
            doi = self._normalize_doi(item.get("doi"))
            identity = pmid or pmcid or self._normalize_title(title)[:80]

            rows.append(
                {
                    "publication_types": (
                        item.get("pubTypeList", {}).get("pubType", [])
                        if isinstance(item.get("pubTypeList"), dict) else []
                    ),
                    "source_id": f"europepmc:{identity}",
                    "source_type": "article",
                    "provider": "Europe PMC",
                    "title": title,
                    "authors": self._clean(item.get("authorString"), 1600),
                    "year": self._year(item.get("pubYear") or item.get("firstPublicationDate")),
                    "journal": self._clean(item.get("journalTitle"), 500),
                    "abstract": self._clean(item.get("abstractText"), 6500),
                    "pmid": pmid,
                    "pmcid": pmcid,
                    "doi": doi,
                    "url": (
                        f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/"
                        if pmid
                        else (
                            f"https://europepmc.org/article/MED/{item.get('id')}"
                            if item.get("id")
                            else None
                        )
                    ),
                    "metadata": {
                        "provider": "Europe PMC",
                        "pmid": pmid,
                        "pmcid": pmcid,
                        "doi": doi,
                    },
                }
            )

        return rows[:page_size]

    @staticmethod
    def _key(item: Dict[str, Any]) -> str:
        doi = str(item.get("doi") or "").lower().strip()
        if doi:
            return f"doi:{doi}"

        pmid = str(item.get("pmid") or "").strip()
        if pmid:
            return f"pmid:{pmid}"

        return f"title:{EvidenceSearch._normalize_title(str(item.get('title') or ''))}"

    @staticmethod
    def _query_tokens(query: str) -> set:
        stop = {
            "and", "or", "the", "with", "from", "into", "dog", "dogs",
            "canine", "veterinary", "diagnosis", "treatment", "prognosis",
            "disease", "diseases",
        }
        return {
            token
            for token in re.findall(r"[a-z0-9]+", query.lower())
            if len(token) >= 4 and token not in stop
        }

    def _score(self, item: Dict[str, Any], query: str) -> float:
        tokens = self._query_tokens(query)
        title = str(item.get("title") or "").lower()
        abstract = str(item.get("abstract") or "").lower()
        haystack = title + " " + abstract

        score = 0.0

        for token in tokens:
            if token in title:
                score += 2.5
            elif token in abstract:
                score += 1.0

        # Veterinary / canine relevance is especially important.
        if any(term in haystack for term in ("canine", " dog ", "dogs", "veterinary")):
            score += 4.0

        # Hematology boost only when the case query is about hematology;
        # do not rank anemia papers above gastroenterology papers in GI cases.
        if any(term in query.lower() for term in
               ('anemia', 'anaemia', 'hemolys', 'haemolys', 'imha')) and any(term in haystack for term in (
            "hemolytic anemia",
            "haemolytic anaemia",
            "immune-mediated hemolytic",
            "immune mediated hemolytic",
            "spherocyt",
            "regenerative anemia",
            "regenerative anaemia",
        )):
            score += 5.0

        # Study design is only a retrieval heuristic. It does not prove that a
        # paper supports a clinical claim or that the study is high quality.
        types = " ".join(str(x) for x in (item.get("publication_types") or []))
        design_text = f"{title} {types}".lower()
        if "practice guideline" in design_text or "consensus statement" in design_text:
            score += 5.0
        elif "systematic review" in design_text or "meta-analysis" in design_text:
            score += 4.5
        elif "review" in design_text:
            score += 3.0
        elif "randomized controlled" in design_text or "clinical trial" in design_text:
            score += 2.5
        if "case report" in design_text or "case series" in design_text or "cases series" in design_text:
            score -= 2.0
        if "molecular characterization" in design_text:
            score -= 2.0

        year = item.get("year")
        if isinstance(year, int):
            if year >= 2025:
                score += 0.8
            elif year >= 2020:
                score += 0.4

        if item.get("abstract"):
            score += 1.0
        if item.get("doi"):
            score += 0.25

        return score

    def _is_relevant(self, item: Dict[str, Any], query: str) -> bool:
        """Veterinary-topic filter, not the former anemia-only hardcode.

        An article can be topically retrieved without supporting a specific
        diagnosis; the clinical citation gate makes that distinction.
        """
        title = str(item.get("title") or "").lower()
        abstract = str(item.get("abstract") or "").lower()
        haystack = f" {title} {abstract} "
        q = str(query or "").lower()

        dog = bool(re.search(r"\b(dog|dogs|canine)\b", q))
        cat = bool(re.search(r"\b(cat|cats|feline)\b", q))
        if dog and not re.search(r"\b(dog|dogs|canine)\b", haystack):
            return False
        if cat and not re.search(r"\b(cat|cats|feline)\b", haystack):
            return False

        groups = (
            (("vomit", "gastroenter", "gastritis", "emesis"),
             ("vomit", "emesis", "gastroenter", "gastritis", "nausea")),
            (("diarrh", "enteritis", "colitis"),
             ("diarrh", "enteritis", "colitis")),
            (("anemia", "anaemia", "hemolys", "haemolys", "imha"),
             ("anemia", "anaemia", "hemolys", "haemolys", "imha", "spherocyt")),
            (("seizure", "epilepsy"), ("seizur", "epilep")),
            (("respiratory", "cough"), ("respirator", "cough", "pneumon")),
            (("pruritus", "dermatitis"), ("prurit", "dermat", "skin")),
            (("lameness", "arthritis"), ("lameness", "arthritis", "orthoped")),
            (("renal", "kidney"), ("renal", "kidney", "nephro")),
        )
        for query_terms, article_terms in groups:
            if any(term in q for term in query_terms):
                return any(term in haystack for term in article_terms)

        # Generic fallback for unfamiliar topics. Strip Boolean syntax and
        # generic words, then demand at least one topic token in the article.
        ignored = {
            "and", "the", "veterinary", "diagnosis", "clinical", "dog",
            "dogs", "canine", "cat", "cats", "feline", "disease", "treatment",
        }
        terms = {
            w for w in re.findall(r"[a-z]{5,}", q) if w not in ignored
        }
        return bool(terms) and any(w in haystack for w in terms)

    async def combined(self, query: str, limit: int = 6) -> List[Dict[str, Any]]:
        query = self._clean(query, 1200)
        if not query:
            return []

        per_provider = max(6, min(12, int(limit) * 3))

        pubmed, epmc = await asyncio.gather(
            self.pubmed(query, per_provider),
            self.europe_pmc(query, per_provider),
            return_exceptions=True,
        )

        candidates: List[Dict[str, Any]] = []

        if not isinstance(pubmed, Exception):
            candidates.extend(pubmed)
        if not isinstance(epmc, Exception):
            candidates.extend(epmc)

        deduped: Dict[str, Dict[str, Any]] = {}

        for item in candidates:
            if not self._is_relevant(item, query):
                continue

            key = self._key(item)

            if key not in deduped:
                deduped[key] = item
                continue

            old = deduped[key]
            if bool(item.get("abstract")) and not bool(old.get("abstract")):
                deduped[key] = item
            elif bool(item.get("abstract")) == bool(old.get("abstract")):
                if item.get("provider") == "PubMed":
                    deduped[key] = item

        ranked: List[Dict[str, Any]] = []

        for item in deduped.values():
            row = dict(item)
            row["relevance_score"] = round(self._score(row, query), 3)
            ranked.append(row)

        ranked.sort(
            key=lambda row: (
                float(row.get("relevance_score") or 0.0),
                int(row.get("year") or 0),
            ),
            reverse=True,
        )

        return ranked[: max(1, int(limit))]
