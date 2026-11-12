"""Assistant Vet v26 -- book-by-book audit and article relevance review.

All extracted source passages are UNTRUSTED evidence; none are prescriptions.
Every indexed book receives a separate, read-only, topic-oriented FTS query.
This is an audit of indexed matches, NOT a claim to read or validate every page.
Europe PMC abstracts are cited, not treated as authoritative dosing instructions.
"""
from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from html import unescape
from html.parser import HTMLParser
import re
import sqlite3
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional
from urllib.parse import urlencode

import httpx

from app.services.treatment_evidence import _book_database_path, _ingredient_names_in_text

RX_STUDY_BASE = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search'
TOPIC_WORDS = {
    'vomiting': ('vomiting', 'vomit', 'emesis', 'antiemetic', 'استفراغ'),
    'diarrhea': ('diarrhea', 'diarrhoea', 'enteritis', 'اسهال'),
    'seizure': ('seizure', 'epilepsy', 'convulsion', 'تشنج'),
    'cough': ('cough', 'bronchitis', 'respiratory', 'سرفه'),
    'pruritus': ('pruritus', 'itch', 'dermatitis', 'خارش'),
    'urinary': ('urinary', 'cystitis', 'dysuria', 'ادرار'),
    'lameness': ('lameness', 'osteoarthritis', 'لنگش'),
}
SPECIES_ALIASES = {
    'dog': ('dog', 'dogs', 'canine'),
    'cat': ('cat', 'cats', 'feline'),
    'horse': ('horse', 'equine', 'horses'),
    'cow': ('cattle', 'bovine', 'cow'),
    'sheep': ('sheep', 'ovine'),
    'goat': ('goat', 'caprine'),
}
SPECIES_QUERY = {
    'dog': '(DOG OR CANINE)', 'cat': '(CAT OR FELINE)',
    'horse': '(HORSE OR EQUINE)', 'cow': '(CATTLE OR BOVINE)',
    'sheep': '(SHEEP OR OVINE)', 'goat': '(GOAT OR CAPRINE)',
}
_COMMON = {'with', 'from', 'that', 'patient', 'history', 'last', 'over', 'since', 'adult',
           'animal', 'young', 'months', 'week', 'days', 'twice', 'today', 'recent', 'hours',
           'mild', 'severe', 'reduced', 'appetite', 'without', 'possible', 'diagnosis'}


