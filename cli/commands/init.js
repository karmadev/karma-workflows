const fs = require('fs');
const path = require('path');
const chalk = require('chalk');
const ora = require('ora');
const inquirer = require('inquirer');
const { detectProject } = require('../utils/projectDetector');
const BuildkiteAnalyzer = require('../utils/buildkiteAnalyzer');
const { generateWorkflow } = require('../utils/workflowGenerator');
const { installDeployScript } = require('../utils/scriptInstaller');

async function initCommand(options) {
  console.log(chalk.cyan('\n🚀 Karma Deploy Initialization\n'));

  const spinner = ora('Analyzing project...').start();

  try {
    // Detect project type
    const projectInfo = detectProject();
    spinner.succeed(`Detected project: ${chalk.bold(projectInfo.name)} (${projectInfo.type})`);

    // Check for existing configurations
    const hasGitHub = fs.existsSync(path.join(process.cwd(), '.github', 'workflows', 'ci-cd.yml'));
    const hasBuildkite = fs.existsSync(path.join(process.cwd(), '.buildkite'));
    const hasDeployScript = fs.existsSync(path.join(process.cwd(), 'deploy.sh'));

    if (hasGitHub && !options.force) {
      console.log(chalk.yellow('\n⚠️  GitHub Actions workflow already exists!'));
      const { proceed } = await inquirer.prompt([{
        type: 'confirm',
        name: 'proceed',
        message: 'Do you want to overwrite existing configuration?',
        default: false
      }]);
      
      if (!proceed) {
        console.log(chalk.yellow('Initialization cancelled.'));
        return;
      }
    }

    // Analyze Buildkite if requested
    let buildkiteAnalysis = null;
    if (options.analyze && hasBuildkite) {
      spinner.start('Analyzing Buildkite pipeline...');
      const analyzer = new BuildkiteAnalyzer();
      buildkiteAnalysis = analyzer.analyze();
      spinner.succeed('Buildkite pipeline analyzed');
    }

    // Determine staging requirement
    let includeStaging = projectInfo.staging;
    if (options.staging !== undefined) {
      includeStaging = options.staging;
    } else if (!projectInfo.staging) {
      // Ask user if they want staging for ambiguous cases
      const { wantStaging } = await inquirer.prompt([{
        type: 'confirm',
        name: 'wantStaging',
        message: 'Do you want to include a staging environment?',
        default: false
      }]);
      includeStaging = wantStaging;
    }

    console.log(chalk.cyan('\n📋 Configuration Summary:\n'));
    console.log(`  Project: ${projectInfo.name}`);
    console.log(`  Type: ${projectInfo.type}`);
    console.log(`  Deployment: ${projectInfo.deployment}`);
    console.log(`  Environments: ${projectInfo.environments.join(', ')}${includeStaging && !projectInfo.environments.includes('staging') ? ', staging' : ''}`);
    
    if (projectInfo.features.graphql) {
      console.log(`  GraphQL: ✅`);
    }
    if (projectInfo.features.sentry) {
      console.log(`  Sentry: ✅`);
    }
    if (projectInfo.features.docker) {
      console.log(`  Docker: ✅`);
    }

    // Initialize components
    console.log(chalk.cyan('\n🔧 Setting up deployment configuration...\n'));

    // 1. Install deploy script
    if (!hasDeployScript || options.force) {
      spinner.start('Installing deploy script...');
      await installDeployScript(projectInfo, options);
      spinner.succeed('Deploy script installed');
    }

    // 2. Create staging overlay if needed
    if (includeStaging && !projectInfo.environments.includes('staging')) {
      spinner.start('Creating staging environment...');
      createStagingOverlay(projectInfo);
      spinner.succeed('Staging environment created');
    }

    // 3. Create GitHub Actions workflow
    spinner.start('Creating GitHub Actions workflow...');
    const workflowContent = generateWorkflow(projectInfo, buildkiteAnalysis);
    const workflowPath = path.join(process.cwd(), '.github', 'workflows');
    
    if (!fs.existsSync(workflowPath)) {
      fs.mkdirSync(workflowPath, { recursive: true });
    }
    
    fs.writeFileSync(path.join(workflowPath, 'ci-cd.yml'), workflowContent);
    spinner.succeed('GitHub Actions workflow created');

    // Display required secrets
    console.log(chalk.cyan('\n🔐 Required GitHub Secrets:\n'));
    const secrets = getRequiredSecrets(projectInfo, buildkiteAnalysis);
    secrets.forEach(secret => {
      console.log(`  • ${secret.name}: ${secret.description}`);
    });

    // Success message
    console.log(chalk.green('\n✅ Initialization complete!\n'));

    // Next steps
    console.log(chalk.cyan('📝 Next Steps:\n'));
    console.log('1. Review .github/workflows/ci-cd.yml');
    console.log('2. Configure GitHub secrets listed above');
    console.log('3. Set up GitHub environments:');
    console.log('   - Go to Settings → Environments');
    console.log('   - Create "development" environment');
    console.log('   - Create "production" environment with protection rules');
    if (includeStaging) {
      console.log('   - Create "staging" environment');
    }
    console.log('4. Test deployment with: npm run deploy:dev');
    console.log('5. Create a version tag to trigger deployment: git tag v1.0.0-dev && git push --tags');

  } catch (error) {
    spinner.fail('Initialization failed');
    console.error(chalk.red(`\n❌ Error: ${error.message}\n`));
    process.exit(1);
  }
}

