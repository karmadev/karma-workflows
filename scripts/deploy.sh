#!/bin/bash

# Karma Universal Deploy Script v3.0
# Enhanced with features from karma-admin-api
# 
# Usage: 
#   npm run deploy                         # Interactive mode
#   npm run deploy:dev                     # Deploy to development
#   npm run deploy:prod                    # Deploy to production  
#   ./deploy.sh dev --rebuild              # Rebuild without version bump
#   ./deploy.sh prod --version 2.1.0       # Deploy specific version
#
# This script handles:
# - Interactive environment selection
# - Semantic versioning (major/minor/patch)
# - Rebuild existing version (new build, same version)
# - Version tagging and deployment
# - Real-time deployment monitoring

set -e

# Colors for output
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
NC=$'\033[0m' # No Color

# Configuration (can be overridden by .deploy.config)
SERVICE_NAME="${SERVICE_NAME:-$(basename $(pwd))}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"
DEPLOY_BRANCHES="${DEPLOY_BRANCHES:-master main}"
VERSION_PREFIX="${VERSION_PREFIX:-v}"
ENABLE_HOTFIX="${ENABLE_HOTFIX:-true}"
ENABLE_PREVIEW="${ENABLE_PREVIEW:-true}"
MONITOR_DEPLOYMENT="${MONITOR_DEPLOYMENT:-true}"
DEPLOY_TYPE="${DEPLOY_TYPE:-kubernetes}"

# Load local configuration if exists
if [ -f .deploy.config ]; then
    source .deploy.config
fi

# Load local overrides if exists
if [ -f .deploy.config.local ]; then
    source .deploy.config.local
fi

# Function to print colored output
print_color() {
    local color=$1
    shift
    printf "${color}%s${NC}\n" "$@"
}

# Function to get current version from package.json
get_current_version() {
    if [ -f "package.json" ]; then
        grep '"version"' "package.json" | sed -E 's/.*"version": "([^"]+)".*/\1/'
    else
        echo "0.0.0"
    fi
}

