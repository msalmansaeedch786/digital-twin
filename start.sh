#!/bin/bash
# start.sh

# Colors for terminal output
GREEN='\03[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Digital Twin Local Development Environment...${NC}"

# 1. Clean up any existing processes on the required ports
echo -e "${BLUE}Cleaning up ports 3000 and 8000...${NC}"
lsof -ti:3000 | xargs kill -9 2>/dev/null
lsof -ti:8000 | xargs kill -9 2>/dev/null

# 2. Start the FastAPI Backend
echo -e "${BLUE}Starting backend (FastAPI) on port 8000...${NC}"
cd backend || exit
source venv/bin/activate
uvicorn main:app --port 8000 --reload > /dev/null 2>&1 &
BACKEND_PID=$!
cd ..

# 3. Start the Next.js Frontend
echo -e "${BLUE}Starting frontend (Next.js) on port 3000...${NC}"
cd frontend || exit
npm run dev > /dev/null 2>&1 &
FRONTEND_PID=$!
cd ..

# 4. Print success message
echo ""
echo "========================================="
echo -e "${GREEN}✅ Backend is running on http://localhost:8000${NC}"
echo -e "${GREEN}✅ Frontend is running on http://localhost:3000${NC}"
echo ""
echo -e "${RED}To stop everything, run: ./stop.sh${NC}"
echo "========================================="
