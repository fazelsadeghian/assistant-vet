import argparse
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

from pypdf import PdfReader

from app.services.knowledge_store import KnowledgeStore


MAX_CHARS = 2800
OVERLAP_CHARS = 300


KNOWN_BOOKS = [
    {
        "match": "canine and feline cytopathology",
        "book_key": "canine_feline_cytopathology_4e",
        "title": "Canine and Feline Cytopathology",
        "edition": "4th Edition",
        "year": None,
    },
    {
        "match": "ettinger",
        "book_key": "ettinger_internal_medicine_9e",
        "title": "Ettinger's Textbook of Veterinary Internal Medicine",
        "edition": "9th Edition",
        "year": 2024,
    },
    {
        "match": "greene",
        "book_key": "greene_infectious_diseases_5e",
        "title": "Greene's Infectious Diseases of the Dog and Cat",
        "edition": "5th Edition",
        "year": None,
    },
    {
        "match": "muller & kirk",
        "book_key": "muller_kirk_dermatology_7e",
        "title": "Muller & Kirk's Small Animal Dermatology",
        "edition": "7th Edition",
        "year": None,
    },
    {
        "match": "plumb",
        "book_key": "plumb_veterinary_drug_handbook_10e",
        "title": "Plumb's Veterinary Drug Handbook",
        "edition": "10th Edition",
        "year": None,
    },
    {
        "match": "schalm",
        "book_key": "schalm_veterinary_hematology_7e",
        "title": "Schalm's Veterinary Hematology",
        "edition": "7th Edition",
        "year": None,
    },
    {
        "match": "small animal diagnostic ultrasound",
        "book_key": "small_animal_diagnostic_ultrasound_4e",
        "title": "Small Animal Diagnostic Ultrasound",
        "edition": "4th Edition",
        "year": None,
    },
    {
        "match": "small animal internal medicine",
        "book_key": "small_animal_internal_medicine",
        "title": "Small Animal Internal Medicine",
        "edition": None,
        "year": None,
    },
    {
        "match": "thrall",
        "book_key": "thrall_diagnostic_radiology_8e",
        "title": "Thrall's Textbook of Veterinary Diagnostic Radiology",
        "edition": "8th Edition",
        "year": None,
    },
    {
        "match": "veterinary hematology, clinical chemistry, and cytology",
        "book_key": "veterinary_hematology_clinical_chemistry_cytology_3e",
        "title": "Veterinary Hematology, Clinical Chemistry, and Cytology",
        "edition": "3rd Edition",
        "year": None,
    },
]



def _clean_line(text: str) -> str:
    text = text.replace("\x00", " ").replace("\u00ad", "")
    text = text.replace("\ufb01", "fi").replace("\ufb02", "fl")
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def _normalize_for_chunking(text: str) -> str:
    """
    Keep paragraph boundaries long enough to detect headings, then normalize
    each paragraph separately. This is safer than flattening the whole page
    before chapter/section detection.
    """
    text = text.replace("\x00", " ").replace("\u00ad", "")
    text = text.replace("\ufb01", "fi").replace("\ufb02", "fl")
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    lines = [_clean_line(line) for line in text.split("\n")]

    paragraphs: List[str] = []
    buffer: List[str] = []

    for line in lines:
        if not line:
            if buffer:
                paragraphs.append(" ".join(buffer).strip())
                buffer = []
            continue

        # Preserve obvious headings as standalone paragraphs.
        if _looks_like_heading(line):
            if buffer:
                paragraphs.append(" ".join(buffer).strip())
                buffer = []
            paragraphs.append(line)
            continue

        buffer.append(line)

    if buffer:
        paragraphs.append(" ".join(buffer).strip())

    return "\n\n".join(p for p in paragraphs if p)


def _looks_like_heading(line: str) -> bool:
    if not line:
        return False

    s = line.strip()

    if re.search(r"\bCHAPTER\s+\d{1,4}\b", s, re.IGNORECASE):
        return True
    if re.search(r"\bSECTION\s+([IVXLC]+|\d+)\b", s, re.IGNORECASE):
        return True
    if re.fullmatch(r"REFERENCES", s, re.IGNORECASE):
        return True
    if re.fullmatch(r"SELECTED REFERENCES", s, re.IGNORECASE):
        return True
    if re.fullmatch(r"FURTHER READING", s, re.IGNORECASE):
        return True
    if re.fullmatch(r"BIBLIOGRAPHY", s, re.IGNORECASE):
        return True

    # Short all-caps lines are commonly subsection headings.
    letters = [c for c in s if c.isalpha()]
    if 3 <= len(letters) <= 90:
        upper_ratio = sum(1 for c in letters if c.isupper()) / len(letters)
        if upper_ratio > 0.88 and len(s) <= 120:
            return True

    return False


