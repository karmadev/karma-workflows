# Karma Reusable Workflows

Centralized GitHub Actions workflows for all Karma services. These reusable workflows provide consistent CI/CD patterns across all repositories.

## 🚀 Quick Start

### Step 1: Install Deploy Script

First, install the unified deploy script in your repository:

```bash
curl -sL https://raw.githubusercontent.com/karmadev/karma-workflows/main/scripts/install-deploy-script.sh | bash
```

This adds:
- `deploy.sh` - Universal deployment script
- `.deploy.config` - Service-specific configuration
- NPM scripts for easy deployment

### Step 2: Configure GitHub Actions

### For Node.js Kubernetes Services

Create `.github/workflows/ci-cd.yml` in your service repository:

```yaml
name: CI/CD Pipeline

on:
  push:
    tags:
      - 'v*'  # Trigger on version tags
  pull_request:
    branches:
      - master
      - main

jobs:
  pipeline:
    uses: karmadev/karma-workflows/.github/workflows/node-service-pipeline.yml@main
    with:
      service-name: your-service-name
      # Optional: For GraphQL services
      has-graphql: true
      apollo-graph: karma-merchant
      apollo-subgraph: Base
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
      GITOPS_TOKEN: ${{ secrets.GITOPS_TOKEN }}
      APOLLO_KEY: ${{ secrets.APOLLO_KEY_MERCHANT }}  # If GraphQL
```

### For Firebase Applications

```yaml
name: CI/CD Pipeline

on:
  push:
    tags:
      - 'v*'
  pull_request:
    branches:
      - master
      - main

jobs:
  pipeline:
    uses: karmadev/karma-workflows/.github/workflows/firebase-app-pipeline.yml@main
    with:
      project-name: your-app-name
      firebase-project-dev: karma-dev-project-id
      firebase-project-prod: karma-prod-project-id
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      FIREBASE_SERVICE_ACCOUNT_DEV: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_DEV }}
      FIREBASE_SERVICE_ACCOUNT_PROD: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_PROD }}
```

## 📦 Available Workflows

### Core Workflows

#### `determine-env.yml`
Determines deployment environment based on git tags.
- `v1.0.0` → production
- `v1.0.0-dev` → development
- `v1.0.0-staging` → staging

#### `node-test.yml`
Runs tests, linting, and type checking for Node.js projects.

#### `docker-build.yml`
Builds and pushes Docker images to Google Artifact Registry.

#### `deploy-k8s.yml`
Deploys services to Kubernetes via GitOps repository.

#### `deploy-firebase.yml`
Deploys applications to Firebase Hosting and Functions.

#### `deploy-cloud-functions.yml`
Deploys Google Cloud Functions.

#### `apollo-schema.yml`
Uploads GraphQL schemas to Apollo Studio.

### Orchestrator Workflows

#### `node-service-pipeline.yml`
Complete pipeline for Node.js services deploying to Kubernetes.

#### `firebase-app-pipeline.yml`
Complete pipeline for Firebase applications.

## 🏷️ Deployment Strategy

### Using the Deploy Script (Recommended)

The deploy script handles all tagging and deployment automatically:

```bash
# Deploy to development
npm run deploy:dev

# Deploy to staging
npm run deploy:staging

# Deploy to production
npm run deploy:prod

# Advanced options
./deploy.sh prod --minor           # Minor version bump
./deploy.sh staging --version 2.1.0  # Specific version
./deploy.sh hotfix --message "Fix bug"  # Hotfix deployment
```

### Manual Tagging

You can also manually create tags that trigger deployments:

```bash
# Deploy to production
git tag v1.0.0
git push origin v1.0.0

# Deploy to development
git tag v1.0.0-dev
git push origin v1.0.0-dev

# Deploy to staging
git tag v1.0.0-staging
git push origin v1.0.0-staging
```

## 🔑 Required Secrets

Configure these secrets in your repository settings:

### For Kubernetes Services
- `NPM_TOKEN` - NPM authentication for private packages
- `GCP_SA_KEY` - Service account JSON for GCP/Docker
- `GITOPS_TOKEN` - GitHub token for GitOps repo access
- `APOLLO_KEY_*` - Apollo Studio API key (for GraphQL services)

