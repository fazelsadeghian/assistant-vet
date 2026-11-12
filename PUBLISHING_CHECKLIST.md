# Assistant Vet — GitHub publishing checklist

This is an **organized draft**, not a validated ready-to-run release. Sources were reorganized without executing clinical logic or AI calls.

- [x] Restore `backend/app/providers/ollama.py`, `base.py` and `__init__.py` from the separately uploaded provider files (syntax checked, **not** runtime tested).
- [ ] Add the remaining Flutter scaffolding and declared assets from your working project.
- [ ] Supply the missing Dockerfile or remove/replace the incomplete Compose configuration.
- [ ] Validate `uvicorn app.main:app` starts and the `/health` endpoint responds.
- [ ] Validate `flutter pub get`, `flutter analyze` and device builds.
- [ ] Add Python and Flutter tests; avoid relying only on static parsing.
- [ ] Confirm authentication and authorization for exposed backend routes before hosting publicly.
- [ ] Restrict local file path access in PDF-ingestion routes before exposing the API.
- [ ] Check Supabase row-level security, credentials, URLs and client/server privileges.
- [ ] Remove or anonymize any real animal/pet-owner clinical records; exclude local databases.
- [ ] Check licenses of papers, textbooks, datasets and other included assets.
- [ ] Keep raw textbook extracts and diagnostic reports with copied book passages out of public repositories.
- [ ] Choose and add a real open-source LICENSE; add contributor guidance if appropriate.
- [ ] Add a screenshot and a short demonstration of the running application (optional but useful).
- [ ] Describe what currently works, what needs validation, and your maintainer role honestly.

The supplied original RAR contained development backup files. They were intentionally excluded from this draft.
