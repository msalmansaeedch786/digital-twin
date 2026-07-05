#!/bin/bash
# start.sh — launch the local dev environment (backend API + frontend)

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Resolve the repo root from this script's location so it works from anywhere
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}Starting Digital Twin Local Development Environment...${NC}"

# 1. Clean up any existing processes on the required ports
echo -e "${BLUE}Cleaning up ports 3000 and 8000...${NC}"
lsof -ti:3000 | xargs kill -9 2>/dev/null
lsof -ti:8000 | xargs kill -9 2>/dev/null

# 2. Start the FastAPI Backend
echo -e "${BLUE}Starting backend (FastAPI) on port 8000...${NC}"
cd "$ROOT/lambdas/api" || exit
if [ ! -d venv ]; then
    echo -e "${BLUE}First run: creating backend virtualenv and installing dependencies...${NC}"
    python3 -m venv venv
    source venv/bin/activate
    pip install -q -r requirements.txt
else
    source venv/bin/activate
fi
uvicorn main:app --port 8000 --reload > /dev/null 2>&1 &

# 3. Start the Next.js Frontend
echo -e "${BLUE}Starting frontend (Next.js) on port 3000...${NC}"
cd "$ROOT/frontend" || exit
npm run dev > /dev/null 2>&1 &

# 4. Print success message
echo ""
echo "========================================="
echo -e "${GREEN}✅ Backend is running on http://localhost:8000${NC}"
echo -e "${GREEN}✅ Frontend is running on http://localhost:3000${NC}"
echo ""
echo -e "${RED}To stop everything, run: ./scripts/stop.sh${NC}"
echo "========================================="