function createStagingOverlay(projectInfo) {
  const stagingPath = path.join(process.cwd(), 'kubernetes', 'overlays', 'staging');
  
  if (!fs.existsSync(stagingPath)) {
    fs.mkdirSync(stagingPath, { recursive: true });
  }

  // Create kustomization.yaml
  const kustomization = `apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../production

namespace: staging

namePrefix: staging-

labels:
  - pairs:
      environment: staging
    includeSelectors: true`;

  fs.writeFileSync(path.join(stagingPath, 'kustomization.yaml'), kustomization);

  // Create configmap
  const configmap = `apiVersion: v1
kind: ConfigMap
metadata:
  name: ${projectInfo.name}
data:
  NODE_ENV: "staging"
  SENTRY_ENVIRONMENT: "staging"`;

  fs.writeFileSync(path.join(stagingPath, 'configmap.yaml'), configmap);

  // Create deployment patch
  const deployment = `apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${projectInfo.name}
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: ${projectInfo.name}
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"`;

  fs.writeFileSync(path.join(stagingPath, 'deployment.yaml'), deployment);
}

function getRequiredSecrets(projectInfo, buildkiteAnalysis) {
  const secrets = [
    { name: 'NPM_TOKEN', description: 'NPM authentication token for private packages' },
    { name: 'GCP_SA_KEY', description: 'Service account key for GCP deployment' },
    { name: 'GITOPS_TOKEN', description: 'GitHub token for GitOps repository access' }
  ];

  if (projectInfo.features.sentry || buildkiteAnalysis?.pipeline?.features?.sentry) {
    secrets.push({ name: 'SENTRY_AUTH_TOKEN', description: 'Sentry authentication token' });
  }

  if (buildkiteAnalysis?.pipeline?.features?.fontawesome) {
    secrets.push({ name: 'FONTAWESOME_NPM_TOKEN', description: 'FontAwesome Pro NPM token' });
  }

  if (buildkiteAnalysis?.pipeline?.features?.googleMaps) {
    secrets.push({ name: 'STOREFRONT_PUBLIC_GOOGLE_MAPS_KEY', description: 'Google Maps API key' });
  }

  if (projectInfo.features.graphql) {
    secrets.push({ name: 'APOLLO_KEY', description: 'Apollo Studio API key' });
  }

  return secrets;
}

module.exports = initCommand;