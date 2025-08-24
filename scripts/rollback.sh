#!/bin/bash

################################################################################
# Karma Universal Rollback Tool
# Version: 1.0.0
# 
# This script allows rolling back to previous deployments by redeploying
# previously successful versions from git tags or Docker images
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SERVICE_NAME="${SERVICE_NAME:-$(basename $(pwd))}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
MAX_VERSIONS_TO_SHOW="${MAX_VERSIONS_TO_SHOW:-20}"

# Load configuration if exists
if [ -f ".deploy.config" ]; then
    source .deploy.config
fi

if [ -f ".deploy.config.local" ]; then
    source .deploy.config.local
fi

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to show header
show_header() {
    print_color $BLUE "═══════════════════════════════════════════════════════════════"
    print_color $BLUE "              Karma Universal Rollback Tool (v1.0)             "
    print_color $BLUE "═══════════════════════════════════════════════════════════════"
    echo ""
    print_color $CYAN "📦 Service: $SERVICE_NAME"
    print_color $CYAN "🌿 Current branch: $(git branch --show-current)"
    echo ""
}

# Function to get deployment history from git tags
get_deployment_history() {
    local environment=$1
    local env_suffix=""
    
    case "$environment" in
        development|dev)
            env_suffix="-dev"
            ;;
        staging)
            env_suffix="-staging"
            ;;
        production|prod)
            env_suffix=""
            ;;
    esac
    
    # Get tags with deployment info
    if [ "$env_suffix" = "" ]; then
        # Production: tags without suffix (v1.0.0)
        git tag -l "v*" --sort=-version:refname | grep -v "\-dev\|\-staging" | head -n $MAX_VERSIONS_TO_SHOW
    else
        # Dev/Staging: tags with suffix (v1.0.0-dev)
        git tag -l "v*${env_suffix}" --sort=-version:refname | head -n $MAX_VERSIONS_TO_SHOW
    fi
}

# Function to get deployment info for a tag
get_tag_info() {
    local tag=$1
    local commit=$(git rev-list -n 1 "$tag" 2>/dev/null || echo "")
    local date=$(git log -1 --format=%ci "$tag" 2>/dev/null || echo "")
    local author=$(git log -1 --format=%an "$tag" 2>/dev/null || echo "")
    local message=$(git tag -l --format='%(contents:subject)' "$tag" 2>/dev/null || echo "")
    
    echo "$date|$author|$message|$commit"
}

# Function to check GitHub Actions status for a tag
check_deployment_status() {
    local tag=$1
    
    if command -v gh &> /dev/null; then
        # Try to find workflow run for this tag
        local workflow_info=$(gh run list --limit 50 --json databaseId,status,conclusion,headBranch 2>/dev/null | \
            jq -r ".[] | select(.headBranch == \"refs/tags/$tag\" or .headBranch == \"$tag\") | \"\(.conclusion)\"" | head -n 1)
        
        if [ -n "$workflow_info" ]; then
            echo "$workflow_info"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Function to check if service supports staging
has_staging_environment() {
    local service=$1
    local staging_services=("karma-merchant-api" "karma-merchant-web" "storefront-service" "storefront-web")
    
    for s in "${staging_services[@]}"; do
        if [[ "$service" == "$s" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to select environment
select_environment() {
    print_color $CYAN "Select environment to rollback:"
    echo ""
    print_color $CYAN "  1) Development"
    
    # Only show staging if this service supports it
    if has_staging_environment "$SERVICE_NAME"; then
        print_color $YELLOW "  2) Staging"
        print_color $RED "  3) Production"
        echo "  4) Cancel"
        echo ""
        read -p "Enter your choice (1-4): " choice
        
        case $choice in
            1)
                echo "development"
                ;;
            2)
                echo "staging"
                ;;
            3)
                echo "production"
                ;;
            *)
                print_color $RED "Rollback cancelled"
                exit 0
                ;;
        esac
    else
        print_color $RED "  2) Production"
        echo "  3) Cancel"
        echo ""
        read -p "Enter your choice (1-3): " choice
        
        case $choice in
            1)
                echo "development"
                ;;
            2)
                echo "production"
                ;;
            *)
                print_color $RED "Rollback cancelled"
                exit 0
                ;;
        esac
    fi
}

