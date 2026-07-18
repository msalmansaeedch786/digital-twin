# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A serverless **RAG "digital twin"** — a chat avatar that answers questions about Muhammad Salman in the first person, using only ingested facts (no hallucination). The stack is 100% Infrastructure-as-Code on AWS: Bedrock (Titan embeddings v2 + Nova Lite LLM), RDS PostgreSQL with `pgvector`, Lambda, API Gateway, and a Next.js frontend on Amplify. Region is `eu-central-1`; Lambdas run `arm64`.

## Architecture (the parts that span files)

Two independent Lambdas plus a frontend, all provisioned by Terraform:

1. **API Lambda** — [lambdas/api/main.py](lambdas/api/main.py). FastAPI wrapped by Mangum. Serves `/chat`, `/health`, `/warmup`. Builds a LangChain history-aware RAG chain: rewrite query → embed → `pgvector` similarity search (`k=5`, collection `digital_twin_docs`) → generate. The `AIEngine` singleton is initialized once per warm container; an EventBridge ping to `/warmup` every 5 min keeps it hot. DB credentials come from Secrets Manager (cached 15 min in-memory), never hardcoded.
2. **Ingestion Lambda** — [lambdas/ingestion/lambda_function.py](lambdas/ingestion/lambda_function.py). Triggered by `s3:ObjectCreated` on the knowledge-base bucket. Downloads the file (with path-traversal-safe filename sanitization + extension allowlist), chunks (1000 chars / 200 overlap), embeds, and writes to the same `pgvector` collection.
3. **Frontend** — Next.js App Router in [frontend/src/app/](frontend/src/app/). `page.js` is the portfolio; `avatar/page.js` is the chat UI that POSTs to `${NEXT_PUBLIC_API_URL}/chat`. Hosted on Amplify (SSR / `WEB_COMPUTE`).

**Data flow:** edit files in [data/](data/) → push → [.github/workflows/data_sync.yml](.github/workflows/data_sync.yml) runs `aws s3 sync ../data s3://<bucket> --delete` → S3 event fires the Ingestion Lambda → vectors land in RDS.

### Non-obvious things that will bite you

- **The repo layout is `lambdas/api/` and `lambdas/ingestion/`, not `backend/`.** There is no `rag_pipeline.py`, `database.py`, or `ingestion.py`, and the frontend is **JavaScript (`.js`), not TypeScript** — don't assume otherwise from framework conventions.
- **An empty knowledge-base bucket fails silently as hallucination, not an error.** The RAG only grounds answers if `data/` has been synced to the KB S3 bucket *and* the ingestion Lambda has populated `pgvector`. If the bucket is empty (e.g. after a `terraform` rebuild recreates it — the data-sync workflow only fires when `data/` files change on push), retrieval returns 0 docs, `{context}` is empty, and Nova Lite answers from its own priors instead of erroring. Symptom: generic, plausible-but-wrong first-person answers. Fix: `aws s3 sync data/ s3://<kb-bucket>/` to re-trigger ingestion.
- **Two copies of ingestion logic exist and must be kept in sync manually:** [lambdas/api/ingest.py](lambdas/api/ingest.py) is a *local* one-shot script (reads `data/`, needs `DATABASE_URL`), while [lambdas/ingestion/lambda_function.py](lambdas/ingestion/lambda_function.py) is the *deployed* S3-triggered version. They share chunking/embedding logic but are separate code.
- **The deploy branch is `main`, and its name is hardcoded in several places** that must change together if ever renamed: `on: push: branches` + the `GIT_BRANCH`/`TF_VAR_git_branch` env + the apply-gate `if:` in [.github/workflows/terraform.yml](.github/workflows/terraform.yml); `on: push: branches` + `GIT_BRANCH`/`TF_VAR_git_branch` in [.github/workflows/data_sync.yml](.github/workflows/data_sync.yml); and the `git_branch` variable **default** in [terraform/variables.tf](terraform/variables.tf) (CI overrides it via `TF_VAR_git_branch`). It drives OIDC trust ([terraform/oidc.tf](terraform/oidc.tf)), the Amplify branch, and CORS origin locking ([terraform/api.tf](terraform/api.tf)). `terraform apply` in CI only runs on push to this branch.
- **Lambda zips must be byte-deterministic** or Terraform sees perpetual drift. Both [lambdas/api/build.sh](lambdas/api/build.sh) and [lambdas/ingestion/build.sh](lambdas/ingestion/build.sh) normalize all file timestamps to `2020-01-01` and sort entries before zipping. Don't add non-deterministic steps.
- **`build.sh` caches by checking for `build/langchain`** — it skips `pip install` if the build dir already looks populated. To force a clean rebuild, delete the `build/` directory first.
- Lambda deps are installed with `--platform manylinux2014_aarch64 --python-version 3.12` (arm64 cross-build); zips deploy via the deployments S3 bucket to bypass the 50 MB API limit.
- **Frontend Next.js is non-standard.** [frontend/AGENTS.md](frontend/AGENTS.md) (referenced by [frontend/CLAUDE.md](frontend/CLAUDE.md)) warns it has breaking changes from training-data Next.js — read `node_modules/next/dist/docs/` before writing frontend code.

## Commands

**Local dev (both services):**
```bash
./scripts/start.sh   # backend uvicorn :8000 (creates/uses lambdas/api/venv), frontend next dev :3000
./scripts/stop.sh
```

**Backend only** (from `lambdas/api/`, venv activated): `uvicorn main:app --port 8000 --reload`
Local ingestion into the DB (needs `DATABASE_URL` in `lambdas/api/.env` — copy from `.env.example`): `python lambdas/api/ingest.py`

**Frontend** (from `frontend/`): `npm install`, `npm run dev`, `npm run build`

**Build Lambda deployment zips** (run before Terraform if Lambda code changed):
```bash
cd lambdas/api && ./build.sh          # -> lambdas/api/api_lambda.zip
cd lambdas/ingestion && ./build.sh    # -> lambdas/ingestion/lambda_function.zip
```

**Infrastructure** (from `terraform/`): `terraform init`, `terraform plan`, `terraform apply`.
Requires `terraform.tfvars` (copy from `terraform.tfvars.example` — sets `alert_email`; secret and gitignored). Amplify pulls the repo via the Amplify GitHub App; `github_token` is only needed as a one-time setup token if the Amplify app is ever recreated from scratch.

**Pre-commit hooks** (enforce `terraform fmt` + `terraform validate`): `pre-commit install`

There is no formal test suite. [lambdas/api/test_lambda.py](lambdas/api/test_lambda.py) is an ad-hoc verification script, not a `pytest` harness.

## Deployment

Primary path is CI/CD: pushing to the deploy branch runs [.github/workflows/terraform.yml](.github/workflows/terraform.yml) (builds both Lambda zips, then `terraform fmt`/`validate`/`plan`/`apply`) via AWS OIDC — no static credentials. On PRs it posts the plan as a comment but does not apply. Local `terraform apply` works too but expects an `AWS_PROFILE`/credentials with the scoped permissions.