# Function to get the latest version tag
get_latest_version() {
    local env=$1
    local latest_tag=""
    
    if [ "$env" = "production" ] || [ "$env" = "prod" ]; then
        # Get latest production version (without suffix)
        latest_tag=$(git tag -l "${VERSION_PREFIX}*" | grep -E "^${VERSION_PREFIX}[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1)
    elif [ "$env" = "staging" ]; then
        # Get latest staging version
        latest_tag=$(git tag -l "${VERSION_PREFIX}*-staging" | sort -V | tail -n 1)
    else
        # Get latest dev version
        latest_tag=$(git tag -l "${VERSION_PREFIX}*-dev" | sort -V | tail -n 1)
    fi
    
    if [ -z "$latest_tag" ]; then
        echo "${VERSION_PREFIX}0.0.0"
    else
        echo "$latest_tag"
    fi
}

# Function to increment version
increment_version() {
    local version=$1
    local increment_type=$2
    
    # Remove prefix and suffix
    version=${version#${VERSION_PREFIX}}
    version=${version%-*}
    
    # Split version into components
    IFS='.' read -r major minor patch <<< "$version"
    
    # Remove any pre-release or build metadata
    patch=${patch%%-*}
    patch=${patch%%+*}
    
    case $increment_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Function to update package.json version
update_package_json() {
    local new_version=$1
    if [ -f "package.json" ]; then
        sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$new_version\"/" "package.json"
        rm "package.json.bak" 2>/dev/null || true
        print_color $GREEN "✓ Updated package.json version to $new_version"
    fi
}

# Function to create and push tag
deploy_version() {
    local version=$1
    local env=$2
    local message=$3
    local rebuild=$4
    
    # Construct the full tag
    local tag="${VERSION_PREFIX}${version}"
    if [ "$env" = "staging" ]; then
        tag="${tag}-staging"
    elif [ "$env" != "production" ] && [ "$env" != "prod" ]; then
        tag="${tag}-dev"
    fi
    
    # Check if this is a rebuild
    if [ "$rebuild" = "true" ]; then
        # For rebuilds, we force update the tag
        print_color $BLUE "🔄 Rebuilding deployment with tag: $tag"
        
        if [ -z "$message" ]; then
            message="Rebuild $SERVICE_NAME $version for $env"
        fi
        
        # Delete the old tag locally and remotely
        git tag -d "$tag" 2>/dev/null || true
        git push origin :refs/tags/"$tag" 2>/dev/null || true
        
        # Create new tag at current commit
        git tag -a "$tag" -m "$message" -f
        
        print_color $BLUE "🚀 Pushing tag to trigger rebuild..."
        git push origin "$tag" -f
    else
        # Normal deployment with new version
        print_color $BLUE "📦 Creating deployment tag: $tag"
        
        if [ -z "$message" ]; then
            message="Deploy $SERVICE_NAME $version to $env"
        fi
        
        # Check if tag already exists
        if git rev-parse "$tag" >/dev/null 2>&1; then
            print_color $YELLOW "⚠️  Tag $tag already exists"
            echo ""
            echo "Options:"
            echo "  1) Force rebuild with same version (redeploy)"
            echo "  2) Choose a different version"
            echo "  3) Cancel"
            read -p "Enter your choice (1-3): " choice
            
            case $choice in
                1)
                    deploy_version "$version" "$env" "$message" "true"
                    return
                    ;;
                2)
                    print_color $CYAN "Please run the script again with a different version"
                    exit 0
                    ;;
                3)
                    print_color $RED "Deployment cancelled"
                    exit 1
                    ;;
            esac
        fi
        
        git tag -a "$tag" -m "$message"
        
        print_color $BLUE "🚀 Pushing tag to trigger deployment..."
        git push origin "$tag"
    fi
    
    print_color $GREEN "✅ Deployment initiated successfully!"
    print_color $GREEN "   Tag: $tag"
    print_color $GREEN "   Environment: $env"
    print_color $GREEN "   Version: $version"
    echo ""
    
    # Check if we should monitor the deployment
    if [ "${MONITOR_DEPLOYMENT:-true}" = "true" ] && command -v gh &> /dev/null; then
        print_color $YELLOW "📊 Monitoring deployment..."
        monitor_github_actions "$tag"
    else
        # Get the GitHub repository path for manual monitoring
        local github_repo=""
        if command -v gh &> /dev/null; then
            github_repo=$(gh repo view --json nameWithOwner 2>/dev/null | jq -r '.nameWithOwner' || echo "")
        fi
        
        if [ -z "$github_repo" ]; then
            # Fallback to git remote URL parsing
            github_repo=$(git remote get-url origin 2>/dev/null | sed -E 's/.*github.com[:\\/](.+)\\.git/\\1/' || echo "karmadev/$SERVICE_NAME")
        fi
        
        print_color $YELLOW "📊 Monitor deployment:"
        print_color $YELLOW "   • GitHub Actions: https://github.com/$github_repo/actions"
        if [ "$DEPLOY_TYPE" = "kubernetes" ]; then
            print_color $YELLOW "   • ArgoCD: https://argocd.karma.life"
        fi
    fi
}