# Function to select version to rollback to
select_version() {
    local environment=$1
    local versions=($(get_deployment_history "$environment"))
    
    if [ ${#versions[@]} -eq 0 ]; then
        print_color $RED "❌ No previous deployments found for $environment"
        exit 1
    fi
    
    print_color $CYAN "📋 Recent deployments for $environment:"
    echo ""
    
    # Get current deployed version (latest tag for this environment)
    local current_version="${versions[0]}"
    
    # Display versions with details
    local index=1
    for version in "${versions[@]}"; do
        local info=$(get_tag_info "$version")
        IFS='|' read -r date author message commit <<< "$info"
        local status=$(check_deployment_status "$version")
        
        # Format status indicator
        local status_indicator=""
        case "$status" in
            success)
                status_indicator="${GREEN}✓${NC}"
                ;;
            failure)
                status_indicator="${RED}✗${NC}"
                ;;
            *)
                status_indicator="${YELLOW}?${NC}"
                ;;
        esac
        
        # Format display
        if [ "$version" = "$current_version" ] && [ $index -eq 1 ]; then
            print_color $GREEN "  $index) $version $status_indicator [CURRENT]"
        else
            echo -e "  $index) $version $status_indicator"
        fi
        
        # Show details
        if [ -n "$date" ]; then
            echo "     📅 Date: $(echo $date | cut -d' ' -f1-2)"
        fi
        if [ -n "$author" ]; then
            echo "     👤 Author: $author"
        fi
        if [ -n "$message" ] && [ "$message" != "$version" ]; then
            echo "     💬 Message: $message"
        fi
        if [ -n "$commit" ]; then
            echo "     🔗 Commit: ${commit:0:8}"
        fi
        echo ""
        
        index=$((index + 1))
    done
    
    echo "  0) Cancel"
    echo ""
    read -p "Select version to rollback to (0-$((${#versions[@]})): " choice
    
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        print_color $RED "Rollback cancelled"
        exit 0
    elif [ "$choice" -ge 1 ] && [ "$choice" -le ${#versions[@]} ] 2>/dev/null; then
        echo "${versions[$((choice-1))]}"
    else
        print_color $RED "Invalid selection"
        exit 1
    fi
}

# Function to confirm rollback
confirm_rollback() {
    local environment=$1
    local from_version=$2
    local to_version=$3
    
    echo ""
    print_color $YELLOW "⚠️  ROLLBACK CONFIRMATION"
    print_color $YELLOW "═══════════════════════════════════════════"
    echo ""
    print_color $CYAN "Environment: ${BOLD}$environment${NC}"
    print_color $CYAN "Current version: ${BOLD}$from_version${NC}"
    print_color $CYAN "Rollback to: ${BOLD}$to_version${NC}"
    echo ""
    
    # Show what changed between versions
    local changes=$(git log --oneline "$to_version..$from_version" 2>/dev/null | head -5)
    if [ -n "$changes" ]; then
        print_color $YELLOW "Changes that will be rolled back:"
        echo "$changes" | while read line; do
            echo "  • $line"
        done
        echo ""
    fi
    
    if [ "$environment" = "production" ]; then
        print_color $RED "🔴 THIS IS A PRODUCTION ROLLBACK!"
        print_color $RED "   All changes since $to_version will be reverted."
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_color $RED "Rollback cancelled"
        exit 0
    fi
}

# Function to perform rollback
perform_rollback() {
    local environment=$1
    local version=$2
    local rollback_method=${3:-"tag"}  # tag or docker
    
    print_color $GREEN "🔄 Starting rollback to $version..."
    echo ""
    
    if [ "$rollback_method" = "tag" ]; then
        # Method 1: Create new tag pointing to old version
        local rollback_tag="rollback-${environment}-$(date +%Y%m%d-%H%M%S)"
        local new_tag=""
        
        # Determine new tag format based on environment
        case "$environment" in
            development|dev)
                new_tag="$version-rollback-$(date +%s)"
                ;;
            staging)
                new_tag="$version-rollback-$(date +%s)"
                ;;
            production|prod)
                new_tag="$version-rollback-$(date +%s)"
                ;;
        esac
        
        # Create annotated tag at the same commit as the version we're rolling back to
        local commit=$(git rev-list -n 1 "$version")
        local message="Rollback to $version on $environment by $(git config user.name || echo $USER)"
        
        print_color $BLUE "📌 Creating rollback tag: $new_tag"
        git tag -a "$new_tag" "$commit" -m "$message"
        
        print_color $BLUE "📤 Pushing rollback tag to trigger deployment..."
        git push origin "$new_tag"
        
        # Monitor deployment
        if command -v gh &> /dev/null; then
            print_color $BLUE "📊 Monitoring rollback deployment..."
            sleep 5
            
            # Try to find the workflow run
            local workflow_id=$(gh run list --limit 5 --json databaseId,headBranch 2>/dev/null | \
                jq -r ".[] | select(.headBranch == \"refs/tags/$new_tag\" or .headBranch == \"$new_tag\") | .databaseId" | head -n 1)
            
            if [ -n "$workflow_id" ]; then
                print_color $GREEN "✓ Found workflow run #$workflow_id"
                print_color $BLUE "📊 Watching rollback progress..."
                echo ""
                
                # Watch the run
                gh run watch "$workflow_id" --interval 5 2>/dev/null || true
                
                # Get final status
                local workflow_info=$(gh run view "$workflow_id" --json status,conclusion 2>/dev/null)
                local workflow_conclusion=$(echo "$workflow_info" | jq -r '.conclusion')
                
                if [ "$workflow_conclusion" = "success" ]; then
                    print_color $GREEN "✅ Rollback completed successfully!"
                else
                    print_color $RED "❌ Rollback deployment failed"
                    print_color $YELLOW "Check the logs for details"
                fi
            else
                print_color $YELLOW "⚠️  Could not find workflow run. Monitor manually at:"
                print_color $YELLOW "   https://github.com/$(git remote get-url origin | sed -E 's/.*github.com[:\\/](.+)\\.git/\\1/')/actions"
            fi
        fi
        
    elif [ "$rollback_method" = "docker" ]; then
        # Method 2: Direct Docker image rollback (for services using GitOps)
        print_color $BLUE "🐳 Rolling back using Docker image from $version..."
        
        # This would require updating the GitOps repository directly
        # Implementation depends on your GitOps structure
        print_color $YELLOW "Docker-based rollback requires GitOps integration"
        print_color $YELLOW "Please implement based on your GitOps structure"
    fi
    
    # Log rollback
    echo ""
    print_color $GREEN "📝 Rollback initiated:"
    print_color $GREEN "   • Environment: $environment"
    print_color $GREEN "   • Rolled back to: $version"
    print_color $GREEN "   • Initiated by: $(git config user.name || echo $USER)"
    print_color $GREEN "   • Timestamp: $(date)"
}