class _StripHTML(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []
    def handle_data(self, text: str) -> None:
        self.parts.append(text)


def _plain(value: Any, limit: int = 600) -> str:
    parser = _StripHTML()
    try:
        parser.feed(str(value or '')[:100_000])
        result = ' '.join(parser.parts)
    except Exception:
        result = re.sub(r'<[^>]*>', ' ', str(value or ''))
    return re.sub(r'\s+', ' ', unescape(result)).strip()[:limit]


def _narrative(case: dict[str, Any]) -> str:
    clinical = case.get('clinical')
    if not isinstance(clinical, dict):
        return ''
    # Only clinician-entered fields, never AI diagnoses, choose article topics.
    return ' '.join(str(v) for v in clinical.values() if isinstance(v, str))[:4000]


def choose_topic(case: dict[str, Any]) -> dict[str, Any]:
    text = _narrative(case).lower()
    selected = [key for key, words in TOPIC_WORDS.items() if any(w in text for w in words)]
    if selected:
        topic = selected[0]
    else:
        words = re.findall(r'[a-z]{4,}', text)
        topic = next((word for word in words if word not in _COMMON), '')
    patient = case.get('patient') or {}
    species = str(patient.get('species') or '').lower()
    return {'species': species, 'topic': topic, 'recognized_topics': selected,
            'search_phrase': topic or 'not_available', 'source': 'clinician_narrative_only'}


def _fts_query(topic: str) -> str:
    words = TOPIC_WORDS.get(topic, (topic,))
    # Exact, quoted expressions avoid FTS operator injection.
    safe = [w for w in words if re.fullmatch(r'[A-Za-z]{4,20}', w)]
    return ' OR '.join('"' + w + '"' for w in safe[:5])


def _source_window(text: str, topic: str, max_chars: int = 380) -> str:
    words = TOPIC_WORDS.get(topic, (topic,))
    hit = next((m for w in words if w for m in [re.search(re.escape(w), text, re.I)] if m), None)
    if hit is None:
        return _plain(text, max_chars)
    start = max(0, hit.start() - 120)
    return _plain(text[start:start + max_chars], max_chars)


def audit_indexed_books(case: dict[str, Any], *, db_path: Optional[Path] = None,
                        max_hits_per_book: int = 3) -> dict[str, Any]:
    """One explicit match query per book. Never query patient names or change DB."""
    topic = choose_topic(case)
    path = db_path or _book_database_path()
    result: dict[str, Any] = {'status': 'unavailable', 'query_topic': topic,
        'books_checked': 0, 'books_with_hits': 0, 'books': [], 'summary_only': True,
        'note': ('Each indexed book is checked for topic matches; passages are sampled, '
                 'not a full-page clinical review. No treatment or dose is approved.')}
    if not path or not Path(path).is_file():
        result['reason'] = 'Local indexed book database not found'
        return result
    expression = _fts_query(topic['topic'])
    try:
        with sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro',
                             uri=True, timeout=5.0) as con:
            con.row_factory = sqlite3.Row
            books = con.execute('SELECT id,book_key,title,edition FROM books ORDER BY title').fetchall()
            result['books_checked'] = len(books)
            if not expression:
                result['status'] = 'insufficient_case_topic'
                result['books'] = [{'book_key': b['book_key'], 'title': b['title'], 'status': 'not_scanned_no_topic'}
                                   for b in books]
                return result
            for book in books:
                entry = {'book_key': book['book_key'], 'title': book['title'], 'edition': book['edition'],
                         'status': 'no_matching_topic_in_index', 'sampled_hits': [],
                         'matched_drug_names': []}
                try:
                    # FTS query is topic-only; a book without drug names still counts.
                    rows = con.execute('''SELECT c.id, c.page_start, c.chapter, c.text
                        FROM chunk_fts JOIN chunks c ON chunk_fts.rowid=c.id
                        WHERE c.book_id=? AND chunk_fts MATCH ?
                        ORDER BY bm25(chunk_fts) LIMIT ?''',
                        (book['id'], expression, min(4, max(1, max_hits_per_book)))).fetchall()
                    names = set()
                    for row in rows:
                        names.update(_ingredient_names_in_text(str(row['text'])))
                        entry['sampled_hits'].append({
                            'source_id': f"kb:{book['book_key']}:{row['id']}",
                            'page_start': row['page_start'],
                            'chapter': _plain(row['chapter'], 100),
                            'passage': _source_window(str(row['text']), topic['topic']),
                            'status': 'topic_match_not_clinically_adjudicated',
                        })
                    entry['matched_drug_names'] = sorted(names)[:12]
                    if rows:
                        entry['status'] = 'indexed_topic_hits_sampled'
                        result['books_with_hits'] += 1
                except sqlite3.Error as exc:
                    entry['status'] = 'index_query_failed'
                    entry['error_type'] = type(exc).__name__
                result['books'].append(entry)
        result['status'] = 'indexed_audit_completed'
    except (OSError, sqlite3.Error) as exc:
        result.update(status='database_read_error', error_type=type(exc).__name__)
    return result


def _study_design(row: dict[str, Any]) -> str:
    types = row.get('pubTypeList') or row.get('publicationTypeList') or {}
    kinds = types.get('publicationType') if isinstance(types, dict) else types
    tokens = ' '.join(str(x) for x in (kinds if isinstance(kinds, list) else [kinds])).lower()
    title = str(row.get('title') or '').lower()
    if 'randomized controlled trial' in tokens or ('randomized' in title and 'trial' in title):
        return 'reported_randomized_trial'
    if 'systematic review' in tokens or 'systematic review' in title:
        return 'reported_systematic_review'
    if 'meta-analysis' in tokens or 'meta analysis' in title:
        return 'reported_meta_analysis'
    if 'clinical trial' in tokens or 'controlled' in title:
        return 'reported_clinical_study'
    if 'case reports' in tokens or 'case report' in title:
        return 'reported_case_report'
    if 'review' in tokens or 'review' in title:
        return 'reported_review'
    return 'not_determined_from_metadata'


def _article(row: dict[str, Any], topic: dict[str, Any], ingredient_names: list[str]) -> Optional[dict[str, Any]]:
    if not isinstance(row, dict):
        return None
    title = _plain(row.get('title'), 260)
    abstract = _plain(row.get('abstractText'), 1500)
    joined = (title + ' ' + abstract).lower()
    if not title or not abstract:
        return None
    species = topic['species']
    aliases = SPECIES_ALIASES.get(species, (species,))
    species_hit = any(re.search(r'(?<!\w)' + re.escape(word) + r'(?!\w)', joined) for word in aliases)
    topic_words = TOPIC_WORDS.get(topic['topic'], (topic['topic'],))
    topic_hit = any(w in joined for w in topic_words if len(w) >= 4)
    matched_ingredients = [n for n in ingredient_names if re.search(r'(?<!\w)' + re.escape(n) + r'(?!\w)', joined)]
    score = int(species_hit) * 3 + int(topic_hit) * 3 + min(2, len(matched_ingredients))
    design = _study_design(row)
    if design == 'reported_randomized_trial': score += 1
    pmid = str(row.get('pmid') or '')
    doi = str(row.get('doi') or '')[:160]
    if pmid.isdigit():
        url = 'https://pubmed.ncbi.nlm.nih.gov/' + pmid + '/'
    elif str(row.get('pmcid') or '').startswith('PMC'):
        url = 'https://europepmc.org/articles/' + str(row['pmcid'])
    else:
        url = None
    return {'title': title, 'year': str(row.get('pubYear') or ''), 'journal': _plain(row.get('journalTitle'), 120),
            'pmid': pmid if pmid.isdigit() else None, 'doi': doi or None, 'url': url,
            'abstract_excerpt': abstract[:740], 'reported_design': design,
            'species_mentioned': species_hit, 'topic_mentioned': topic_hit,
            'ingredients_mentioned': matched_ingredients, 'relevance_score': score,
            'review_status': 'abstract_metadata_screen_only',
            'dose_approved': False,
            'relevance_status': 'population_topic_overlap' if species_hit and topic_hit else 'weak_or_unverified_match'}


