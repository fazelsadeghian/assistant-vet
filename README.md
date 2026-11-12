# Assistant Vet

**Status:** public-source preparation draft. This archive contains Python backend and Flutter UI code supplied for repository preparation, but is **not a complete, verified runnable distribution**.

Assistant Vet is an experimental veterinary decision-support application. It combines a Flutter user interface with a Python / FastAPI backend for structured case analysis, veterinary knowledge retrieval, research literature search, prescription workflow review, and equine reproduction-related interfaces. The backend includes integration points for a locally hosted AI model (Ollama). The source also includes a Supabase-based account flow in the Flutter application.

## Repository layout

- `backend/app/main.py` — FastAPI endpoints (`/health`, `/analyze-case`, evidence, knowledge and prescription workflows).
- `backend/app/services/` — orchestration, evidence search, knowledge indexing, treatment and prescription-related workflows.
- `backend/app/providers/` — `OllamaProvider` implementation, provider interface, and package initializer supplied separately and now included.
- `backend/requirements.txt` — declared Python package requirements.
- `frontend/lib/` — Flutter screens, case workflow, prescription workspace, and equine-reproduction UI.
- `frontend/pubspec.yaml` — Flutter package declaration.
- `docs/` — the original Persian overview supplied with the project. Diagnostic reports with excerpts from licensed veterinary books were excluded from this public-source draft.

## Project capabilities visible in source

- Structured canine and feline patient case input
- Rule-based clinical checks and AI orchestration
- Research retrieval via PubMed and Europe PMC
- PDF text ingestion and local knowledge indexing
- Prescription evidence review, quotes and price lookup workflows
- Flutter case management, analysis and veterinary reproduction screens

These are *source-level features*, not claims of validated clinical performance, live service availability, or production readiness.

## Important: files still needed for a complete build

1. The provider files (`ollama.py`, `base.py`, `__init__.py`) were added from a separate upload. They passed Python syntax parsing, but Ollama integration and end-to-end backend execution remain untested.
2. Flutter project/platform scaffolding (`android/`, `ios/`, `web/`, etc. as applicable) and the declared `frontend/assets/` directory were not in the supplied archive.
3. `Dockerfile`: referenced by the provided Docker Compose configuration, but missing. Docker Compose is not presently ready to build.
4. Automated tests and a suitable open-source license are not present in this snapshot.

## Local development (after remaining missing files are restored)

Python backend (run from `backend/`):

```bash
python -m venv .venv
# Activate the environment for your OS, then:
pip install -r requirements.txt
cp .env.example .env  # or create .env on Windows
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

The backend references a locally hosted Ollama-compatible service; verify the configuration and model availability before starting. These commands have **not** been verified against this partial source bundle.

Flutter frontend: restore your complete original Flutter project directory, then run `flutter pub get` and `flutter run`. The API client currently points to `http://127.0.0.1:8000`; adjust your development setup for simulators or physical devices.

## Safety, privacy and license

**Not for unsupervised clinical use.** Any clinical output, drug dose, contraindication or treatment suggestion must be reviewed by a qualified veterinarian and validated against trusted sources. Do not publish patient information, clinical records, private credentials, database dumps, proprietary textbooks, or API secrets. Public Supabase publishable keys are different from private service-role keys; still audit configuration and access policies before publishing.

No license has been chosen for this draft. Choose and add an appropriate open-source `LICENSE` file **before** presenting the repository as open source. Do not assume third-party data and text share that license.

See [`PUBLISHING_CHECKLIST.md`](PUBLISHING_CHECKLIST.md) for pre-release checks.