# Function to monitor GitHub Actions
monitor_github_actions() {
    local tag=$1
    local workflow_found=false
    local workflow_id=""
    local workflow_status=""
    local check_count=0
    local max_checks=60  # Max 10 minutes (60 * 10 seconds)
    
    # Get the GitHub repository path
    local github_repo=""
    if command -v gh &> /dev/null; then
        github_repo=$(gh repo view --json nameWithOwner 2>/dev/null | jq -r '.nameWithOwner' || echo "")
    fi
    
    if [ -z "$github_repo" ]; then
        # Fallback to git remote URL parsing
        github_repo=$(git remote get-url origin 2>/dev/null | sed -E 's/.*github.com[:\\/](.+)\\.git/\\1/' || echo "karmadev/$SERVICE_NAME")
    fi
    
    print_color $BLUE "⏳ Waiting for GitHub Actions to start..."
    
    # Wait for workflow to start
    while [ $check_count -lt 10 ]; do
        check_count=$((check_count + 1))
        
        # Try to find the workflow run using gh CLI
        workflow_info=$(gh run list --limit 5 --json databaseId,status,headBranch,name 2>/dev/null | \
            jq -r ".[] | select(.headBranch == \"refs/tags/$tag\" or .headBranch == \"$tag\") | \"\(.databaseId)|\(.status)\"" | head -n 1)
        
        if [ -n "$workflow_info" ]; then
            workflow_id=$(echo "$workflow_info" | cut -d'|' -f1)
            workflow_status=$(echo "$workflow_info" | cut -d'|' -f2)
            workflow_found=true
            break
        fi
        
        sleep 2
    done
    
    if [ "$workflow_found" = false ]; then
        print_color $YELLOW "⚠️  Workflow not found yet. You can monitor manually at:"
        print_color $YELLOW "   https://github.com/$github_repo/actions"
        return
    fi
    
    print_color $GREEN "✓ Found workflow run #$workflow_id"
    print_color $BLUE "📊 Watching deployment progress..."
    echo ""
    
    # Use gh CLI to watch the run (suppress stderr to avoid "no default repo" warnings)
    gh run watch "$workflow_id" --interval 5 2>/dev/null || true
    
    # Get final status
    workflow_info=$(gh run view "$workflow_id" --json status,conclusion 2>/dev/null)
    workflow_conclusion=$(echo "$workflow_info" | jq -r '.conclusion')
    
    if [ "$workflow_conclusion" = "success" ]; then
        print_color $GREEN "🎉 Deployment completed successfully!"
        print_color $GREEN "   View run: https://github.com/$github_repo/actions/runs/$workflow_id"
        
        # Additional monitoring for Kubernetes deployments
        if [ "$DEPLOY_TYPE" = "kubernetes" ]; then
            echo ""
            print_color $BLUE "⏳ Waiting for ArgoCD sync (this may take 2-3 minutes)..."
            print_color $YELLOW "📊 Check ArgoCD status at: https://argocd.karma.life"
        fi
    else
        print_color $RED "❌ Deployment failed with status: $workflow_conclusion"
        print_color $RED "   View logs: https://github.com/$github_repo/actions/runs/$workflow_id"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Karma Deploy Script v3.0

Usage: $0 [environment] [options]

Environments:
  dev, development    Deploy to development environment
  staging            Deploy to staging environment  
  prod, production   Deploy to production environment
  hotfix             Create a hotfix deployment
  rollback           Rollback to a previous version (interactive)

Options:
  --major            Increment major version (X.0.0)
  --minor            Increment minor version (x.X.0)
  --patch            Increment patch version (x.x.X) [default]
  --version VERSION  Use specific version number
  --rebuild          Rebuild with same version (new build, no version bump)
  --message MESSAGE  Custom tag message
  --preview          Preview the deployment without executing
  --no-monitor       Don't monitor the deployment after triggering
  --help             Show this help message

Examples:
  $0                           # Interactive mode
  $0 dev                       # Deploy to dev with patch increment
  $0 prod --minor             # Deploy to production with minor version bump
  $0 staging --version 2.1.0  # Deploy specific version to staging
  $0 dev --rebuild            # Rebuild dev with same version
  $0 hotfix --message "Fix critical bug"  # Create hotfix deployment
  $0 rollback                 # Interactive rollback to previous version

Configuration:
  Create a .deploy.config file to customize:
    SERVICE_NAME="my-service"
    DEFAULT_BRANCH="main"
    DEPLOY_BRANCHES="main develop"
    
  Create a .deploy.config.local for personal overrides (gitignored)
EOF
}

