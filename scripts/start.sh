#!/bin/bash
# start.sh — launch the local dev environment (backend API + frontend)

set -uo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${TMPDIR:-/tmp}"
BACKEND_LOG="$LOG_DIR/digital-twin-backend.log"
FRONTEND_LOG="$LOG_DIR/digital-twin-frontend.log"

echo -e "${BLUE}Starting Digital Twin Local Development Environment...${NC}"

# 1. Pick an interpreter the pinned dependencies can actually install under.
#    requirements.txt targets the Lambda runtime (3.12); pydantic-core 2.7.4
#    ships no wheels for 3.14 and its Rust build fails there, so a bare
#    `python3` on a newer machine produces a broken venv.
PY=""
for candidate in python3.12 python3.11 python3.13; do
    if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
if [ -z "$PY" ]; then
    HAVE="$(python3 -V 2>&1)"
    echo -e "${RED}No suitable Python found. The backend needs 3.12 (the Lambda runtime).${NC}"
    echo -e "${RED}Your default is ${HAVE}, which cannot build pydantic-core 2.7.4.${NC}"
    echo -e "${YELLOW}Install it with:  brew install python@3.12${NC}"
    exit 1
fi

# 2. Backend
echo -e "${BLUE}Cleaning up ports 3000 and 8000...${NC}"
lsof -ti:3000 | xargs kill -9 2>/dev/null
lsof -ti:8000 | xargs kill -9 2>/dev/null

echo -e "${BLUE}Starting backend (FastAPI) on port 8000 using ${PY}...${NC}"
cd "$ROOT/lambdas/api" || exit 1
if [ ! -d venv ]; then
    echo -e "${BLUE}First run: creating backend virtualenv and installing dependencies...${NC}"
    "$PY" -m venv venv || exit 1
    # shellcheck disable=SC1091
    source venv/bin/activate
    # A failed install used to leave a venv behind: the next run saw the
    # directory, skipped installing, and started a backend with no uvicorn.
    if ! pip install -q -r requirements.txt; then
        echo -e "${RED}Dependency install failed — removing the half-built venv.${NC}"
        deactivate 2>/dev/null
        rm -rf venv
        exit 1
    fi
else
    # shellcheck disable=SC1091
    source venv/bin/activate
fi
uvicorn main:app --port 8000 --reload > "$BACKEND_LOG" 2>&1 &

# 3. Frontend
echo -e "${BLUE}Starting frontend (Next.js) on port 3000...${NC}"
cd "$ROOT/frontend" || exit 1
npm run dev > "$FRONTEND_LOG" 2>&1 &

# 4. Report what actually came up, rather than assuming.
wait_for() {
    for _ in $(seq 1 40); do
        curl -sf -o /dev/null "$1" && return 0
        sleep 1
    done
    return 1
}

echo ""
echo "========================================="
if wait_for http://localhost:8000/health; then
    echo -e "${GREEN}✅ Backend  http://localhost:8000${NC}"
else
    echo -e "${RED}❌ Backend did not come up — see $BACKEND_LOG${NC}"
fi
if wait_for http://localhost:3000; then
    echo -e "${GREEN}✅ Frontend http://localhost:3000${NC}"
else
    echo -e "${RED}❌ Frontend did not come up — see $FRONTEND_LOG${NC}"
fi
echo ""
echo -e "${YELLOW}Note: RDS is publicly_accessible = false, so a local backend cannot${NC}"
echo -e "${YELLOW}reach the database. /chat needs a tunnel or a local Postgres; the${NC}"
echo -e "${YELLOW}frontend against the deployed API is the usual local loop.${NC}"
echo ""
echo -e "${RED}To stop everything, run: ./scripts/stop.sh${NC}"
echo "========================================="
