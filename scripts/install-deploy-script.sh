#!/bin/bash

# Karma Deploy Script Installer
# This script installs or updates the deploy.sh script in any repository

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_VERSION="2.0.0"
WORKFLOWS_REPO="https://raw.githubusercontent.com/karmadev/karma-workflows/main"
SCRIPT_URL="${WORKFLOWS_REPO}/scripts/deploy.sh"

print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to detect service type
detect_service_type() {
    if [ -f "package.json" ]; then
        # Check for specific indicators
        if [ -f "Dockerfile" ]; then
            echo "kubernetes"
        elif [ -f "firebase.json" ]; then
            echo "firebase"
        elif [ -f ".firebaserc" ]; then
            echo "firebase"
        elif grep -q "@google-cloud/functions" package.json 2>/dev/null; then
            echo "cloud-function"
        else
            echo "nodejs"
        fi
    else
        echo "unknown"
    fi
}

# Function to create deploy config
create_deploy_config() {
    local service_type=$1
    local service_name=$(basename $(pwd))
    
    print_color $BLUE "📝 Creating .deploy.config for $service_type service..."
    
    case $service_type in
        kubernetes)
            cat > .deploy.config << EOF
# Deploy configuration for $service_name
SERVICE_NAME="$service_name"
DEFAULT_BRANCH="master"
DEPLOY_BRANCHES="master main"
VERSION_PREFIX="v"
ENABLE_HOTFIX=true
ENABLE_PREVIEW=true

# Kubernetes-specific settings
DEPLOY_TYPE="kubernetes"
EOF
            ;;
        firebase)
            cat > .deploy.config << EOF
# Deploy configuration for $service_name
SERVICE_NAME="$service_name"
DEFAULT_BRANCH="main"
DEPLOY_BRANCHES="main master"
VERSION_PREFIX="v"
ENABLE_HOTFIX=false
ENABLE_PREVIEW=true

# Firebase-specific settings
DEPLOY_TYPE="firebase"
FIREBASE_PROJECT_DEV="${service_name}-dev"
FIREBASE_PROJECT_PROD="${service_name}-prod"
EOF
            ;;
        cloud-function)
            cat > .deploy.config << EOF
# Deploy configuration for $service_name
SERVICE_NAME="$service_name"
DEFAULT_BRANCH="main"
DEPLOY_BRANCHES="main master"
VERSION_PREFIX="v"
ENABLE_HOTFIX=true
ENABLE_PREVIEW=true

# Cloud Function-specific settings
DEPLOY_TYPE="cloud-function"
FUNCTION_NAME="$service_name"
FUNCTION_REGION="europe-north1"
EOF
            ;;
        *)
            cat > .deploy.config << EOF
# Deploy configuration for $service_name
SERVICE_NAME="$service_name"
DEFAULT_BRANCH="main"
DEPLOY_BRANCHES="main master"
VERSION_PREFIX="v"
ENABLE_HOTFIX=false
ENABLE_PREVIEW=true

# Service type
DEPLOY_TYPE="generic"
EOF
            ;;
    esac
    
    print_color $GREEN "✅ Created .deploy.config"
}

# Function to update package.json
update_package_json() {
    if [ -f "package.json" ]; then
        print_color $BLUE "📦 Updating package.json..."
        
        # Check if deploy script already exists
        if grep -q '"deploy"' package.json; then
            print_color $YELLOW "⚠️  Deploy script already exists in package.json"
            read -p "Do you want to update it? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Update existing deploy script
                sed -i.bak '/"deploy":/s/.*/    "deploy": "bash deploy.sh",/' package.json && rm package.json.bak
                print_color $GREEN "✅ Updated deploy script in package.json"
            fi
        else
            # Add deploy script to scripts section
            if grep -q '"scripts"' package.json; then
                # Add after "scripts": {
                sed -i.bak '/"scripts": {/a\
    "deploy": "bash deploy.sh",' package.json && rm package.json.bak
                print_color $GREEN "✅ Added deploy script to package.json"
            else
                print_color $YELLOW "⚠️  No scripts section found in package.json"
                print_color $YELLOW "   Please add manually: \"deploy\": \"bash deploy.sh\""
            fi
        fi
        
        # Add deployment helper scripts
        if ! grep -q '"deploy:dev"' package.json; then
            sed -i.bak '/"deploy":/a\
    "deploy:dev": "bash deploy.sh dev",\
    "deploy:staging": "bash deploy.sh staging",\
    "deploy:prod": "bash deploy.sh prod",' package.json && rm package.json.bak
            print_color $GREEN "✅ Added deployment helper scripts"
        fi
    fi
}

