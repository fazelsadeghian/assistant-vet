"""Read-only diagnostics for Assistant Vet's local textbook retrieval and Ollama.

This script does NOT create or modify book records, prescriptions, cases, or
application configuration. It never uploads patient or book text.
"""
from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
# Run this script from maghz with the virtual environment used by the backend.
PROJECT = Path.cwd()
OUTPUT = PROJECT / 'AssistantVet_Evidence_Diagnostic_report.txt'
OUTPUT_JSON = PROJECT / 'AssistantVet_Evidence_Diagnostic_report.json'


def read_db_path() -> Path:
    try:
        from app.config import settings
        return Path(settings.knowledge_db).expanduser().resolve()
    except Exception:
        return (PROJECT / 'data' / 'knowledge' / 'assistant_vet_knowledge.sqlite3').resolve()


def db_diagnostics(path: Path) -> dict:
    info = {'db_exists': path.is_file(), 'db_file': str(path),
            'database_read_only': True}
    if not path.is_file():
        return info
    try:
        db = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=8)
        db.row_factory = sqlite3.Row
        try:
            tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type IN ('table','view')")}
            for table in ('books', 'chunks', 'chunk_embeddings'):
                if table in tables:
                    info[table + '_count'] = int(db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0])
            if 'books' in tables and 'chunks' in tables:
                info['books_by_chunk_count'] = [dict(row) for row in db.execute(
                    'SELECT b.title AS title, b.book_key AS book_key, COUNT(c.id) AS chunks '
                    'FROM books b LEFT JOIN chunks c ON c.book_id=b.id '
                    'GROUP BY b.id ORDER BY chunks DESC LIMIT 18'
                )]
                info['chunk_text_length'] = dict(db.execute(
                    'SELECT MIN(LENGTH(text)) AS min_chars, '
                    'ROUND(AVG(LENGTH(text))) AS avg_chars, '
                    'MAX(LENGTH(text)) AS max_chars FROM chunks'
                ).fetchone())
            if 'chunk_embeddings' in tables:
                info['embeddings_by_model'] = [dict(row) for row in db.execute(
                    'SELECT model, COUNT(*) AS chunks FROM chunk_embeddings '
                    'GROUP BY model ORDER BY chunks DESC LIMIT 6'
                )]
            # The next words are index-presence controls, NOT drug recommendations.
            probes = ('vomiting', 'gastritis', 'antiemetic', 'dose', 'maropitant',
                      'ondansetron', 'metoclopramide', 'omeprazole')
            info['index_control_terms_not_prescriptions'] = {}
            if 'chunk_fts' in tables:
                for word in probes:
                    try:
                        count = db.execute('SELECT COUNT(*) FROM chunk_fts WHERE chunk_fts MATCH ?', (word,)).fetchone()[0]
                        info['index_control_terms_not_prescriptions'][word] = int(count)
                    except sqlite3.Error as error:
                        info['index_control_terms_not_prescriptions'][word] = 'lookup_error: ' + str(error)[:120]
            if 'books' in tables and 'chunks' in tables:
                # Metadata only; never copy copyrighted book passages into the report.
                info['sample_search_metadata'] = [dict(row) for row in db.execute(
                    "SELECT b.title, c.chapter, c.page_start, LENGTH(c.text) AS chars "
                    "FROM chunks c JOIN books b ON b.id=c.book_id "
                    "WHERE lower(c.text) LIKE '%antiemetic%' LIMIT 5"
                )]
        finally:
            db.close()
    except Exception as error:
        info['error'] = type(error).__name__ + ': ' + str(error)[:250]
    return info


def retrieval_diagnostics() -> dict:
    # Run the existing retrieval algorithm under an OS-enforced deadline.
    # This avoids silently leaving a long-running async search thread behind.
    code = '''import json,time
from app.services.knowledge_store import KnowledgeStore
t=time.monotonic()
s=KnowledgeStore()
queries=['canine acute vomiting gastritis treatment','canine acute vomiting antiemetic pharmacologic management']
rows=s.search_many(queries,limit=5)
print(json.dumps({'elapsed_seconds':round(time.monotonic()-t,2),'counts':[len(r) for r in rows], 'top_matches':[[{'title':x.get('title'), 'chapter':x.get('chapter'),'page_start':x.get('page_start'),'book_key':x.get('book_key'), 'chunk_id':x.get('chunk_id')} for x in result[:3]] for result in rows]},ensure_ascii=False))'''
    began = time.monotonic()
    try:
        run = subprocess.run([sys.executable, '-c', code], cwd=str(PROJECT),
                             capture_output=True, text=True, encoding='utf-8',
                             errors='replace', timeout=35, check=False)
        info = {'wall_seconds': round(time.monotonic()-began, 2),
                'exit_code': run.returncode}
        if run.returncode == 0:
            try:
                info['details'] = json.loads(run.stdout.strip().splitlines()[-1])
            except (ValueError, IndexError):
                info['error'] = 'Retrieval returned no parsable summary.'
        else:
            info['error'] = (run.stderr or run.stdout)[-400:]
        return info
    except subprocess.TimeoutExpired:
        return {'timed_out': True, 'wall_seconds': round(time.monotonic()-began, 2),
                'note': 'Local book search exceeded the 35 second diagnostic cap.'}
    except Exception as error:
        return {'error': type(error).__name__ + ': ' + str(error)[:160]}