# Show header
show_header() {
    echo ""
    print_color $BLUE "═══════════════════════════════════════════════════════════════"
    print_color $BLUE "              Karma Universal Deploy Tool (v3.0)               "
    print_color $BLUE "═══════════════════════════════════════════════════════════════"
    echo ""
    print_color $CYAN "📦 Service: $SERVICE_NAME"
    print_color $CYAN "🌿 Current branch: $(git branch --show-current)"
    echo ""
}

# Main deployment flow
main() {
    # Parse arguments
    local environment=""
    local increment_type="patch"
    local specific_version=""
    local message=""
    local preview_mode=false
    local rebuild_mode=false
    local monitor=true
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            dev|development)
                environment="development"
                shift
                ;;
            staging)
                environment="staging"
                shift
                ;;
            prod|production)
                environment="production"
                shift
                ;;
            hotfix)
                environment="hotfix"
                shift
                ;;
            rollback)
                # Launch rollback script
                SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                if [ -f "$SCRIPT_DIR/rollback.sh" ]; then
                    exec "$SCRIPT_DIR/rollback.sh" "$@"
                else
                    print_color $RED "Rollback script not found"
                    print_color $YELLOW "Please ensure rollback.sh is in the same directory as deploy.sh"
                    exit 1
                fi
                ;;
            --major)
                increment_type="major"
                shift
                ;;
            --minor)
                increment_type="minor"
                shift
                ;;
            --patch)
                increment_type="patch"
                shift
                ;;
            --version)
                specific_version="$2"
                shift 2
                ;;
            --rebuild)
                rebuild_mode=true
                shift
                ;;
            --message)
                message="$2"
                shift 2
                ;;
            --preview)
                preview_mode=true
                shift
                ;;
            --no-monitor)
                monitor=false
                MONITOR_DEPLOYMENT=false
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                print_color $RED "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Show header
    show_header
    
    # Interactive mode if no environment specified
    if [ -z "$environment" ]; then
        print_color $CYAN "Select action:"
        echo ""
        print_color $CYAN "  1) Development deployment (creates tag like v1.0.0-dev)"
        print_color $YELLOW "  2) Staging deployment (creates tag like v1.0.0-staging)"
        print_color $RED "  3) Production deployment (creates tag like v1.0.0)"
        print_color $MAGENTA "  4) Rollback to previous version"
        echo "  5) Cancel"
        echo ""
        read -p "Enter your choice (1-5): " choice
        
        case $choice in
            1)
                environment="development"
                ;;
            2)
                environment="staging"
                ;;
            3)
                environment="production"
                ;;
            4)
                # Launch rollback script
                SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                if [ -f "$SCRIPT_DIR/rollback.sh" ]; then
                    exec "$SCRIPT_DIR/rollback.sh"
                else
                    print_color $RED "Rollback script not found"
                    exit 1
                fi
                ;;
            5)
                print_color $YELLOW "Operation cancelled"
                exit 0
                ;;
            *)
                print_color $RED "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    # Convert environment shortcuts
    if [ "$environment" = "development" ]; then
        environment="dev"
    elif [ "$environment" = "production" ]; then
        environment="prod"
    fi
    
    # Special handling for hotfix
    if [ "$environment" = "hotfix" ]; then
        if [ "$ENABLE_HOTFIX" != "true" ]; then
            print_color $RED "Hotfix deployments are disabled for this service"
            exit 1
        fi
        environment="production"
        increment_type="patch"
        if [ -z "$message" ]; then
            message="Hotfix deployment"
        fi
    fi
    
    # Set environment color for display
    local env_color=""
    if [[ "$environment" == "prod" ]] || [[ "$environment" == "production" ]]; then
        env_color="${RED}"
    elif [[ "$environment" == "staging" ]]; then
        env_color="${YELLOW}"
    else
        env_color="${CYAN}"
    fi
    
    print_color $BLUE "🎯 Deployment target: ${env_color}$environment${NC}"
    echo ""
    
    # Check git status
    if [ "$(git status --porcelain)" ]; then
        print_color $YELLOW "⚠️  Warning: You have uncommitted changes"
        git status -s | head -10
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_color $RED "Deployment cancelled"
            exit 1
        fi
    fi
    
    # Check branch for production deployment
    if [[ "$environment" == "prod" ]] || [[ "$environment" == "production" ]]; then
        local current_branch=$(git branch --show-current)
        local is_valid_branch=false
        
        for branch in $DEPLOY_BRANCHES; do
            if [ "$current_branch" = "$branch" ]; then
                is_valid_branch=true
                break
            fi
        done
        
        if [ "$is_valid_branch" = false ]; then
            print_color $YELLOW "⚠️  Warning: Production deployment from branch '$current_branch'"
            print_color $YELLOW "   Usually done from: $DEPLOY_BRANCHES"
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_color $RED "Deployment cancelled"
                exit 1
            fi
        fi
    fi
    
    # Fetch latest tags
    print_color $BLUE "📥 Fetching latest tags..."
    git fetch --tags
    
    # Show recent tags
    print_color $BLUE "📋 Recent deployment tags:"
    git tag -l "${VERSION_PREFIX}*" --sort=-v:refname | head -5 | while read tag; do
        if [[ "$tag" == *"-dev" ]]; then
            echo "  $tag (development)"
        elif [[ "$tag" == *"-staging" ]]; then
            echo "  $tag (staging)"
        else
            echo "  $tag (production)"
        fi
    done
    echo ""
    
    # Determine version
    local new_version=""
    local latest_tag=$(get_latest_version "$environment")
    
    if [ "$rebuild_mode" = true ]; then
        # For rebuild, use the latest version without incrementing
        new_version=${latest_tag#${VERSION_PREFIX}}
        new_version=${new_version%-*}
        print_color $CYAN "🔄 Rebuild mode: Using existing version $new_version"
    elif [ -n "$specific_version" ]; then
        new_version="$specific_version"
        print_color $BLUE "📌 Using specified version: $new_version"
    else
        # Interactive version selection
        local current_version=${latest_tag#${VERSION_PREFIX}}
        current_version=${current_version%-*}
        
        print_color $BLUE "📊 Current version: $current_version"
        echo ""
        print_color $MAGENTA "Select version bump type:"
        echo ""
        print_color $GREEN "  1) Patch (bug fixes)        - $current_version → $(increment_version $current_version patch)"
        print_color $YELLOW "  2) Minor (new features)     - $current_version → $(increment_version $current_version minor)"
        print_color $RED "  3) Major (breaking changes) - $current_version → $(increment_version $current_version major)"
        print_color $CYAN "  4) Custom version"
        print_color $BLUE "  5) Rebuild (same version, new build)"
        echo "  6) Cancel"
        echo ""
        read -p "Enter your choice (1-6): " version_choice
        
        case $version_choice in
            1)
                new_version=$(increment_version "$current_version" "patch")
                ;;
            2)
                new_version=$(increment_version "$current_version" "minor")
                ;;
            3)
                new_version=$(increment_version "$current_version" "major")
                ;;
            4)
                read -p "Enter custom version (e.g., 2.1.0): " new_version
                if ! [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    print_color $RED "Invalid version format. Must be X.Y.Z"
                    exit 1
                fi
                ;;
            5)
                rebuild_mode=true
                new_version="$current_version"
                print_color $CYAN "🔄 Rebuild mode: Using existing version $new_version"
                ;;
            6)
                print_color $YELLOW "Deployment cancelled"
                exit 0
                ;;
            *)
                print_color $RED "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    # Production deployment confirmation
    if [[ "$environment" == "prod" ]] || [[ "$environment" == "production" ]]; then
        echo ""
        print_color $RED "╔═══════════════════════════════════════════════════════════════╗"
        print_color $RED "║              🚨 PRODUCTION DEPLOYMENT WARNING 🚨              ║"
        print_color $RED "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        print_color $YELLOW "You are about to deploy v$new_version to PRODUCTION!"
        echo ""
        print_color $YELLOW "Pre-deployment checklist:"
        echo "  □ All features tested in development"
        echo "  □ No breaking changes (or coordinated)"
        echo "  □ All tests passing"
        echo ""
        
        local confirm_tag="${VERSION_PREFIX}${new_version}"
        read -p "Type 'DEPLOY $confirm_tag' to confirm: " confirmation
        if [[ "$confirmation" != "DEPLOY $confirm_tag" ]]; then
            print_color $RED "Production deployment cancelled"
            exit 1
        fi
    fi
    
    # Preview mode
    if [ "$preview_mode" = true ] || [ "$ENABLE_PREVIEW" = "true" ]; then
        echo ""
        print_color $YELLOW "📋 Deployment Preview:"
        print_color $YELLOW "   • Service: $SERVICE_NAME"
        print_color $YELLOW "   • Environment: $environment"
        print_color $YELLOW "   • Version: $new_version"
        local preview_tag="${VERSION_PREFIX}${new_version}"
        if [ "$environment" = "staging" ]; then
            preview_tag="${preview_tag}-staging"
        elif [ "$environment" != "production" ] && [ "$environment" != "prod" ]; then
            preview_tag="${preview_tag}-dev"
        fi
        print_color $YELLOW "   • Tag: $preview_tag"
        print_color $YELLOW "   • Branch: $(git branch --show-current)"
        print_color $YELLOW "   • Commit: $(git rev-parse --short HEAD)"
        if [ "$rebuild_mode" = true ]; then
            print_color $YELLOW "   • Mode: REBUILD (same version, new build)"
        fi
        echo ""
        
        if [ "$preview_mode" = true ]; then
            print_color $GREEN "Preview mode - no changes made"
            exit 0
        fi
        
        read -p "Proceed with deployment? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_color $RED "Deployment cancelled"
            exit 1
        fi
    fi
    
    # Update package.json if not rebuilding
    if [ "$rebuild_mode" != true ] && [ -f "package.json" ]; then
        local current_pkg_version=$(get_current_version)
        if [ "$current_pkg_version" != "$new_version" ]; then
            print_color $BLUE "📝 Updating package.json version..."
            update_package_json "$new_version"
            
            # Commit the version change
            print_color $BLUE "📦 Committing version bump..."
            git add "package.json"
            git commit -m "chore: bump version to $new_version for $environment deployment

