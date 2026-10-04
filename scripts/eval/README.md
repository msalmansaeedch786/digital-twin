# Retrieval regression suite

A change detector for the twin's answers. It exists because the backend's worst
failure mode is **silent**: if retrieval returns nothing, the LLM answers from its
own priors and the reply looks confident and plausible rather than erroring.

Run it before and after anything that touches embeddings, the vector store, or the
knowledge base, and diff the two runs.

```bash
python scripts/eval/capture.py --label before-change
#   ... make the change, deploy, let ingestion settle ...
python scripts/eval/capture.py --label after-change
python scripts/eval/compare.py before-change after-change    # exit 1 if anything regressed
```

`capture.py` hits the deployed `/chat`; point it elsewhere with `--base-url` or
`TWIN_API_URL` (e.g. `http://localhost:8000` for a local run).

## What it checks

- **13 grounded questions**, two locales. Each asserts fact *groups* with locale
  alternatives, so `Munich`/`München` and `3.74`/`3,74` both count. The score is the
  share of groups present, not a text match — wording is free to change.
- **3 negative questions** that have no answer in the knowledge base. These are the
  valuable ones: they catch the twin claiming a certification it does not hold, a
  job it never had, or inventing a salary. One of these is the real
  `SysOps Administrator – Associate` bug, kept as a permanent test.

## What it is not

Not a grader. Scores are crude on purpose; the LLM is non-deterministic, so a
reworded answer is not a regression. The durable value is the saved replies in
`runs/*.json`, which a human can read side by side. Committed runs are the record.

## Gotchas

- Pacing is bound by `@limiter.limit("20/minute")` per IP in `lambdas/api/main.py`,
  not by the API Gateway stage (5 rps). Hence the 2.5s default `--delay`; a 429
  needs ~25s of backoff, not seconds.
- `docs_retrieved` is **logged, not returned** by `/chat`. Pull it from Logs Insights
  on `/aws/lambda/digital-twin-api` for the run window and merge it into the run
  file — that field going to 0 is the empty-knowledge-base failure.
- The python.org macOS build ships no CA bundle, so every HTTPS call fails with
  `CERTIFICATE_VERIFY_FAILED`. The preflight says what to do:
  `SSL_CERT_FILE=/opt/homebrew/etc/openssl@3/cert.pem`.