def _article_terms(topic: dict[str, Any], names: list[str]) -> list[str]:
    species_expr = SPECIES_QUERY.get(topic['species'])
    if not species_expr or not topic['topic']:
        return []
    terms = TOPIC_WORDS.get(topic['topic'], (topic['topic'],))
    term = ' OR '.join('"' + w + '"' for w in terms[:3] if re.fullmatch(r'[A-Za-z]{4,20}', w))
    if not term:
        return []
    base = f'{species_expr} AND ({term})'
    # Broad search plus a limited targeted search on ACTUAL sourced ingredient names.
    targets = [n for n in names if re.fullmatch(r'[a-z][a-z\- ]{2,35}', n)][:3]
    return [base + ' AND (CLINICAL TRIAL OR RANDOMIZED OR CONTROLLED OR SYSTEMATIC REVIEW)',
            *[base + ' AND "' + n + '"' for n in targets]]


async def search_veterinary_articles(case: dict[str, Any], discovery: dict[str, Any], *,
        request_json: Optional[Callable[[str], Any]] = None,
        max_requests: int = 4) -> dict[str, Any]:
    """Search Europe PMC metadata with bounded requests. No paper is a dosing authority."""
    topic = choose_topic(case)
    names = [str(c.get('drug_name') or '').strip().lower() for c in
             (discovery.get('candidates') or []) if isinstance(c, dict)]
    terms = _article_terms(topic, names)[:max_requests]
    output = {'status': 'not_searched', 'service': 'Europe PMC REST',
              'endpoint': RX_STUDY_BASE, 'queries': terms, 'papers': [],
              'dose_from_abstract_approved': False,
              'note': 'Article metadata/abstract screening is NOT critical appraisal or clinical dose verification.'}
    if not terms:
        output['status'] = 'insufficient_case_topic'
        return output

    async def ask(client: httpx.AsyncClient, query: str) -> tuple[list, str]:
        url = RX_STUDY_BASE + '?' + urlencode({'query': query, 'format': 'json',
                                               'resultType': 'core', 'pageSize': '8'})
        try:
            if request_json is None:
                response = await client.get(url)
                response.raise_for_status()
                payload = response.json()
            else:
                payload = await request_json(url)
            items = (payload.get('resultList') or {}).get('result') or []
            return (items if isinstance(items, list) else []), 'ok'
        except (httpx.HTTPError, ValueError, TypeError, KeyError, OSError) as exc:
            return [], type(exc).__name__

    async with httpx.AsyncClient(timeout=httpx.Timeout(7.0), follow_redirects=False,
        headers={'User-Agent': 'AssistantVet/26 evidence-screening', 'Accept': 'application/json'}) as client:
        results = await asyncio.gather(*(ask(client, t) for t in terms))
    seen = set()
    failures = []
    for (items, status), term in zip(results, terms):
        if status != 'ok':
            failures.append({'query': term, 'reason': status})
        for raw in items:
            paper = _article(raw, topic, names)
            if paper is None or not paper['topic_mentioned'] or paper['relevance_score'] < 3:
                continue
            key = paper['pmid'] or paper['doi'] or paper['title'].lower()
            if key in seen: continue
            seen.add(key)
            paper['matched_query'] = term
            output['papers'].append(paper)
    output['papers'].sort(key=lambda r: (r['relevance_score'], r['reported_design'] == 'reported_randomized_trial'), reverse=True)
    output['papers'] = output['papers'][:12]
    output['failed_queries'] = failures
    output['status'] = ('search_completed' if not failures else
                        'partial_search_failure' if len(failures) < len(terms) else 'unavailable')
    output['checked_at_utc'] = datetime.now(timezone.utc).isoformat()
    return output