- Previous version: $current_pkg_version
- New version: $new_version
- Environment: $environment
- Bump type: $increment_type"
            
            # Push the commit
            print_color $BLUE "📤 Pushing version bump..."
            git push origin "$(git branch --show-current)" || true
        fi
    fi
    
    # Execute deployment
    deploy_version "$new_version" "$environment" "$message" "$rebuild_mode"
    
    # Post-deployment instructions
    echo ""
    print_color $BLUE "📝 Post-deployment checklist:"
    print_color $BLUE "   □ Monitor GitHub Actions for build status"
    if [ "$DEPLOY_TYPE" = "kubernetes" ]; then
        print_color $BLUE "   □ Check ArgoCD for sync status"
    fi
    print_color $BLUE "   □ Verify service health in the $environment environment"
    print_color $BLUE "   □ Run smoke tests if applicable"
    
    if [[ "$environment" == "prod" ]] || [[ "$environment" == "production" ]]; then
        print_color $YELLOW ""
        print_color $YELLOW "🚨 Production Deployment - Additional steps:"
        print_color $YELLOW "   □ Monitor error rates and performance metrics"
        print_color $YELLOW "   □ Be ready to rollback if issues arise"
        print_color $YELLOW "   □ Update release notes/changelog"
        print_color $YELLOW "   □ Notify team of production deployment"
    fi
    
    echo ""
    print_color $GREEN "🚀 Deployment script completed!"
}

# Run main function
main "$@"