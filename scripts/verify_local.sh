#!/usr/bin/env bash
#
# Proves the no-AWS path still works, end to end, with AWS credentials removed
# from the environment.
#
# This exists because that path has no CI coverage and cannot have any: it needs
# Ollama and a local Postgres, neither of which belongs on a GitHub runner. The
# alternative to a script you can run on demand is a capability that quietly stops
# working and is only discovered when you actually need it offline — which is
# precisely what happened between 2026-09-06 and 2026-10-06, when the vector store
# changed underneath it and main.py turned out never to have read .env at all.
#
#   ./scripts/verify_local.sh
#
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="$REPO_ROOT/lambdas/api"
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'

fail=0
step() { printf "  %-46s" "$1"; }
ok()   { echo "${GREEN}ok${NC}${1:+  $1}"; }
bad()  { echo "${RED}FAIL${NC}  $1"; fail=1; }

echo "Verifying the fully local, no-AWS path"
echo

step "ollama installed"
command -v ollama >/dev/null && ok "$(ollama --version 2>/dev/null | head -1)" || bad "brew install ollama"

step "ollama serving"
curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && ok || bad "start it with: ollama serve"

EMB="$(grep -E '^OLLAMA_EMBEDDING_MODEL=' "$API_DIR/.env" 2>/dev/null | cut -d= -f2)"
LLM="$(grep -E '^OLLAMA_LLM_MODEL=' "$API_DIR/.env" 2>/dev/null | cut -d= -f2)"
EMB="${EMB:-bge-m3}"; LLM="${LLM:-llama3.1}"

for m in "$EMB" "$LLM"; do
  step "model pulled: $m"
  ollama list 2>/dev/null | awk '{print $1}' | grep -q "^${m%%:*}" && ok || bad "ollama pull $m"
done

step "postgres accepting connections"
pg_isready -q 2>/dev/null && ok || bad "brew services start postgresql@17"

step "pgvector extension present"
psql -d digitaltwin -tAc "select 1 from pg_extension where extname='vector'" 2>/dev/null | grep -q 1 \
  && ok || bad "CREATE EXTENSION vector; in the digitaltwin database"

step "local vectors ingested"
N="$(psql -d digitaltwin -tAc 'select count(*) from langchain_pg_embedding' 2>/dev/null | tr -d ' ')"
[ "${N:-0}" -gt 0 ] && ok "$N chunks" \
  || bad "run: AI_PROVIDER=ollama VECTOR_STORE=pgvector python lambdas/api/ingest.py"

step ".env sets BOTH switches"
if grep -qE '^AI_PROVIDER=ollama' "$API_DIR/.env" 2>/dev/null; then
  grep -qE '^VECTOR_STORE=pgvector' "$API_DIR/.env" 2>/dev/null && ok \
    || bad "AI_PROVIDER=ollama without VECTOR_STORE=pgvector — the guard will refuse to start"
else
  echo "${YELLOW}skip${NC}  (.env is not in local mode)"
fi

[ "$fail" -ne 0 ] && { echo; echo "${RED}Prerequisites missing — fix the above first.${NC}"; exit 1; }

echo
echo "  asking a real question with AWS credentials stripped..."
OUT="$(cd "$API_DIR" && env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
  -u AWS_PROFILE -u AWS_REGION -u AWS_DEFAULT_REGION \
  venv/bin/python -c "
import main
eng = main.AIEngine(); eng.initialize()
r = eng.rag_chain.invoke({'input':'How many AWS certifications do you hold?','chat_history':[],
                          'query_language':'en','answer_language':'English'})
print('DOCS', len(r['context']))
print('ANSWER', r['answer'].replace(chr(10),' ')[:200])
" 2>/dev/null)"

DOCS="$(echo "$OUT" | grep '^DOCS' | awk '{print $2}')"
ANSWER="$(echo "$OUT" | grep '^ANSWER' | cut -d' ' -f2-)"

step "retrieval returned documents"
[ "${DOCS:-0}" -gt 0 ] && ok "$DOCS docs" || bad "retrieval returned nothing — answers would be ungrounded"

step "answer mentions the certifications"
echo "$ANSWER" | grep -qiE "6x|six|certif" && ok || bad "unexpected answer: ${ANSWER:0:80}"

echo
if [ "$fail" -eq 0 ]; then
  echo "${GREEN}The no-AWS path works.${NC}"
  echo "  $ANSWER" | cut -c1-110
else
  echo "${RED}The no-AWS path is broken.${NC}"
fi
exit "$fail"