### For Firebase Projects
- `NPM_TOKEN` - NPM authentication
- `FIREBASE_SERVICE_ACCOUNT_DEV` - Firebase SA for development
- `FIREBASE_SERVICE_ACCOUNT_PROD` - Firebase SA for production

## 📚 Usage Examples

### Basic Node.js Service

```yaml
name: CI/CD Pipeline

on:
  push:
    tags:
      - 'v*'

jobs:
  pipeline:
    uses: karmadev/karma-workflows/.github/workflows/node-service-pipeline.yml@main
    with:
      service-name: inventory-service
    secrets: inherit  # Inherit all secrets from caller
```

### Node.js Service with GraphQL

```yaml
jobs:
  pipeline:
    uses: karmadev/karma-workflows/.github/workflows/node-service-pipeline.yml@main
    with:
      service-name: karma-merchant-api
      has-graphql: true
      apollo-graph: karma-merchant
      apollo-subgraph: Base
      working-directory: backend
    secrets: inherit
```

### React/Next.js to Firebase

```yaml
jobs:
  pipeline:
    uses: karmadev/karma-workflows/.github/workflows/firebase-app-pipeline.yml@main
    with:
      project-name: storefront-web
      firebase-project-dev: karma-dev-abc123
      firebase-project-prod: karma-prod-xyz789
      build-command: npm run build:production
    secrets: inherit
```

### Cloud Functions

```yaml
name: Deploy Cloud Functions

on:
  push:
    tags:
      - 'v*'

jobs:
  determine:
    uses: karmadev/karma-workflows/.github/workflows/determine-env.yml@main
  
  deploy:
    needs: determine
    if: needs.determine.outputs.should-deploy == 'true'
    uses: karmadev/karma-workflows/.github/workflows/deploy-cloud-functions.yml@main
    with:
      function-name: printer-function
      environment: ${{ needs.determine.outputs.environment }}
      runtime: nodejs18
      memory: 512MB
      timeout: 120
      region: europe-north1
    secrets:
      GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

## 🔧 Customization

### Custom Working Directory

For monorepos or non-standard structures:

```yaml
with:
  service-name: my-service
  working-directory: backend  # or services/my-service
```

### Skip Tests or Linting

```yaml
with:
  service-name: my-service
  run-lint: false
  run-typecheck: false
```

### Custom Node Version

```yaml
with:
  service-name: my-service
  node-version: '20'
```

## 🏗️ Migration Guide

### From Existing Workflows

1. **Identify your service type**:
   - Kubernetes service → Use `node-service-pipeline.yml`
   - Firebase app → Use `firebase-app-pipeline.yml`
   - Cloud Functions → Use `deploy-cloud-functions.yml`

2. **Update your workflow file**:
   ```yaml
   # Replace entire jobs section with:
   jobs:
     pipeline:
       uses: karmadev/karma-workflows/.github/workflows/[workflow-name].yml@main
       with:
         service-name: your-service
         # Add other required inputs
       secrets: inherit
   ```

3. **Ensure secrets are configured**:
   - Check repository settings → Secrets
   - Add any missing secrets

4. **Test with a dev tag**:
   ```bash
   git tag v0.0.1-dev
   git push origin v0.0.1-dev
   ```

## 🐛 Troubleshooting

### Workflow not found
- Ensure `karma-workflows` repository is accessible
- Check the workflow path is correct
- Verify you're using `@main` branch reference

### Missing secrets
- Check repository settings for required secrets
- Use `secrets: inherit` to pass all secrets

### Docker build fails
- Verify `NPM_TOKEN` is set for private packages
- Check Dockerfile path and context

### GitOps deployment fails
- Ensure `GITOPS_TOKEN` has write access to gitops repo
- Verify service directory exists in gitops repo

## 📝 Contributing

To add or modify workflows:

1. Clone this repository
2. Create/edit workflows in `.github/workflows/`
3. Test changes in a sample repository
4. Submit PR with documentation updates

## 📄 License

Internal use only - Karma Restaurant Platform