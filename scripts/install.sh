#!/bin/bash

################################################################################
# Karma Universal Deploy & Rollback Installer
# Version: 1.0.0
# 
# This script installs the deploy and rollback tools in a service
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
GITHUB_RAW_URL="https://raw.githubusercontent.com/karmadev/karma-workflows/main/scripts"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        Karma Universal Deploy & Rollback Installer             ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo -e "${RED}❌ Not in a git repository${NC}"
    echo "Please run this script from your service's root directory"
    exit 1
fi

# Check if package.json exists
if [ ! -f "package.json" ]; then
    echo -e "${RED}❌ No package.json found${NC}"
    echo "Please run this script from a Node.js project root"
    exit 1
fi

# Create scripts directory if it doesn't exist
mkdir -p scripts

# Download deploy.sh
echo -e "${BLUE}📥 Downloading deploy.sh...${NC}"
curl -s "$GITHUB_RAW_URL/deploy.sh" > scripts/deploy.sh
chmod +x scripts/deploy.sh
echo -e "${GREEN}✅ deploy.sh installed${NC}"

# Download rollback.sh
echo -e "${BLUE}📥 Downloading rollback.sh...${NC}"
curl -s "$GITHUB_RAW_URL/rollback.sh" > scripts/rollback.sh
chmod +x scripts/rollback.sh
echo -e "${GREEN}✅ rollback.sh installed${NC}"

# Add npm scripts
echo -e "${BLUE}📝 Adding npm scripts...${NC}"

# Deploy scripts
npm pkg set scripts.deploy="bash scripts/deploy.sh"
npm pkg set scripts.deploy:dev="bash scripts/deploy.sh dev"
npm pkg set scripts.deploy:staging="bash scripts/deploy.sh staging"
npm pkg set scripts.deploy:prod="bash scripts/deploy.sh prod"

# Rollback scripts
npm pkg set scripts.rollback="bash scripts/rollback.sh"
npm pkg set scripts.rollback:dev="bash scripts/rollback.sh dev"
npm pkg set scripts.rollback:staging="bash scripts/rollback.sh staging"
npm pkg set scripts.rollback:prod="bash scripts/rollback.sh prod"
npm pkg set scripts.rollback:history="bash scripts/rollback.sh --history"

echo -e "${GREEN}✅ npm scripts added${NC}"

# Create .deploy.config template if it doesn't exist
if [ ! -f ".deploy.config" ]; then
    echo -e "${BLUE}📝 Creating .deploy.config template...${NC}"
    SERVICE_NAME=$(basename $(pwd))
    cat > .deploy.config << EOF
# Karma Deploy Configuration
# Service: $SERVICE_NAME

SERVICE_NAME="$SERVICE_NAME"
DEFAULT_BRANCH="main"
DEPLOY_BRANCHES="main develop"
MAX_VERSIONS_TO_SHOW=20

# Deployment type (kubernetes or firebase)
DEPLOY_TYPE="kubernetes"

# For Firebase deployments
# FIREBASE_PROJECT_DEV="your-dev-project"
# FIREBASE_PROJECT_PROD="your-prod-project"
# FIREBASE_HOSTING_TARGET="your-hosting-target"
EOF
    echo -e "${GREEN}✅ .deploy.config created${NC}"
else
    echo -e "${YELLOW}ℹ️  .deploy.config already exists${NC}"
fi

# Add .deploy.config.local to .gitignore if not already there
if [ -f ".gitignore" ]; then
    if ! grep -q ".deploy.config.local" .gitignore; then
        echo "" >> .gitignore
        echo "# Local deploy configuration" >> .gitignore
        echo ".deploy.config.local" >> .gitignore
        echo -e "${GREEN}✅ Added .deploy.config.local to .gitignore${NC}"
    fi
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                 Installation Complete! 🎉                      ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Available commands:"
echo ""
echo "  Deploy commands:"
echo "    npm run deploy              # Interactive deployment"
echo "    npm run deploy:dev          # Deploy to development"
echo "    npm run deploy:staging      # Deploy to staging"
echo "    npm run deploy:prod         # Deploy to production"
echo ""
echo "  Rollback commands:"
echo "    npm run rollback            # Interactive rollback"
echo "    npm run rollback:dev        # Rollback development"
echo "    npm run rollback:staging    # Rollback staging"
echo "    npm run rollback:prod       # Rollback production"
echo "    npm run rollback:history    # Show rollback history"
echo ""
echo "Next steps:"
echo "  1. Review and customize .deploy.config"
echo "  2. Test with: npm run deploy dev"
echo "  3. For help: npm run deploy -- --help"
echo ""