# Function to show recent rollbacks
show_rollback_history() {
    print_color $CYAN "📜 Recent rollbacks:"
    echo ""
    
    # Find rollback tags
    local rollback_tags=$(git tag -l "*rollback*" --sort=-version:refname | head -10)
    
    if [ -z "$rollback_tags" ]; then
        print_color $YELLOW "No rollbacks found"
    else
        echo "$rollback_tags" | while read tag; do
            if [ -n "$tag" ]; then
                local info=$(get_tag_info "$tag")
                IFS='|' read -r date author message commit <<< "$info"
                print_color $CYAN "• $tag"
                echo "  Date: $(echo $date | cut -d' ' -f1-2)"
                echo "  Message: $message"
                echo ""
            fi
        done
    fi
}

# Main function
main() {
    show_header
    
    # Parse command line arguments
    local environment=""
    local version=""
    local skip_confirm=false
    local show_history=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                environment="$2"
                shift 2
                ;;
            --version)
                version="$2"
                shift 2
                ;;
            --skip-confirm)
                skip_confirm=true
                shift
                ;;
            --history)
                show_history=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                environment="$1"
                shift
                ;;
        esac
    done
    
    # Show rollback history if requested
    if [ "$show_history" = true ]; then
        show_rollback_history
        exit 0
    fi
    
    # Interactive mode if no environment specified
    if [ -z "$environment" ]; then
        environment=$(select_environment)
    fi
    
    # Normalize environment name
    case "$environment" in
        dev)
            environment="development"
            ;;
        prod)
            environment="production"
            ;;
    esac
    
    # Check if staging is supported for this service
    if [ "$environment" = "staging" ]; then
        if ! has_staging_environment "$SERVICE_NAME"; then
            print_color $RED "❌ Service $SERVICE_NAME does not support staging environment"
            print_color $YELLOW "Staging is only available for:"
            print_color $YELLOW "  • karma-merchant-api"
            print_color $YELLOW "  • karma-merchant-web"
            print_color $YELLOW "  • storefront-service"
            print_color $YELLOW "  • storefront-web"
            exit 1
        fi
    fi
    
    print_color $MAGENTA "🎯 Rollback target: $environment"
    echo ""
    
    # Get current version
    local current_version=$(get_deployment_history "$environment" | head -1)
    
    if [ -z "$current_version" ]; then
        print_color $RED "❌ No deployments found for $environment"
        exit 1
    fi
    
    # Select version if not specified
    if [ -z "$version" ]; then
        version=$(select_version "$environment")
    fi
    
    # Validate version exists
    if ! git rev-parse "$version" >/dev/null 2>&1; then
        print_color $RED "❌ Version $version does not exist"
        exit 1
    fi
    
    # Confirm rollback
    if [ "$skip_confirm" = false ]; then
        confirm_rollback "$environment" "$current_version" "$version"
    fi
    
    # Perform rollback
    perform_rollback "$environment" "$version"
    
    echo ""
    print_color $GREEN "═══════════════════════════════════════════════════════════════"
    print_color $GREEN "                    Rollback Complete!                          "
    print_color $GREEN "═══════════════════════════════════════════════════════════════"
}

# Function to show usage
show_usage() {
    cat << EOF
Karma Rollback Script v1.0

Usage: $0 [environment] [options]

Environments:
  dev, development    Rollback development environment
  staging            Rollback staging environment (only for supported services)
  prod, production   Rollback production environment

Note: Staging is only available for:
  • karma-merchant-api
  • karma-merchant-web
  • storefront-service
  • storefront-web

Options:
  --version VERSION  Specific version to rollback to
  --skip-confirm     Skip confirmation prompt
  --history          Show rollback history
  --help             Show this help message

Examples:
  $0                                    # Interactive mode
  $0 production                         # Rollback production interactively
  $0 dev --version v1.2.3-dev          # Rollback dev to specific version
  $0 --history                         # Show rollback history

Configuration:
  Create a .deploy.config file to customize:
    SERVICE_NAME="my-service"
    DEFAULT_BRANCH="main"
    MAX_VERSIONS_TO_SHOW=20
EOF
}

# Run main function
main "$@"