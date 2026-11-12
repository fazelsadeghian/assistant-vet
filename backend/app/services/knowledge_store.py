import heapq
import math
import os
import re
import sqlite3
import struct
import threading
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence

import httpx
from dotenv import load_dotenv

try:
    import numpy as np
except Exception:
    np = None

from app.config import settings

load_dotenv()

SCHEMA_VERSION = "knowledge-hybrid-0.3.0-batched-exact"


class KnowledgeStore:
    def __init__(self, db_path: Path | None = None) -> None:
        self.db_path = db_path or settings.knowledge_db
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.ollama_base_url = os.getenv(
            "OLLAMA_BASE_URL", "http://127.0.0.1:11434"
        ).rstrip("/")
        self.embed_model = os.getenv("OLLAMA_EMBED_MODEL", "").strip()
        self.embed_num_gpu = int(os.getenv("OLLAMA_EMBED_NUM_GPU", "0"))
        self.embed_keep_alive = os.getenv("OLLAMA_EMBED_KEEP_ALIVE", "30m")

        self._semantic_cache_lock = threading.Lock()
        self._semantic_cache_model: str | None = None
        self._semantic_chunk_ids = None
        self._semantic_matrix = None
        self._semantic_dims: int | None = None

        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        con = sqlite3.connect(self.db_path)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys = ON")
        con.execute("PRAGMA journal_mode = WAL")
        return con

    @staticmethod
    def _ensure_column(
        con: sqlite3.Connection,
        table: str,
        column: str,
        definition: str,
    ) -> None:
        columns = {
            row["name"]
            for row in con.execute(f"PRAGMA table_info({table})").fetchall()
        }
        if column not in columns:
            con.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")

    def _init_db(self) -> None:
        with self._connect() as con:
            con.execute(
                "CREATE TABLE IF NOT EXISTS books ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                "book_key TEXT UNIQUE NOT NULL,"
                "title TEXT NOT NULL,"
                "edition TEXT,"
                "year INTEGER,"
                "source_path TEXT)"
            )
            con.execute(
                "CREATE TABLE IF NOT EXISTS chunks ("
                "id INTEGER PRIMARY KEY AUTOINCREMENT,"
                "book_id INTEGER NOT NULL,"
                "page_start INTEGER,"
                "page_end INTEGER,"
                "chapter TEXT,"
                "section TEXT,"
                "text TEXT NOT NULL,"
                "FOREIGN KEY(book_id) REFERENCES books(id))"
            )
            self._ensure_column(con, "chunks", "printed_page_start", "INTEGER")
            self._ensure_column(con, "chunks", "printed_page_end", "INTEGER")

            con.execute(
                "CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts "
                "USING fts5(text, content='chunks', content_rowid='id')"
            )
            con.execute(
                "CREATE TRIGGER IF NOT EXISTS chunks_ai "
                "AFTER INSERT ON chunks BEGIN "
                "INSERT INTO chunk_fts(rowid, text) VALUES (new.id, new.text); "
                "END;"
            )
            con.execute(
                "CREATE TRIGGER IF NOT EXISTS chunks_ad "
                "AFTER DELETE ON chunks BEGIN "
                "INSERT INTO chunk_fts(chunk_fts, rowid, text) "
                "VALUES('delete', old.id, old.text); "
                "END;"
            )
            con.execute(
                "CREATE TRIGGER IF NOT EXISTS chunks_au "
                "AFTER UPDATE OF text ON chunks BEGIN "
                "INSERT INTO chunk_fts(chunk_fts, rowid, text) "
                "VALUES('delete', old.id, old.text); "
                "INSERT INTO chunk_fts(rowid, text) VALUES (new.id, new.text); "
                "END;"
            )
            con.execute(
                "CREATE TABLE IF NOT EXISTS chunk_embeddings ("
                "chunk_id INTEGER PRIMARY KEY,"
                "model TEXT NOT NULL,"
                "dims INTEGER NOT NULL,"
                "vector BLOB NOT NULL,"
                "FOREIGN KEY(chunk_id) REFERENCES chunks(id) ON DELETE CASCADE)"
            )
            con.execute(
                "CREATE INDEX IF NOT EXISTS idx_chunks_book_id "
                "ON chunks(book_id)"
            )
            con.execute(
                "CREATE INDEX IF NOT EXISTS idx_embeddings_model "
                "ON chunk_embeddings(model)"
            )

    def upsert_book(
        self,
        *,
        book_key: str,
        title: str,
        edition: str | None,
        year: int | None,
        source_path: str | None,
    ) -> int:
        with self._connect() as con:
            con.execute(
                "INSERT INTO books(book_key,title,edition,year,source_path) "
                "VALUES (?,?,?,?,?) "
                "ON CONFLICT(book_key) DO UPDATE SET "
                "title=excluded.title,"
                "edition=excluded.edition,"
                "year=excluded.year,"
                "source_path=excluded.source_path",
                (book_key, title, edition, year, source_path),
            )
            row = con.execute(
                "SELECT id FROM books WHERE book_key=?",
                (book_key,),
            ).fetchone()
            return int(row["id"])

    @staticmethod
    def _clean_heading(value: str | None) -> str | None:
        if not value:
            return None
        value = re.sub(r"\s+", " ", value).strip(" \t\r\n•|-")
        return value[:240] if value else None

    @classmethod
    def _detect_section(cls, text: str) -> str | None:
        match = re.search(
            r"\bSECTION\s+([IVXLC]+|\d+)\b([^\n\r]{0,120})",
            text,
            flags=re.IGNORECASE,
        )
        if not match:
            return None
        suffix = re.split(
            r"\b(?:CHAPTER|eBooks\.Health\.Elsevier\.com)\b",
            match.group(2),
            maxsplit=1,
            flags=re.IGNORECASE,
        )[0]
        return cls._clean_heading(f"Section {match.group(1)} {suffix}")

    @classmethod
    def _detect_chapter(cls, text: str) -> str | None:
        match = re.search(r"\bCHAPTER\s+(\d{1,4})\b", text, flags=re.IGNORECASE)
        if match:
            return f"Chapter {match.group(1)}"
        match = re.search(r"\bChapter\s+(\d{1,4})\b", text, flags=re.IGNORECASE)
        if match:
            return f"Chapter {match.group(1)}"
        return None

    @staticmethod
    def _detect_printed_page(text: str) -> int | None:
        patterns = [
            r"\b(?:Chapter\s+\d+\s*[•|:-].{0,120}?)\s+(\d{1,4})\s+eBooks\.Health\.Elsevier\.com\b",
            r"\b(?:SECTION\s+[IVXLC\d]+.{0,120}?)\s+(\d{1,4})\s+eBooks\.Health\.Elsevier\.com\b",
        ]
        for pattern in patterns:
            match = re.search(pattern, text, flags=re.IGNORECASE)
            if match:
                value = int(match.group(1))
                if 1 <= value <= 5000:
                    return value
        return None

    def _enrich_chunks(
        self,
        chunks: Iterable[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        enriched: List[Dict[str, Any]] = []
        current_chapter: str | None = None
        current_section: str | None = None
        current_printed_page: int | None = None

        for raw in chunks:
            c = dict(raw)
            text = str(c.get("text") or "")

            detected_section = self._detect_section(text)
            if detected_section:
                current_section = detected_section

            detected_chapter = self._detect_chapter(text)
            if detected_chapter:
                current_chapter = detected_chapter

            detected_printed_page = self._detect_printed_page(text)
            if detected_printed_page is not None:
                current_printed_page = detected_printed_page

            c["chapter"] = self._clean_heading(c.get("chapter") or current_chapter)
            c["section"] = self._clean_heading(c.get("section") or current_section)

            if c.get("printed_page_start") is None:
                c["printed_page_start"] = current_printed_page
            if c.get("printed_page_end") is None:
                c["printed_page_end"] = c.get("printed_page_start")

            enriched.append(c)

        return enriched

    def replace_chunks(
        self,
        book_id: int,
        chunks: Iterable[Dict[str, Any]],
    ) -> None:
        prepared = self._enrich_chunks(chunks)
        inserted: List[tuple[int, str]] = []

        with self._connect() as con:
            old_ids = [
                int(row["id"])
                for row in con.execute(
                    "SELECT id FROM chunks WHERE book_id=?",
                    (book_id,),
                ).fetchall()
            ]

            if old_ids:
                placeholders = ",".join("?" for _ in old_ids)
                con.execute(
                    f"DELETE FROM chunk_embeddings WHERE chunk_id IN ({placeholders})",
                    old_ids,
                )

            con.execute("DELETE FROM chunks WHERE book_id=?", (book_id,))

            for c in prepared:
                cur = con.execute(
                    "INSERT INTO chunks("
                    "book_id,page_start,page_end,"
                    "printed_page_start,printed_page_end,"
                    "chapter,section,text"
                    ") VALUES (?,?,?,?,?,?,?,?)",
                    (
                        book_id,
                        c.get("page_start"),
                        c.get("page_end"),
                        c.get("printed_page_start"),
                        c.get("printed_page_end"),
                        c.get("chapter"),
                        c.get("section"),
                        c["text"],
                    ),
                )
                inserted.append((int(cur.lastrowid), str(c["text"])))

        if self.embed_model and inserted:
            self._embed_and_store(inserted)

        self._invalidate_semantic_cache()

    @staticmethod
    def _tokenize(query: str) -> List[str]:
        tokens = re.findall(r"[A-Za-z0-9_]+", query.lower())
        return [token for token in tokens if len(token) > 1][:32]

    def _lexical_search(self, query: str, limit: int) -> List[Dict[str, Any]]:
        tokens = self._tokenize(query)
        if not tokens:
            return []

        fts_query = " OR ".join(f'"{token}"' for token in tokens)

        with self._connect() as con:
            try:
                rows = con.execute(
                    "SELECT "
                    "c.id AS chunk_id,"
                    "b.book_key,b.title,b.edition,b.year,"
                    "c.page_start,c.page_end,"
                    "c.printed_page_start,c.printed_page_end,"
                    "c.chapter,c.section,"
                    "c.text,"
                    "snippet(chunk_fts,0,'[',']',' … ',38) AS snippet,"
                    "bm25(chunk_fts) AS bm25_score "
                    "FROM chunk_fts "
                    "JOIN chunks c ON c.id=chunk_fts.rowid "
                    "JOIN books b ON b.id=c.book_id "
                    "WHERE chunk_fts MATCH ? "
                    "ORDER BY bm25_score "
                    "LIMIT ?",
                    (fts_query, max(limit, 1)),
                ).fetchall()
            except sqlite3.OperationalError:
                return []

        return [dict(row) for row in rows]

    @staticmethod
    def _pack_vector(vector: Sequence[float]) -> bytes:
        if not vector:
            return b""
        return struct.pack(f"<{len(vector)}f", *vector)

    @staticmethod
    def _unpack_vector(blob: bytes, dims: int) -> tuple[float, ...]:
        if not blob or dims <= 0:
            return tuple()
        return struct.unpack(f"<{dims}f", blob)

    def _embed_texts(
        self,
        texts: Sequence[str],
        timeout: float = 180.0,
    ) -> List[List[float]]:
        if not self.embed_model or not texts:
            return []

        body: Dict[str, Any] = {
            "model": self.embed_model,
            "input": list(texts),
            "keep_alive": self.embed_keep_alive,
            "options": {
                "num_gpu": self.embed_num_gpu,
            },
        }

        try:
            response = httpx.post(
                f"{self.ollama_base_url}/api/embed",
                json=body,
                timeout=timeout,
            )

            if response.status_code >= 400:
                response = httpx.post(
                    f"{self.ollama_base_url}/api/embed",
                    json={
                        "model": self.embed_model,
                        "input": list(texts),
                    },
                    timeout=timeout,
                )

            response.raise_for_status()
            payload = response.json()
            embeddings = payload.get("embeddings")
            if not isinstance(embeddings, list):
                return []

            return [
                [float(value) for value in vector]
                for vector in embeddings
                if isinstance(vector, list)
            ]
        except Exception:
            return []

    def _embed_and_store(
        self,
        rows: Sequence[tuple[int, str]],
        batch_size: int = 16,
    ) -> int:
        if not self.embed_model:
            return 0

        stored = 0

        for start in range(0, len(rows), batch_size):
            batch = rows[start:start + batch_size]
            texts = [text for _, text in batch]
            embeddings = self._embed_texts(texts)

            if len(embeddings) != len(batch):
                continue

            with self._connect() as con:
                for (chunk_id, _), vector in zip(batch, embeddings):
                    if not vector:
                        continue
                    con.execute(
                        "INSERT INTO chunk_embeddings(chunk_id,model,dims,vector) "
                        "VALUES (?,?,?,?) "
                        "ON CONFLICT(chunk_id) DO UPDATE SET "
                        "model=excluded.model,dims=excluded.dims,vector=excluded.vector",
                        (
                            chunk_id,
                            self.embed_model,
                            len(vector),
                            self._pack_vector(vector),
                        ),
                    )
                    stored += 1

        if stored:
            self._invalidate_semantic_cache()

        return stored

    def backfill_embeddings(
        self,
        *,
        book_key: str | None = None,
        batch_size: int = 16,
    ) -> Dict[str, Any]:
        if not self.embed_model:
            return {
                "ok": False,
                "message": "OLLAMA_EMBED_MODEL is not configured.",
                "embedded": 0,
            }

        sql = (
            "SELECT c.id AS chunk_id,c.text "
            "FROM chunks c "
            "JOIN books b ON b.id=c.book_id "
            "LEFT JOIN chunk_embeddings e "
            "ON e.chunk_id=c.id AND e.model=? "
            "WHERE e.chunk_id IS NULL "
        )
        params: List[Any] = [self.embed_model]

        if book_key:
            sql += "AND b.book_key=? "
            params.append(book_key)

        sql += "ORDER BY c.id"

        with self._connect() as con:
            rows = con.execute(sql, params).fetchall()

        pending = [(int(row["chunk_id"]), str(row["text"])) for row in rows]
        embedded = self._embed_and_store(pending, batch_size=batch_size)

        return {
            "ok": embedded == len(pending),
            "model": self.embed_model,
            "pending_before": len(pending),
            "embedded": embedded,
        }

    @staticmethod
    def _cosine_similarity(a: Sequence[float], b: Sequence[float]) -> float:
        if not a or not b or len(a) != len(b):
            return -1.0

        dot = 0.0
        norm_a = 0.0
        norm_b = 0.0

        for x, y in zip(a, b):
            dot += x * y
            norm_a += x * x
            norm_b += y * y

        if norm_a <= 0.0 or norm_b <= 0.0:
            return -1.0

        return dot / math.sqrt(norm_a * norm_b)

    @staticmethod
    def _make_snippet(text: str, query: str, width: int = 360) -> str:
        compact = re.sub(r"\s+", " ", text).strip()
        if len(compact) <= width:
            return compact

        tokens = KnowledgeStore._tokenize(query)
        lower = compact.lower()
        positions = [lower.find(token) for token in tokens if lower.find(token) >= 0]
        center = min(positions) if positions else 0
        start = max(0, center - width // 3)
        end = min(len(compact), start + width)

        prefix = " … " if start > 0 else ""
        suffix = " … " if end < len(compact) else ""
        return prefix + compact[start:end] + suffix

    def _invalidate_semantic_cache(self) -> None:
        with self._semantic_cache_lock:
            self._semantic_cache_model = None
            self._semantic_chunk_ids = None
            self._semantic_matrix = None
            self._semantic_dims = None

    def _fetch_chunk_metadata(
        self,
        chunk_ids: Sequence[int],
    ) -> Dict[int, Dict[str, Any]]:
        ids = [int(x) for x in dict.fromkeys(chunk_ids)]
        if not ids:
            return {}

        placeholders = ",".join("?" for _ in ids)
        with self._connect() as con:
            rows = con.execute(
                "SELECT "
                "c.id AS chunk_id,"
                "b.book_key,b.title,b.edition,b.year,"
                "c.page_start,c.page_end,"
                "c.printed_page_start,c.printed_page_end,"
                "c.chapter,c.section,c.text "
                "FROM chunks c "
                "JOIN books b ON b.id=c.book_id "
                f"WHERE c.id IN ({placeholders})",
                ids,
            ).fetchall()

        return {
            int(row["chunk_id"]): dict(row)
            for row in rows
        }

    def _ensure_numpy_semantic_cache(self) -> bool:
        if np is None or not self.embed_model:
            return False

        if (
            self._semantic_cache_model == self.embed_model
            and self._semantic_chunk_ids is not None
            and self._semantic_matrix is not None
        ):
            return True

        with self._semantic_cache_lock:
            if (
                self._semantic_cache_model == self.embed_model
                and self._semantic_chunk_ids is not None
                and self._semantic_matrix is not None
            ):
                return True

            with self._connect() as con:
                rows = con.execute(
                    "SELECT chunk_id,dims,vector "
                    "FROM chunk_embeddings "
                    "WHERE model=? "
                    "ORDER BY chunk_id",
                    (self.embed_model,),
                ).fetchall()

            if not rows:
                return False

            dims = int(rows[0]["dims"])
            usable = [
                row for row in rows
                if int(row["dims"]) == dims
            ]
            if not usable or dims <= 0:
                return False

            matrix = np.empty(
                (len(usable), dims),
                dtype=np.float32,
            )
            chunk_ids = np.empty(
                len(usable),
                dtype=np.int64,
            )

            for index, row in enumerate(usable):
                vector = np.frombuffer(
                    row["vector"],
                    dtype="<f4",
                    count=dims,
                )
                if vector.size != dims:
                    return False
                matrix[index, :] = vector
                chunk_ids[index] = int(row["chunk_id"])

            block_size = 2048
            for start in range(0, len(matrix), block_size):
                block = matrix[start:start + block_size]
                norms = np.sqrt(
                    np.sum(block * block, axis=1)
                )
                norms[norms == 0.0] = 1.0
                block /= norms[:, None]

            self._semantic_cache_model = self.embed_model
            self._semantic_chunk_ids = chunk_ids
            self._semantic_matrix = matrix
            self._semantic_dims = dims
            return True

    def _semantic_search_many_numpy(
        self,
        queries: Sequence[str],
        query_vectors: Sequence[Sequence[float]],
        limit: int,
    ) -> List[List[Dict[str, Any]]]:
        if not self._ensure_numpy_semantic_cache():
            return []

        matrix = self._semantic_matrix
        chunk_ids = self._semantic_chunk_ids
        dims = int(self._semantic_dims or 0)

        if matrix is None or chunk_ids is None or dims <= 0:
            return []

        q = np.asarray(query_vectors, dtype=np.float32)
        if q.ndim != 2 or q.shape[1] != dims:
            return []

        norms = np.sqrt(np.sum(q * q, axis=1))
        norms[norms == 0.0] = 1.0
        q = q / norms[:, None]

        scores = matrix @ q.T
        n_rows = int(scores.shape[0])
        top_n = min(max(1, int(limit)), n_rows)

        selected_ids: List[List[int]] = []
        selected_scores: List[List[float]] = []
        union_ids: List[int] = []

        for q_index in range(len(queries)):
            column = scores[:, q_index]

            if top_n >= n_rows:
                indices = np.argsort(column)[::-1]
            else:
                partition = np.argpartition(
                    column,
                    n_rows - top_n,
                )[n_rows - top_n:]
                indices = partition[
                    np.argsort(column[partition])[::-1]
                ]

            ids = [
                int(chunk_ids[index])
                for index in indices[:top_n]
            ]
            vals = [
                float(column[index])
                for index in indices[:top_n]
            ]

            selected_ids.append(ids)
            selected_scores.append(vals)
            union_ids.extend(ids)

        metadata = self._fetch_chunk_metadata(union_ids)
        result_sets: List[List[Dict[str, Any]]] = []

        for query, ids, vals in zip(
            queries,
            selected_ids,
            selected_scores,
        ):
            rows: List[Dict[str, Any]] = []
            for chunk_id, similarity in zip(ids, vals):
                row = metadata.get(chunk_id)
                if not row:
                    continue
                rows.append(
                    {
                        "chunk_id": chunk_id,
                        "book_key": row["book_key"],
                        "title": row["title"],
                        "edition": row["edition"],
                        "year": row["year"],
                        "page_start": row["page_start"],
                        "page_end": row["page_end"],
                        "printed_page_start": row["printed_page_start"],
                        "printed_page_end": row["printed_page_end"],
                        "chapter": row["chapter"],
                        "section": row["section"],
                        "text": row["text"],
                        "semantic_score": similarity,
                    }
                )
            result_sets.append(rows)

        return result_sets

    def _semantic_search_many_python(
        self,
        queries: Sequence[str],
        query_vectors: Sequence[Sequence[float]],
        limit: int,
    ) -> List[List[Dict[str, Any]]]:
        if not query_vectors:
            return [[] for _ in queries]

        q_norms: List[float] = []
        for vector in query_vectors:
            q_norms.append(
                math.sqrt(sum(value * value for value in vector))
            )

        heaps: List[List[tuple[float, int]]] = [
            [] for _ in queries
        ]

        with self._connect() as con:
            rows = con.execute(
                "SELECT chunk_id,dims,vector "
                "FROM chunk_embeddings "
                "WHERE model=?",
                (self.embed_model,),
            ).fetchall()

        for row in rows:
            dims = int(row["dims"])
            vector = self._unpack_vector(
                row["vector"],
                dims,
            )
            if not vector:
                continue

            row_norm = math.sqrt(
                sum(value * value for value in vector)
            )
            if row_norm <= 0.0:
                continue

            chunk_id = int(row["chunk_id"])

            for q_index, query_vector in enumerate(query_vectors):
                if (
                    len(query_vector) != dims
                    or q_norms[q_index] <= 0.0
                ):
                    continue

                dot = sum(
                    x * y
                    for x, y in zip(
                        query_vector,
                        vector,
                    )
                )
                similarity = dot / (
                    q_norms[q_index] * row_norm
                )

                heap = heaps[q_index]
                key = (similarity, chunk_id)
                if len(heap) < limit:
                    heapq.heappush(heap, key)
                elif similarity > heap[0][0]:
                    heapq.heapreplace(heap, key)

        ranked_pairs: List[List[tuple[float, int]]] = [
            sorted(heap, key=lambda x: x[0], reverse=True)
            for heap in heaps
        ]
        union_ids = [
            chunk_id
            for pairs in ranked_pairs
            for _, chunk_id in pairs
        ]
        metadata = self._fetch_chunk_metadata(union_ids)

        result_sets: List[List[Dict[str, Any]]] = []
        for pairs in ranked_pairs:
            result: List[Dict[str, Any]] = []
            for similarity, chunk_id in pairs:
                row = metadata.get(chunk_id)
                if not row:
                    continue
                result.append(
                    {
                        "chunk_id": chunk_id,
                        "book_key": row["book_key"],
                        "title": row["title"],
                        "edition": row["edition"],
                        "year": row["year"],
                        "page_start": row["page_start"],
                        "page_end": row["page_end"],
                        "printed_page_start": row["printed_page_start"],
                        "printed_page_end": row["printed_page_end"],
                        "chapter": row["chapter"],
                        "section": row["section"],
                        "text": row["text"],
                        "semantic_score": similarity,
                    }
                )
            result_sets.append(result)

        return result_sets

    def _semantic_search_many(
        self,
        queries: Sequence[str],
        limit: int,
    ) -> List[List[Dict[str, Any]]]:
        clean_queries = [
            str(query).strip()
            for query in queries
        ]
        if not self.embed_model or not clean_queries:
            return [[] for _ in clean_queries]

        embedded = self._embed_texts(clean_queries)
        if len(embedded) != len(clean_queries):
            return [[] for _ in clean_queries]

        if np is not None:
            accelerated = self._semantic_search_many_numpy(
                clean_queries,
                embedded,
                limit,
            )
            if len(accelerated) == len(clean_queries):
                return accelerated

        return self._semantic_search_many_python(
            clean_queries,
            embedded,
            limit,
        )

    def _semantic_search(
        self,
        query: str,
        limit: int,
    ) -> List[Dict[str, Any]]:
        result_sets = self._semantic_search_many(
            [query],
            limit,
        )
        return result_sets[0] if result_sets else []

    def semantic_status(self) -> Dict[str, Any]:
        with self._connect() as con:
            chunk_count = int(
                con.execute("SELECT COUNT(*) AS n FROM chunks").fetchone()["n"]
            )
            if self.embed_model:
                embedded_count = int(
                    con.execute(
                        "SELECT COUNT(*) AS n FROM chunk_embeddings WHERE model=?",
                        (self.embed_model,),
                    ).fetchone()["n"]
                )
            else:
                embedded_count = 0

        return {
            "schema_version": SCHEMA_VERSION,
            "embedding_model": self.embed_model or None,
            "semantic_enabled": bool(self.embed_model),
            "chunks": chunk_count,
            "embedded_chunks": embedded_count,
        }

    def _fuse_search_results(
        self,
        query: str,
        lexical: List[Dict[str, Any]],
        semantic: List[Dict[str, Any]],
        limit: int,
    ) -> List[Dict[str, Any]]:
        fused: Dict[int, Dict[str, Any]] = {}
        rrf_k = 60.0

        for rank, row in enumerate(lexical, start=1):
            chunk_id = int(row["chunk_id"])
            item = fused.setdefault(
                chunk_id,
                {
                    **row,
                    "hybrid_score": 0.0,
                    "lexical_rank": None,
                    "semantic_rank": None,
                    "semantic_score": None,
                },
            )
            item["lexical_rank"] = rank
            item["hybrid_score"] += 1.0 / (rrf_k + rank)

        for rank, row in enumerate(semantic, start=1):
            chunk_id = int(row["chunk_id"])
            item = fused.setdefault(
                chunk_id,
                {
                    **row,
                    "snippet": self._make_snippet(
                        str(row.get("text") or ""),
                        query,
                    ),
                    "bm25_score": None,
                    "hybrid_score": 0.0,
                    "lexical_rank": None,
                    "semantic_rank": None,
                },
            )
            item["semantic_rank"] = rank
            item["semantic_score"] = row.get("semantic_score")
            item["hybrid_score"] += 1.20 / (rrf_k + rank)

        normalized_query = " ".join(self._tokenize(query))
        if normalized_query:
            for item in fused.values():
                text_value = str(item.get("text") or "").lower()
                normalized_text = " ".join(self._tokenize(text_value))
                if normalized_query in normalized_text:
                    item["hybrid_score"] += 0.02

        for item in fused.values():
            section_value = str(
                item.get("section") or ""
            ).strip().lower()
            text_value = str(item.get("text") or "")
            snippet_value = str(item.get("snippet") or "")

            is_reference_section = section_value in {
                "references",
                "selected references",
                "further reading",
                "bibliography",
            }

            reference_like = bool(
                re.search(
                    r"(?:^|\s)\d{1,3}\.\s+[A-Z][A-Za-z'`\-]+",
                    text_value,
                )
                and re.search(
                    r"\b(?:J Vet|Vet J|J Small Anim Pract|JVIM|doi|et al\.)\b",
                    text_value + " " + snippet_value,
                    flags=re.IGNORECASE,
                )
            )

            if is_reference_section:
                item["hybrid_score"] *= 0.45
            elif reference_like:
                item["hybrid_score"] *= 0.72

        ranked = sorted(
            fused.values(),
            key=lambda item: float(item["hybrid_score"]),
            reverse=True,
        )[:limit]

        results: List[Dict[str, Any]] = []

        for item in ranked:
            results.append(
                {
                    "chunk_id": item["chunk_id"],
                    "book_key": item["book_key"],
                    "title": item["title"],
                    "edition": item["edition"],
                    "year": item["year"],
                    "page_start": item["page_start"],
                    "page_end": item["page_end"],
                    "printed_page_start": item.get("printed_page_start"),
                    "printed_page_end": item.get("printed_page_end"),
                    "chapter": item["chapter"],
                    "section": item["section"],
                    "snippet": item.get("snippet")
                    or self._make_snippet(
                        str(item.get("text") or ""),
                        query,
                    ),
                    "score": round(
                        float(item["hybrid_score"]),
                        8,
                    ),
                    "lexical_rank": item.get("lexical_rank"),
                    "semantic_rank": item.get("semantic_rank"),
                    "semantic_score": (
                        round(float(item["semantic_score"]), 6)
                        if item.get("semantic_score") is not None
                        else None
                    ),
                }
            )

        return results

    def search_many(
        self,
        queries: Sequence[str],
        limit: int = 8,
    ) -> List[List[Dict[str, Any]]]:
        clean_queries = [
            (query or "").strip()
            for query in queries
        ]

        limit = max(1, min(int(limit), 50))
        candidate_limit = max(40, limit * 8)

        lexical_sets = [
            self._lexical_search(query, candidate_limit)
            if query else []
            for query in clean_queries
        ]

        semantic_sets = self._semantic_search_many(
            clean_queries,
            candidate_limit,
        )

        if len(semantic_sets) != len(clean_queries):
            semantic_sets = [
                [] for _ in clean_queries
            ]

        return [
            self._fuse_search_results(
                query,
                lexical,
                semantic,
                limit,
            )
            if query else []
            for query, lexical, semantic in zip(
                clean_queries,
                lexical_sets,
                semantic_sets,
            )
        ]

    def search(
        self,
        query: str,
        limit: int = 8,
    ) -> List[Dict[str, Any]]:
        result_sets = self.search_many(
            [query],
            limit=limit,
        )
        return result_sets[0] if result_sets else []