# Function to add to .gitignore
update_gitignore() {
    if [ -f ".gitignore" ]; then
        if ! grep -q ".deploy.config.local" .gitignore; then
            echo "" >> .gitignore
            echo "# Deploy script local configuration" >> .gitignore
            echo ".deploy.config.local" >> .gitignore
            print_color $GREEN "✅ Updated .gitignore"
        fi
    fi
}

# Main installation flow
main() {
    print_color $BLUE "🚀 Karma Deploy Script Installer v${SCRIPT_VERSION}"
    echo ""
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_color $RED "Error: Not in a git repository"
        exit 1
    fi
    
    # Detect service type
    local service_type=$(detect_service_type)
    print_color $BLUE "🔍 Detected service type: $service_type"
    
    # Download deploy.sh
    print_color $BLUE "📥 Downloading deploy.sh..."
    if command -v curl &> /dev/null; then
        curl -sL "$SCRIPT_URL" -o deploy.sh
    elif command -v wget &> /dev/null; then
        wget -q "$SCRIPT_URL" -O deploy.sh
    else
        print_color $RED "Error: Neither curl nor wget is installed"
        exit 1
    fi
    
    # Make executable
    chmod +x deploy.sh
    print_color $GREEN "✅ Downloaded deploy.sh"
    
    # Create or update .deploy.config
    if [ ! -f ".deploy.config" ]; then
        create_deploy_config "$service_type"
    else
        print_color $YELLOW "⚠️  .deploy.config already exists"
        read -p "Do you want to regenerate it? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mv .deploy.config .deploy.config.backup
            create_deploy_config "$service_type"
            print_color $YELLOW "   Previous config backed up to .deploy.config.backup"
        fi
    fi
    
    # Update package.json
    update_package_json
    
    # Update .gitignore
    update_gitignore
    
    # Create README section
    if [ ! -f "DEPLOY.md" ]; then
        cat > DEPLOY.md << 'EOF'
# Deployment Guide

This service uses the Karma unified deployment system.

## Quick Deploy

```bash
# Deploy to development
npm run deploy:dev

# Deploy to staging
npm run deploy:staging

# Deploy to production
npm run deploy:prod
```

## Advanced Usage

```bash
# Deploy with specific version
./deploy.sh prod --version 2.1.0

# Deploy with version bump
./deploy.sh prod --minor  # Bumps minor version
./deploy.sh prod --major  # Bumps major version

# Preview deployment
./deploy.sh dev --preview

# Hotfix deployment
./deploy.sh hotfix --message "Fix critical bug"
```

## Configuration

Edit `.deploy.config` to customize deployment settings:
- `SERVICE_NAME`: Name of the service
- `DEFAULT_BRANCH`: Default git branch
- `DEPLOY_BRANCHES`: Allowed deployment branches
- `VERSION_PREFIX`: Tag prefix (default: "v")
- `ENABLE_HOTFIX`: Allow hotfix deployments
- `ENABLE_PREVIEW`: Show preview before deployment

## Version Tagging Strategy

- Production: `v1.0.0`
- Development: `v1.0.0-dev`
- Staging: `v1.0.0-staging`

## Updating Deploy Script

To update to the latest version:
```bash
curl -sL https://raw.githubusercontent.com/karmadev/karma-workflows/main/scripts/install-deploy-script.sh | bash
```
EOF
        print_color $GREEN "✅ Created DEPLOY.md documentation"
    fi
    
    # Summary
    echo ""
    print_color $GREEN "✨ Installation complete!"
    echo ""
    print_color $BLUE "📋 Next steps:"
    print_color $BLUE "   1. Review .deploy.config and adjust settings"
    print_color $BLUE "   2. Commit the new files:"
    print_color $YELLOW "      git add deploy.sh .deploy.config DEPLOY.md"
    print_color $YELLOW "      git commit -m 'Add unified deploy script'"
    echo ""
    print_color $BLUE "📚 Usage:"
    print_color $BLUE "   npm run deploy:dev      # Deploy to development"
    print_color $BLUE "   npm run deploy:staging  # Deploy to staging"
    print_color $BLUE "   npm run deploy:prod     # Deploy to production"
    print_color $BLUE "   ./deploy.sh --help      # See all options"
}

# Run main function
main "$@"