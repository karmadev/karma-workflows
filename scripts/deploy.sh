#!/bin/bash

# Karma Universal Deploy Script
# Version: 2.0.0
# 
# This script handles version tagging and deployment for all Karma services
# It automatically detects the service type and applies appropriate deployment strategies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to check if we're on a deployable branch
check_branch() {
    local current_branch=$(git branch --show-current)
    local is_valid=false
    
    for branch in $DEPLOY_BRANCHES; do
        if [ "$current_branch" = "$branch" ]; then
            is_valid=true
            break
        fi
    done
    
    if [ "$is_valid" = false ]; then
        print_color $YELLOW "⚠️  Warning: You're on branch '$current_branch'"
        print_color $YELLOW "   Deployments are typically done from: $DEPLOY_BRANCHES"
        read -p "Do you want to continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_color $RED "Deployment cancelled"
            exit 1
        fi
    fi
}

# Function to get the latest version tag
get_latest_version() {
    local env=$1
    local latest_tag=""
    
    if [ "$env" = "production" ]; then
        # Get latest production version (without suffix)
        latest_tag=$(git tag -l "${VERSION_PREFIX}*" | grep -E "^${VERSION_PREFIX}[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1)
    else
        # Get latest version for specific environment
        latest_tag=$(git tag -l "${VERSION_PREFIX}*-${env}" | sort -V | tail -n 1)
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
    
    # Increment based on type
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

# Function to create and push tag
deploy_version() {
    local version=$1
    local env=$2
    local message=$3
    
    # Construct the full tag
    local tag="${VERSION_PREFIX}${version}"
    if [ "$env" != "production" ]; then
        tag="${tag}-${env}"
    fi
    
    print_color $BLUE "📦 Creating deployment tag: $tag"
    
    # Create annotated tag
    if [ -z "$message" ]; then
        message="Deploy $SERVICE_NAME $version to $env"
    fi
    
    git tag -a "$tag" -m "$message"
    
    print_color $BLUE "🚀 Pushing tag to trigger deployment..."
    git push origin "$tag"
    
    print_color $GREEN "✅ Deployment initiated successfully!"
    print_color $GREEN "   Tag: $tag"
    print_color $GREEN "   Environment: $env"
    print_color $GREEN "   Version: $version"
    echo ""
    
    # Check if we should monitor the deployment
    if [ "${MONITOR_DEPLOYMENT:-true}" = "true" ]; then
        print_color $YELLOW "📊 Monitoring deployment..."
        monitor_github_actions "$tag"
    else
        print_color $YELLOW "📊 Monitor deployment:"
        print_color $YELLOW "   • GitHub Actions: https://github.com/karmadev/$SERVICE_NAME/actions"
        print_color $YELLOW "   • ArgoCD: https://argocd.karma.life"
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
    
    print_color $BLUE "⏳ Waiting for GitHub Actions to start..."
    
    # Wait for workflow to start
    while [ $check_count -lt 10 ]; do
        check_count=$((check_count + 1))
        
        # Try to find the workflow run using gh CLI if available
        if command -v gh &> /dev/null; then
            # Get the latest workflow run for this tag
            workflow_info=$(gh run list --limit 5 --json databaseId,status,headBranch,name 2>/dev/null | \
                jq -r ".[] | select(.headBranch == \"refs/tags/$tag\") | \"\(.databaseId)|\(.status)\"" | head -n 1)
            
            if [ -n "$workflow_info" ]; then
                workflow_id=$(echo "$workflow_info" | cut -d'|' -f1)
                workflow_status=$(echo "$workflow_info" | cut -d'|' -f2)
                workflow_found=true
                break
            fi
        fi
        
        sleep 2
    done
    
    if [ "$workflow_found" = false ]; then
        print_color $YELLOW "⚠️  GitHub CLI not available or workflow not found"
        print_color $YELLOW "   Monitor manually at: https://github.com/karmadev/$SERVICE_NAME/actions"
        return
    fi
    
    print_color $GREEN "✓ Found workflow run #$workflow_id"
    print_color $BLUE "📊 Monitoring deployment progress..."
    echo ""
    
    # Monitor the workflow
    local last_status=""
    check_count=0
    
    while [ $check_count -lt $max_checks ]; do
        check_count=$((check_count + 1))
        
        # Get current workflow status
        workflow_info=$(gh run view $workflow_id --json status,conclusion,jobs 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            print_color $RED "Failed to get workflow status"
            break
        fi
        
        workflow_status=$(echo "$workflow_info" | jq -r '.status')
        workflow_conclusion=$(echo "$workflow_info" | jq -r '.conclusion')
        
        # Get job statuses
        job_statuses=$(echo "$workflow_info" | jq -r '.jobs[] | "  • \(.name): \(.status)"')
        
        # Only update display if status changed
        if [ "$workflow_status" != "$last_status" ]; then
            clear_lines 10  # Clear previous status lines
            print_color $BLUE "Status: $workflow_status"
            echo "$job_statuses"
            last_status="$workflow_status"
        fi
        
        # Check if completed
        if [ "$workflow_status" = "completed" ]; then
            echo ""
            if [ "$workflow_conclusion" = "success" ]; then
                print_color $GREEN "🎉 Deployment completed successfully!"
                print_color $GREEN "   View run: https://github.com/karmadev/$SERVICE_NAME/actions/runs/$workflow_id"
                
                # Additional monitoring for Kubernetes deployments
                if [ "$DEPLOY_TYPE" = "kubernetes" ]; then
                    echo ""
                    print_color $BLUE "⏳ Waiting for ArgoCD sync (this may take 2-3 minutes)..."
                    sleep 10
                    print_color $YELLOW "📊 Check ArgoCD status at: https://argocd.karma.life"
                fi
            else
                print_color $RED "❌ Deployment failed with status: $workflow_conclusion"
                print_color $RED "   View logs: https://github.com/karmadev/$SERVICE_NAME/actions/runs/$workflow_id"
                exit 1
            fi
            break
        fi
        
        # Wait before next check
        sleep 10
    done
    
    if [ $check_count -eq $max_checks ]; then
        print_color $YELLOW "⏱️  Monitoring timeout - deployment is still running"
        print_color $YELLOW "   Continue monitoring at: https://github.com/karmadev/$SERVICE_NAME/actions/runs/$workflow_id"
    fi
}

# Helper function to clear lines
clear_lines() {
    local lines=$1
    for i in $(seq 1 $lines); do
        tput cuu1
        tput el
    done 2>/dev/null || true
}

# Function to show usage
show_usage() {
    cat << EOF
Karma Deploy Script v2.0.0

Usage: $0 [environment] [options]

Environments:
  dev, development    Deploy to development environment
  staging            Deploy to staging environment  
  prod, production   Deploy to production environment
  hotfix             Create a hotfix deployment

Options:
  --major            Increment major version (X.0.0)
  --minor            Increment minor version (x.X.0)
  --patch            Increment patch version (x.x.X) [default]
  --version VERSION  Use specific version number
  --message MESSAGE  Custom tag message
  --preview          Preview the deployment without executing
  --help             Show this help message

Examples:
  $0 dev                    # Deploy to dev with patch increment
  $0 prod --minor          # Deploy to production with minor version bump
  $0 staging --version 2.1.0  # Deploy specific version to staging
  $0 hotfix --message "Fix critical bug"  # Create hotfix deployment

Configuration:
  Create a .deploy.config file to customize:
    SERVICE_NAME="my-service"
    DEFAULT_BRANCH="main"
    DEPLOY_BRANCHES="main develop"
EOF
}

# Main deployment flow
main() {
    # Parse arguments
    local environment=""
    local increment_type="patch"
    local specific_version=""
    local message=""
    local preview_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            dev|development)
                environment="dev"
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
            --message)
                message="$2"
                shift 2
                ;;
            --preview)
                preview_mode=true
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
    
    # Validate environment
    if [ -z "$environment" ]; then
        print_color $RED "Error: No environment specified"
        show_usage
        exit 1
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
    
    print_color $BLUE "🔍 Karma Deploy Script v2.0.0"
    print_color $BLUE "   Service: $SERVICE_NAME"
    print_color $BLUE "   Environment: $environment"
    echo ""
    
    # Check git status
    if [ "$(git status --porcelain)" ]; then
        print_color $YELLOW "⚠️  Warning: You have uncommitted changes"
        read -p "Do you want to continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_color $RED "Deployment cancelled"
            exit 1
        fi
    fi
    
    # Check branch
    check_branch
    
    # Fetch latest tags
    print_color $BLUE "📥 Fetching latest tags..."
    git fetch --tags
    
    # Determine version
    local new_version=""
    if [ -n "$specific_version" ]; then
        new_version="$specific_version"
        print_color $BLUE "📌 Using specified version: $new_version"
    else
        # Get latest version for the environment
        local latest_version=$(get_latest_version "$environment")
        print_color $BLUE "📊 Latest version: $latest_version"
        
        # Increment version
        new_version=$(increment_version "$latest_version" "$increment_type")
        print_color $BLUE "📈 New version: $new_version"
    fi
    
    # Preview mode
    if [ "$preview_mode" = true ] || [ "$ENABLE_PREVIEW" = "true" ]; then
        echo ""
        print_color $YELLOW "📋 Deployment Preview:"
        print_color $YELLOW "   • Service: $SERVICE_NAME"
        print_color $YELLOW "   • Environment: $environment"
        print_color $YELLOW "   • Version: $new_version"
        print_color $YELLOW "   • Tag: ${VERSION_PREFIX}${new_version}$([ "$environment" != "production" ] && echo "-$environment")"
        print_color $YELLOW "   • Branch: $(git branch --show-current)"
        print_color $YELLOW "   • Commit: $(git rev-parse --short HEAD)"
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
    
    # Execute deployment
    deploy_version "$new_version" "$environment" "$message"
    
    # Post-deployment instructions
    echo ""
    print_color $BLUE "📝 Post-deployment checklist:"
    print_color $BLUE "   □ Monitor GitHub Actions for build status"
    print_color $BLUE "   □ Check ArgoCD for sync status"
    print_color $BLUE "   □ Verify service health in the $environment environment"
    print_color $BLUE "   □ Run smoke tests if applicable"
    
    if [ "$environment" = "production" ]; then
        print_color $YELLOW ""
        print_color $YELLOW "🚨 Production Deployment - Additional steps:"
        print_color $YELLOW "   □ Monitor error rates and performance metrics"
        print_color $YELLOW "   □ Be ready to rollback if issues arise"
        print_color $YELLOW "   □ Update release notes/changelog"
        print_color $YELLOW "   □ Notify team of production deployment"
    fi
}

# Run main function
main "$@"