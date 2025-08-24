#!/bin/bash

################################################################################
# Karma Rollback Installer
# Version: 1.0.0
# 
# This script adds rollback capability to a service's package.json
################################################################################

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}📦 Adding rollback capability to package.json...${NC}"

# Check if package.json exists
if [ ! -f "package.json" ]; then
    echo -e "${YELLOW}⚠️  No package.json found in current directory${NC}"
    exit 1
fi

# Check if npm is available
if ! command -v npm &> /dev/null; then
    echo -e "${YELLOW}⚠️  npm is not installed${NC}"
    exit 1
fi

# Add rollback script to package.json
if ! grep -q '"deploy:rollback"' package.json; then
    # Use npm to add the script
    npm pkg set scripts.deploy:rollback="bash scripts/rollback.sh"
    echo -e "${GREEN}✅ Added deploy:rollback script${NC}"
else
    echo -e "${YELLOW}ℹ️  deploy:rollback script already exists${NC}"
fi

# Also add convenience scripts for specific environments
npm pkg set scripts.rollback="bash scripts/rollback.sh"
npm pkg set scripts.rollback:dev="bash scripts/rollback.sh dev"
npm pkg set scripts.rollback:staging="bash scripts/rollback.sh staging"
npm pkg set scripts.rollback:prod="bash scripts/rollback.sh prod"

echo -e "${GREEN}✅ Rollback scripts added to package.json${NC}"
echo ""
echo "Available commands:"
echo "  npm run rollback         # Interactive rollback"
echo "  npm run rollback:dev     # Rollback development"
echo "  npm run rollback:staging # Rollback staging"
echo "  npm run rollback:prod    # Rollback production"
echo ""
echo -e "${GREEN}🎉 Rollback capability installed successfully!${NC}"