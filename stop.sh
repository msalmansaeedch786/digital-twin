#!/bin/bash
# stop.sh

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Stopping Digital Twin Local Environment...${NC}"

# Find and kill backend
echo -e "${BLUE}Hunting down processes on port 8000 (Backend)...${NC}"
BACKEND_PIDS=$(lsof -ti:8000)
if [ ! -z "$BACKEND_PIDS" ]; then
    echo "$BACKEND_PIDS" | xargs kill -9 2>/dev/null
    echo -e "${GREEN}Backend killed.${NC}"
else
    echo "No backend process found."
fi

# Find and kill frontend
echo -e "${BLUE}Hunting down processes on port 3000 (Frontend)...${NC}"
FRONTEND_PIDS=$(lsof -ti:3000)
if [ ! -z "$FRONTEND_PIDS" ]; then
    echo "$FRONTEND_PIDS" | xargs kill -9 2>/dev/null
    echo -e "${GREEN}Frontend killed.${NC}"
else
    echo "No frontend process found."
fi

echo ""
echo -e "${GREEN}✅ All local processes have been successfully stopped.${NC}"
