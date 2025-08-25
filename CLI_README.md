# Karma Deploy CLI

A comprehensive CLI tool for managing CI/CD pipelines and deployment configurations across all Karma services.

## Features

- 🔍 **Intelligent Project Detection**: Automatically detects project type, deployment method, and required environments
- 🏗️ **Buildkite Analysis**: Analyzes existing Buildkite pipelines to ensure no steps are missed during migration
- 🚀 **Automated Migration**: Migrates from Buildkite to GitHub Actions with full feature parity
- 📦 **Smart Staging Detection**: Knows which services require staging environments
- 🔄 **Update Management**: Keep deployment scripts and workflows up to date
- 📊 **Comprehensive Analysis**: Detailed reports on project configuration and CI/CD setup

## Installation

### Option 1: Global Installation (Recommended)

```bash
# Clone the repository
git clone https://github.com/karmadev/karma-workflows.git ~/karma-workflows

# Install dependencies
cd ~/karma-workflows
npm install

# Create global symlink
npm link

# Now you can use the CLI anywhere
karma --version
```

### Option 2: Local Installation

```bash
# In your project directory
git clone https://github.com/karmadev/karma-workflows.git .karma-workflows
cd .karma-workflows && npm install && cd ..

# Use with npx
npx .karma-workflows/cli/index.js init
```

## Commands

### `karma init`

Initialize deployment configuration for your project.

```bash
karma init                  # Interactive setup
karma init --staging        # Include staging environment
karma init --analyze        # Analyze Buildkite pipeline if present
karma init --force          # Overwrite existing configuration
```

**What it does:**
- Detects project type and configuration
- Analyzes existing Buildkite pipeline (if present)
- Installs deploy.sh script
- Creates GitHub Actions workflow
- Sets up staging environment (if needed)
- Lists required GitHub secrets

### `karma migrate`

Migrate from Buildkite to GitHub Actions.

```bash
karma migrate               # Full migration
karma migrate --dry-run     # Preview changes without applying
karma migrate --keep-buildkite  # Keep Buildkite files after migration
```

**What it does:**
- Analyzes Buildkite pipeline.nix
- Extracts all build arguments and secrets
- Creates equivalent GitHub Actions workflow
- Preserves all deployment steps and environments
- Provides migration checklist

### `karma analyze`

Analyze current CI/CD setup and provide recommendations.

```bash
karma analyze               # Human-readable analysis
karma analyze --json        # JSON output for automation
karma analyze --verbose     # Detailed analysis with all secrets
```

**Output includes:**
- Project type and deployment method
- Detected features (GraphQL, Sentry, Docker, etc.)
- Current CI/CD configuration
- Buildkite pipeline analysis
- Migration readiness assessment
- Recommendations for improvements

### `karma update`

Update deployment scripts and workflows to the latest version.

```bash
karma update                # Update everything
karma update --check        # Check for updates without applying
karma update --scripts-only # Only update local scripts
karma update --workflows-only # Only update GitHub Actions
```

### `karma info`

Display information about the current project.

```bash
karma info                  # Show project detection results
```

## Project Detection

The CLI automatically detects:

### Project Types
- Next.js applications
- React applications (Gatsby, CRA)
- Node.js services
- Cloud Functions
- Firebase projects

### Deployment Methods
- Kubernetes (with Kustomize)
- Firebase Hosting
- Google Cloud Functions

### Features
- GraphQL/Apollo integration
- Sentry error tracking
- Docker containerization
- Test suites
- Linting and type checking
- Database connections

### Staging Requirements

The CLI knows which services use staging:
- ✅ **With Staging**: storefront-web, storefront-service, karma-merchant-web, karma-merchant-api
- ❌ **Without Staging**: admin services, payment-service, inventory-service, other supporting services

## Example Workflows

### New Service Setup

```bash
# In your new service directory
karma init

# Follow the prompts, then:
# 1. Add secrets to GitHub
# 2. Configure environments in GitHub
# 3. Test deployment
npm run deploy:dev
```

### Migrating from Buildkite

```bash
# Analyze current setup
karma analyze

# Perform migration
karma migrate

# The tool will:
# - Parse .buildkite/pipeline.nix
# - Extract all configuration
# - Create equivalent GitHub Actions
# - List required secrets
# - Provide migration checklist
```

### Keeping Scripts Updated

```bash
# Check for updates
karma update --check

# Apply updates
karma update

# Verify changes
git diff deploy.sh .github/workflows/ci-cd.yml
```

## Required GitHub Secrets

After running `karma init` or `karma migrate`, configure these secrets in your GitHub repository:

### Base Secrets (All Services)
- `NPM_TOKEN` - NPM authentication for private packages
- `GCP_SA_KEY` - Service account key for GCP deployment
- `GITOPS_TOKEN` - GitHub token for GitOps repository

### Optional Secrets (Based on Features)
- `SENTRY_AUTH_TOKEN` - For Sentry release tracking
- `FONTAWESOME_NPM_TOKEN` - For FontAwesome Pro icons
- `STOREFRONT_PUBLIC_GOOGLE_MAPS_KEY` - For Google Maps integration
- `APOLLO_KEY` - For GraphQL schema registry

## GitHub Environments

Configure these environments in Settings → Environments:

1. **development** - Auto-deploy from dev tags
2. **production** - Manual approval required
3. **staging** - (If applicable) Between dev and prod

## Troubleshooting

### Command not found

If `karma` command is not found after installation:

```bash
# Check if npm link worked
which karma

# If not, add to PATH manually
echo 'alias karma="node ~/karma-workflows/cli/index.js"' >> ~/.bashrc
source ~/.bashrc
```

### Permission denied

```bash
# Make scripts executable
chmod +x ~/karma-workflows/cli/index.js
chmod +x ./deploy.sh
```

### Buildkite analysis fails

The tool supports `.nix` pipeline files. If you have a different format:

```bash
# Run generic initialization
karma init --force
```

## Development

To contribute to the CLI:

```bash
# Clone and install
git clone https://github.com/karmadev/karma-workflows.git
cd karma-workflows
npm install

# Make changes to cli/ directory

# Test locally
node cli/index.js analyze

# Create PR
```

## Support

For issues or questions:
- Create an issue in the karma-workflows repository
- Contact the platform team

## Version History

- **1.0.0** - Initial release with init, migrate, analyze, update commands
- **1.1.0** - Added staging environment detection
- **1.2.0** - Improved Buildkite .nix parsing