def _clean_heading(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    value = re.sub(r"\s+", " ", value)
    value = re.sub(r"eBooks\.Health\.Elsevier\.com.*$", "", value, flags=re.IGNORECASE)
    value = value.strip(" \t\r\n•|:-")
    return value[:240] if value else None


def _extract_section(raw_text: str) -> Optional[str]:
    patterns = [
        r"\bSECTION\s+([IVXLC]+|\d+)\s*[•|:\-]?\s*([^\n\r]{0,140})",
        r"\bSECTION\s+([IVXLC]+|\d+)\b",
    ]

    for pattern in patterns:
        match = re.search(pattern, raw_text, flags=re.IGNORECASE)
        if not match:
            continue

        number = match.group(1)
        suffix = match.group(2) if match.lastindex and match.lastindex >= 2 else ""
        suffix = re.split(
            r"\b(?:CHAPTER|eBooks\.Health\.Elsevier\.com)\b",
            suffix,
            maxsplit=1,
            flags=re.IGNORECASE,
        )[0]
        return _clean_heading(f"Section {number} {suffix}")

    return None


def _extract_chapter(raw_text: str) -> Optional[str]:
    """
    Prefer chapter number + title when the PDF header exposes both.
    Fall back to 'Chapter N' rather than inventing a title.
    """
    header_patterns = [
        r"\bChapter\s+(\d{1,4})\s*[•|:\-]\s*([^\n\r]{3,160})",
        r"\bCHAPTER\s+(\d{1,4})\s*[•|:\-]?\s*([^\n\r]{3,160})",
    ]

    for pattern in header_patterns:
        match = re.search(pattern, raw_text, flags=re.IGNORECASE)
        if not match:
            continue

        number = match.group(1)
        title = match.group(2)
        title = re.split(
            r"\b(?:eBooks\.Health\.Elsevier\.com|SECTION|CHAPTER)\b",
            title,
            maxsplit=1,
            flags=re.IGNORECASE,
        )[0]
        title = re.sub(r"\s+\d{1,4}\s*$", "", title).strip()
        title = _clean_heading(title)

        if title and not re.fullmatch(r"\d+", title):
            return f"Chapter {number} — {title}"
        return f"Chapter {number}"

    simple = re.search(r"\bCHAPTER\s+(\d{1,4})\b", raw_text, flags=re.IGNORECASE)
    if simple:
        return f"Chapter {simple.group(1)}"

    simple = re.search(r"\bChapter\s+(\d{1,4})\b", raw_text, flags=re.IGNORECASE)
    if simple:
        return f"Chapter {simple.group(1)}"

    return None


def _extract_printed_page(raw_text: str) -> Optional[int]:
    """
    Best-effort only. PDF page index remains the authoritative locator.
    """
    patterns = [
        r"\bChapter\s+\d{1,4}\s*[•|:\-].{0,180}?\s+(\d{1,4})\s+eBooks\.Health\.Elsevier\.com\b",
        r"\bSECTION\s+[IVXLC\d]+.{0,180}?\s+(\d{1,4})\s+eBooks\.Health\.Elsevier\.com\b",
        r"eBooks\.Health\.Elsevier\.com\s+.*?\s+(\d{1,4})\b",
    ]

    for pattern in patterns:
        match = re.search(pattern, raw_text, flags=re.IGNORECASE | re.DOTALL)
        if match:
            value = int(match.group(1))
            if 1 <= value <= 5000:
                return value

    return None


def _is_reference_heading(paragraph: str) -> bool:
    return bool(
        re.fullmatch(
            r"(REFERENCES|SELECTED REFERENCES|FURTHER READING|BIBLIOGRAPHY)",
            paragraph.strip(),
            flags=re.IGNORECASE,
        )
    )


def _is_reference_like(text: str) -> bool:
    """
    Conservative reference detector used only to label chunks.
    We do not delete references because they can still be clinically useful.
    """
    text = text.strip()
    if not text:
        return False

    numbered_refs = len(
        re.findall(
            r"(?:^|\s)\d{1,3}\.\s+[A-Z][A-Za-z'`\-]+",
            text,
        )
    )
    journal_tokens = len(
        re.findall(
            r"\b(?:doi|J Vet|Vet J|J Small Anim Pract|JVIM|PubMed|et al\.)\b",
            text,
            flags=re.IGNORECASE,
        )
    )

    return numbered_refs >= 3 or journal_tokens >= 4


def _split_long_text(
    text: str,
    max_chars: int = MAX_CHARS,
    overlap_chars: int = OVERLAP_CHARS,
) -> List[str]:
    text = re.sub(r"[ \t]+", " ", text).strip()
    if not text:
        return []
    if len(text) <= max_chars:
        return [text]

    chunks: List[str] = []
    start = 0

    while start < len(text):
        end = min(len(text), start + max_chars)

        if end < len(text):
            candidates = [
                text.rfind(". ", start, end),
                text.rfind("? ", start, end),
                text.rfind("! ", start, end),
                text.rfind("; ", start, end),
            ]
            boundary = max(candidates)

            if boundary > start + int(max_chars * 0.55):
                end = boundary + 1

        piece = text[start:end].strip()
        if piece:
            chunks.append(piece)

        if end >= len(text):
            break

        start = max(start + 1, end - overlap_chars)

    return chunks


def _chunk_page(
    normalized_text: str,
    *,
    page_number: int,
    chapter: Optional[str],
    section: Optional[str],
    printed_page: Optional[int],
    max_chars: int = MAX_CHARS,
    overlap_chars: int = OVERLAP_CHARS,
) -> List[Dict[str, Any]]:
    """
    Paragraph-aware chunking. This avoids blindly slicing chapter headings away
    from the text they describe.
    """
    paragraphs = [
        p.strip()
        for p in re.split(r"\n\s*\n", normalized_text)
        if p.strip()
    ]

    chunks: List[Dict[str, Any]] = []
    buffer: List[str] = []
    buffer_chars = 0
    active_section = section
    seen_reference_heading = False

    def flush() -> None:
        nonlocal buffer, buffer_chars
        if not buffer:
            return

        combined = "\n\n".join(buffer).strip()
        for piece in _split_long_text(
            combined,
            max_chars=max_chars,
            overlap_chars=overlap_chars,
        ):
            chunk_section = active_section
            if seen_reference_heading or _is_reference_like(piece):
                chunk_section = "References"

            chunks.append(
                {
                    "page_start": page_number,
                    "page_end": page_number,
                    "printed_page_start": printed_page,
                    "printed_page_end": printed_page,
                    "chapter": chapter,
                    "section": chunk_section,
                    "text": piece,
                }
            )

        buffer = []
        buffer_chars = 0

    for paragraph in paragraphs:
        if _is_reference_heading(paragraph):
            flush()
            active_section = "References"
            seen_reference_heading = True
            continue

        if _looks_like_heading(paragraph) and len(paragraph) <= 160:
            # Keep subsection heading with the following content rather than
            # creating a tiny heading-only chunk.
            if buffer and buffer_chars > int(max_chars * 0.55):
                flush()

        projected = buffer_chars + len(paragraph) + (2 if buffer else 0)

        if buffer and projected > max_chars:
            flush()

        buffer.append(paragraph)
        buffer_chars += len(paragraph) + (2 if buffer_chars else 0)

    flush()
    return chunks


def ingest_pdf(
    pdf_path: str,
    *,
    book_key: str,
    title: str,
    edition: str | None = None,
    year: int | None = None,
) -> Dict[str, Any]:
    path = Path(pdf_path)
    if not path.exists():
        raise FileNotFoundError(path)

    reader = PdfReader(str(path))
    chunks: List[Dict[str, Any]] = []
    empty_pages = 0

    current_chapter: Optional[str] = None
    current_section: Optional[str] = None
    current_printed_page: Optional[int] = None
    chapter_pages_detected = 0
    section_pages_detected = 0

    total_pages = len(reader.pages)

    for index, page in enumerate(reader.pages, start=1):
        raw_text = page.extract_text() or ""

        if not raw_text.strip():
            empty_pages += 1
            continue

        detected_section = _extract_section(raw_text)
        if detected_section:
            current_section = detected_section
            section_pages_detected += 1

        detected_chapter = _extract_chapter(raw_text)
        if detected_chapter:
            current_chapter = detected_chapter
            chapter_pages_detected += 1

        detected_printed_page = _extract_printed_page(raw_text)
        if detected_printed_page is not None:
            current_printed_page = detected_printed_page

        normalized = _normalize_for_chunking(raw_text)
        if not normalized:
            empty_pages += 1
            continue

        chunks.extend(
            _chunk_page(
                normalized,
                page_number=index,
                chapter=current_chapter,
                section=current_section,
                printed_page=current_printed_page,
            )
        )

        # Useful when ingesting from PowerShell; does not affect Swagger output.
        if index % 100 == 0 or index == total_pages:
            print(
                f"[ingest] {path.name}: page {index}/{total_pages} | "
                f"chunks={len(chunks)}",
                flush=True,
            )

    store = KnowledgeStore()
    book_id = store.upsert_book(
        book_key=book_key,
        title=title,
        edition=edition,
        year=year,
        source_path=str(path),
    )
    store.replace_chunks(book_id, chunks)

    reference_chunks = sum(
        1 for chunk in chunks if chunk.get("section") == "References"
    )

    return {
        "book_id": book_id,
        "book_key": book_key,
        "title": title,
        "edition": edition,
        "year": year,
        "pages": total_pages,
        "empty_or_unreadable_pages": empty_pages,
        "chunks_indexed": len(chunks),
        "chapter_pages_detected": chapter_pages_detected,
        "section_pages_detected": section_pages_detected,
        "reference_chunks": reference_chunks,
        "semantic": store.semantic_status(),
    }


def _slugify(value: str) -> str:
    value = value.lower()
    value = re.sub(r"\([^)]*\)", " ", value)
    value = re.sub(r"\b\d+(?:st|nd|rd|th)\s+edition\b", " ", value)
    value = re.sub(r"[^a-z0-9]+", "_", value)
    return re.sub(r"_+", "_", value).strip("_")[:100]


def _metadata_from_filename(path: Path) -> Dict[str, Any]:
    stem = path.stem
    lowered = stem.lower()

    # Canonical metadata keeps stable book_keys across re-indexing and prevents
    # duplicate copies of the same textbook in the knowledge database.
    for item in KNOWN_BOOKS:
        if item["match"].lower() in lowered:
            return {
                "book_key": item["book_key"],
                "title": item["title"],
                "edition": item["edition"],
                "year": item["year"],
            }

    edition_match = re.search(
        r"(\d+(?:st|nd|rd|th)\s+Edition)",
        stem,
        flags=re.IGNORECASE,
    )
    edition = edition_match.group(1) if edition_match else None

    title = re.sub(
        r",?\s*\d+(?:st|nd|rd|th)\s+Edition",
        "",
        stem,
        flags=re.IGNORECASE,
    )
    title = re.sub(r"\s*\(VetBooks\.ir\)\s*", "", title, flags=re.IGNORECASE)
    title = re.sub(r"\s+", " ", title).strip(" ,")

    return {
        "book_key": _slugify(stem),
        "title": title,
        "edition": edition,
        "year": None,
    }


def ingest_directory(
    books_dir: str,
    *,
    skip_existing: bool = True,
) -> Dict[str, Any]:
    """
    Batch helper for the local books folder.
    Existing indexed books are skipped by book_key unless skip_existing=False.
    """
    root = Path(books_dir)
    if not root.exists():
        raise FileNotFoundError(root)

    pdfs = sorted(root.glob("*.pdf"))
    store = KnowledgeStore()

    with store._connect() as con:
        existing_keys = {
            row["book_key"]
            for row in con.execute("SELECT book_key FROM books").fetchall()
        }

    results: List[Dict[str, Any]] = []

    for index, pdf in enumerate(pdfs, start=1):
        meta = _metadata_from_filename(pdf)

        if skip_existing and meta["book_key"] in existing_keys:
            results.append(
                {
                    "file": pdf.name,
                    "book_key": meta["book_key"],
                    "status": "skipped_existing",
                }
            )
            print(
                f"[batch] {index}/{len(pdfs)} SKIP {pdf.name}",
                flush=True,
            )
            continue

        print(
            f"[batch] {index}/{len(pdfs)} START {pdf.name}",
            flush=True,
        )

        try:
            result = ingest_pdf(
                str(pdf),
                book_key=meta["book_key"],
                title=meta["title"],
                edition=meta["edition"],
                year=meta["year"],
            )
            result["file"] = pdf.name
            result["status"] = "indexed"
            results.append(result)
            existing_keys.add(meta["book_key"])
            print(
                f"[batch] {index}/{len(pdfs)} DONE {pdf.name}",
                flush=True,
            )
        except Exception as exc:
            results.append(
                {
                    "file": pdf.name,
                    "book_key": meta["book_key"],
                    "status": "error",
                    "error": str(exc),
                }
            )
            print(
                f"[batch] {index}/{len(pdfs)} ERROR {pdf.name}: {exc}",
                flush=True,
            )

    return {
        "books_dir": str(root),
        "pdf_count": len(pdfs),
        "results": results,
        "semantic": store.semantic_status(),
    }


def _main() -> None:
    parser = argparse.ArgumentParser(
        description="Assistant Vet veterinary textbook ingester"
    )
    parser.add_argument(
        "--books-dir",
        default="books",
        help="Directory containing PDF textbooks",
    )
    parser.add_argument(
        "--batch",
        action="store_true",
        help="Ingest every PDF in --books-dir",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-index books already present in the knowledge database",
    )
    args = parser.parse_args()

    if not args.batch:
        parser.error("Use --batch for directory ingestion.")

    result = ingest_directory(
        args.books_dir,
        skip_existing=not args.force,
    )

    indexed = sum(
        1 for item in result["results"] if item.get("status") == "indexed"
    )
    skipped = sum(
        1
        for item in result["results"]
        if item.get("status") == "skipped_existing"
    )
    errors = sum(
        1 for item in result["results"] if item.get("status") == "error"
    )

    print(
        f"[batch] COMPLETE indexed={indexed} skipped={skipped} errors={errors}",
        flush=True,
    )


if __name__ == "__main__":
    _main()