def ollama_diagnostics() -> dict:
    base = os.environ.get('OLLAMA_BASE_URL', 'http://127.0.0.1:11434').rstrip('/')
    model = os.environ.get('OLLAMA_MODEL', 'qwen3:8b') or 'qwen3:8b'
    info = {'model_requested': model}
    try:
        with urllib.request.urlopen(base + '/api/tags', timeout=5) as resp:
            raw = json.load(resp)
        names = [v.get('name','') for v in raw.get('models', []) if isinstance(v, dict)]
        info['ollama_reachable'] = True
        info['model_installed'] = model in names
    except Exception as error:
        info.update({'ollama_reachable': False, 'error': str(error)[:200]})
        return info
    # Small model benchmark; no case information or book text is sent.
    req = urllib.request.Request(base + '/api/generate',
        data=json.dumps({'model': model, 'stream': False, 'think': False,
          'prompt': 'Return exactly this JSON: {"ok":true}',
          'format': 'json', 'options': {'temperature': 0, 'num_predict': 45, 'num_ctx': 1024}}).encode(),
        headers={'Content-Type':'application/json'}, method='POST')
    t = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=35) as resp:
            out = json.load(resp)
        info.update({'small_request_wall_seconds': round(time.monotonic()-t, 2),
                     'small_request_completed': True,
                     'eval_count': out.get('eval_count'),
                     'prompt_eval_count': out.get('prompt_eval_count'),
                     'ollama_total_seconds': round((out.get('total_duration') or 0)/1e9, 2),
                     'small_response_parsable': bool(out.get('response'))})
    except Exception as error:
        info.update({'small_request_completed': False,
                     'small_request_wall_seconds': round(time.monotonic()-t, 2),
                     'error': type(error).__name__ + ': ' + str(error)[:180]})
    return info


def write_report(data: dict) -> None:
    OUTPUT_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    db = data['database']; ret = data['retrieval']; oll = data['ollama']
    lines = [
      'ASSISTANT VET — READ-ONLY EVIDENCE DIAGNOSTIC',
      'Generated: ' + data['created_at'],
      'No case, book, account, prescription or backend settings were changed.',
      '',
      'DATABASE',
      'Database present: ' + str(db.get('db_exists')),
      'Books: ' + str(db.get('books_count', '?')),
      'Chunks: ' + str(db.get('chunks_count', '?')),
      'Embedded chunks: ' + str(db.get('chunk_embeddings_count', '?')),
      'Chunk lengths: ' + str(db.get('chunk_text_length', {})),
      'Book counts: ' + ', '.join(str(b.get('book_key')) + '=' + str(b.get('chunks')) for b in db.get('books_by_chunk_count', [])[:10]),
      'Index control word counts (not treatment recommendations): ' + str(db.get('index_control_terms_not_prescriptions', {})),
      'Database error: ' + str(db.get('error', 'none')),
      '',
      'RETRIEVAL',
      'Elapsed: ' + str(ret.get('wall_seconds', '?')) + ' seconds',
      'Timed out: ' + str(ret.get('timed_out', False)),
      'Matches: ' + str(ret.get('details', {}).get('counts', [])),
      'Top result metadata: ' + json.dumps(ret.get('details', {}).get('top_matches', []), ensure_ascii=False),
      'Error: ' + str(ret.get('error', 'none')),
      '',
      'OLLAMA',
      'Model: ' + str(oll.get('model_requested')),
      'Connected: ' + str(oll.get('ollama_reachable')),
      'Model installed: ' + str(oll.get('model_installed')),
      'Small generation completed: ' + str(oll.get('small_request_completed')),
      'Small generation seconds: ' + str(oll.get('small_request_wall_seconds', '?')),
      'Ollama server generation seconds: ' + str(oll.get('ollama_total_seconds', '?')),
      'Error: ' + str(oll.get('error', 'none')),
      '',
      'This diagnostic does NOT evaluate treatment efficacy or clinical appropriateness.'
    ]
    OUTPUT.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main() -> int:
    print('Assistant Vet evidence diagnostics (read-only).')
    dbpath = read_db_path()
    print('1/3 Checking local textbook index...', flush=True)
    db = db_diagnostics(dbpath)
    print('2/3 Measuring source retrieval (max 35 s)...', flush=True)
    retrieval = retrieval_diagnostics() if db.get('db_exists') else {'error':'No knowledge database found'}
    print('3/3 Checking local qwen3:8b response (max 35 s)...', flush=True)
    ollama = ollama_diagnostics()
    data = {'created_at': datetime.now().isoformat(timespec='seconds'),
            'database':db, 'retrieval':retrieval, 'ollama':ollama}
    write_report(data)
    print('DONE. Diagnostic report: ' + str(OUTPUT))
    print('Please share only AssistantVet_Evidence_Diagnostic_report.txt with ChatGPT.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
