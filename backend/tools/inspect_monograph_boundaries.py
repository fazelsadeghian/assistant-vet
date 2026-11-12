"""Assistant Vet: read-only diagnostic of Plumb's monograph boundaries.

No patient records, book text, or prescriptions are changed. No internet/network.
This outputs only structural metadata and tiny heading contexts for debugging.
NOT a dosing validator.
"""
from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
import re
import sqlite3
import sys

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'AssistantVet_Monograph_Boundary_report.txt'
# These chunk IDs originate from the user's own existing v20 report.
PROBES = [
    ('maropitant', 29426),
    ('metoclopramide', 29696),
    ('fenbendazole', 28257),
    ('sucralfate', 30984),
]
ENTRY_RE = re.compile(r'(?<!\w)([A-Z][A-Za-z-]{3,45})\s+(\d{1,4})\s+\1\s*\([^)]{4,65}\)', re.I)
DOSAGE_RE = re.compile(r'\b(?:dosages?|dosing)(?:\s+(?:and|&|for)\s+(?:uses?|administration|dogs?|cats?|horses?))?\b', re.I)
SECTIONS_RE = re.compile(r'\b(?:prescriber\s+highlights|uses\s*/\s*indications|contraindications\s*/\s*precautions\s*/\s*warnings|pharmacokinetics)\b', re.I)

def db_path():
    try:
        from app.config import settings
        value = Path(settings.knowledge_db).expanduser().resolve()
        if value.is_file():
            return value
    except Exception:
        pass
    return (ROOT / 'data' / 'knowledge' / 'assistant_vet_knowledge.sqlite3').resolve()

def tiny_context(text, start, end, *, cap=130):
    # Metadata / headings only; no multi-paragraph reproduction.
    return re.sub(r'\s+', ' ', text[max(0,start-18):min(len(text), end+95)]).strip()[:cap]

def report(db: Path) -> str:
    lines = [
        'ASSISTANT VET — PLUMB MONOGRAPH BOUNDARY CHECK (READ ONLY)',
        f'Generated: {datetime.now().isoformat(timespec="seconds")}',
        'This report is NOT a source of clinical dosing or a prescription.',
        f'Database found: {db.is_file()}',
        '',
    ]
    if not db.is_file():
        return '\n'.join(lines + ['ERROR: SQLite book database not found. Run from maghz.'])
    try:
        with sqlite3.connect(db.as_uri() + '?mode=ro', uri=True, timeout=8) as con:
            con.row_factory = sqlite3.Row
            for drug, anchor in PROBES:
                lines += [f'--- {drug.upper()} (starting anchor {anchor}) ---']
                record = con.execute('''SELECT c.id, c.book_id, c.page_start, c.text,
                                               b.book_key, b.title
                                        FROM chunks c JOIN books b ON b.id = c.book_id
                                        WHERE c.id = ?''', (anchor,)).fetchone()
                if not record:
                    lines += ['Anchor missing from database.', '']
                    continue
                lines.append('Book ID verified: ' + ('yes' if 'plumb' in str(record['book_key']).lower() else 'NO - CHECK ID'))
                lines.append(f'Anchor page: {record["page_start"]}; anchor text length: {len(record["text"] or "")}')
                # Query chunks in original ingestion order for THIS book only; never inspect other books.
                rows = con.execute('''SELECT id, page_start, text
                                      FROM chunks WHERE book_id=? AND id>=?
                                      ORDER BY id LIMIT 70''', (record['book_id'], anchor)).fetchall()
                start_page = record['page_start']
                hits = []
                all_entries = []
                section_hits = []
                seen_pages = set()
                for pos, row in enumerate(rows):
                    page = row['page_start']
                    seen_pages.add(str(page))
                    txt = row['text'] or ''
                    for m in ENTRY_RE.finditer(txt):
                        all_entries.append((pos, row['id'], page, m.group(1).lower(), tiny_context(txt, m.start(), m.end())))
                    for m in DOSAGE_RE.finditer(txt):
                        hits.append((pos, row['id'], page, tiny_context(txt, m.start(), m.end())))
                    for m in SECTIONS_RE.finditer(txt):
                        section_hits.append((pos, row['id'], page, m.group().lower()))
                lines.append(f'Forward chunks inspected: {len(rows)}; pages seen: {", ".join(sorted(seen_pages)[:18])}')
                lines.append(f'Possible drug-entry headings: {len(all_entries)}')
                for pos, cid, page, other, context in all_entries[:14]:
                    lines.append(f'  entry at +{pos} / chunk {cid} / p.{page}: name={other}; heading={context}')
                lines.append(f'Dosage-word occurrences: {len(hits)} (NOT verified as drug-specific)')
                for pos, cid, page, context in hits[:16]:
                    lines.append(f'  dosage word at +{pos} / chunk {cid} / p.{page}: {context}')
                lines.append(f'Other labeled section occurrences: {len(section_hits)}')
                lines.append('  earliest labels: ' + ', '.join(f'{s} @chunk {cid}' for _, cid, _, s in section_hits[:12]))
                # Make the first 27 vs 70 comparison explicit: was previous scan simply too short?
                later_dosage = [(pos, cid, pg) for pos, cid, pg, _ in hits if pos >= 27]
                lines.append(f'Dosage word locations after initial 27 chunks: {later_dosage[:12]}')
                next_entry = [(pos,cid,page,other) for pos,cid,page,other,_ in all_entries
                              if other != drug and pos > 0]
                lines.append(f'Potential OTHER drug headings after anchor: {next_entry[:8]}')
                lines.append('NOTE: A dosage word after a different drug heading must NOT be assigned to this drug.')
                lines.append('')
    except Exception as exc:
        lines += [f'ERROR: {type(exc).__name__}: {str(exc)[:200]}']
    return '\n'.join(lines) + '\n'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', type=Path, default=None)
    args = parser.parse_args()
    result = report((args.db or db_path()).expanduser().resolve())
    OUT.write_text(result, encoding='utf-8')
    print(result)
    print(f'\nReport saved to: {OUT}')

if __name__ == '__main__':
    main()
