const fs = require('fs');
const path = require('path');
const chalk = require('chalk');
const ora = require('ora');
const BuildkiteAnalyzer = require('../utils/buildkiteAnalyzer');
const { detectProject } = require('../utils/projectDetector');
const { generateWorkflow } = require('../utils/workflowGenerator');
const { installDeployScript } = require('../utils/scriptInstaller');

async function migrateCommand(options) {
  console.log(chalk.cyan('\n🚀 Karma Migration Tool - Buildkite to GitHub Actions\n'));

  const spinner = ora('Analyzing project...').start();

  try {
    // Detect project type and configuration
    const projectInfo = detectProject();
    spinner.succeed('Project analyzed');

    // Analyze Buildkite pipeline
    spinner.start('Analyzing Buildkite pipeline...');
    const analyzer = new BuildkiteAnalyzer();
    const buildkiteAnalysis = analyzer.analyze();
    
    if (!buildkiteAnalysis) {
      spinner.warn('No Buildkite configuration found');
      console.log(chalk.yellow('\n⚠️  No .buildkite/pipeline.nix found. Will create GitHub Actions from scratch.\n'));
    } else {
      spinner.succeed('Buildkite pipeline analyzed');
      
      // Display analysis
      console.log(chalk.cyan('\n📊 Buildkite Pipeline Analysis:\n'));
      console.log(chalk.white('Files found:'), buildkiteAnalysis.files.join(', '));
      
      if (buildkiteAnalysis.pipeline) {
        const features = buildkiteAnalysis.pipeline.features;
        console.log(chalk.white('\n✅ Detected features:'));
        
        if (features.tests) console.log('  • Tests');
        if (features.docker) console.log('  • Docker builds');
        if (features.sentry) console.log('  • Sentry integration');
        if (features.graphql) console.log('  • GraphQL/Apollo');
        if (features.fontawesome) console.log('  • FontAwesome Pro');
        if (features.googleMaps) console.log('  • Google Maps');
        if (features.manualApproval) console.log('  • Manual deployment approval');
        if (features.branchBasedDeployment) console.log('  • Branch-based deployment');
        
        if (buildkiteAnalysis.pipeline.environments.length > 0) {
          console.log(chalk.white('\n🌍 Environments:'), buildkiteAnalysis.pipeline.environments.join(', '));
        }
        
        if (buildkiteAnalysis.pipeline.secrets.length > 0) {
          console.log(chalk.white('\n🔐 Secrets required:'));
          buildkiteAnalysis.pipeline.secrets.forEach(secret => {
            console.log(`  • ${secret}`);
          });
        }

        if (buildkiteAnalysis.pipeline.dockerBuildArgs.length > 0) {
          console.log(chalk.white('\n🐳 Docker build args:'));
          buildkiteAnalysis.pipeline.dockerBuildArgs.forEach(arg => {
            console.log(`  • ${arg}`);
          });
        }
      }
    }

    if (options.dryRun) {
      console.log(chalk.yellow('\n🔍 Dry run mode - no changes will be made\n'));
    }

    // Generate migration plan
    console.log(chalk.cyan('\n📋 Migration Plan:\n'));
    
    const migrationSteps = [];
    
    // Step 1: Install deploy script
    migrationSteps.push({
      name: 'Install deployment script',
      action: () => installDeployScript(projectInfo, options)
    });

    // Step 2: Create staging overlay if needed
    if (projectInfo.staging && !projectInfo.environments.includes('staging')) {
      migrationSteps.push({
        name: 'Create staging environment configuration',
        action: () => createStagingOverlay(projectInfo)
      });
    }

    // Step 3: Create GitHub Actions workflow
    migrationSteps.push({
      name: 'Create GitHub Actions workflow',
      action: () => createGitHubWorkflow(projectInfo, buildkiteAnalysis)
    });

    // Step 4: List required secrets
    migrationSteps.push({
      name: 'Configure GitHub secrets',
      action: () => listRequiredSecrets(projectInfo, buildkiteAnalysis)
    });

    // Display plan
    migrationSteps.forEach((step, index) => {
      console.log(`${index + 1}. ${step.name}`);
    });

    if (!options.dryRun) {
      console.log(chalk.cyan('\n🚀 Executing migration...\n'));
      
      for (const step of migrationSteps) {
        spinner.start(step.name);
        try {
          await step.action();
          spinner.succeed(step.name);
        } catch (error) {
          spinner.fail(`${step.name}: ${error.message}`);
          if (!options.force) {
            throw error;
          }
        }
      }

      // Compare with existing GitHub Actions
      if (buildkiteAnalysis) {
        console.log(chalk.cyan('\n🔍 Comparison with GitHub Actions:\n'));
        const comparison = analyzer.compareWithGitHubActions();
        
        if (comparison.recommendations.length > 0) {
          console.log(chalk.yellow('⚠️  Recommendations:'));
          comparison.recommendations.forEach(rec => {
            console.log(`  • ${rec}`);
          });
        }
      }

      console.log(chalk.green('\n✅ Migration completed successfully!\n'));
      
      // Next steps
      console.log(chalk.cyan('📝 Next steps:\n'));
      console.log('1. Review the generated .github/workflows/ci-cd.yml file');
      console.log('2. Configure the following GitHub secrets:');
      console.log('   • NPM_TOKEN');
      console.log('   • GCP_SA_KEY');
      if (buildkiteAnalysis?.pipeline?.features?.sentry) {
        console.log('   • SENTRY_AUTH_TOKEN');
      }
      if (buildkiteAnalysis?.pipeline?.features?.fontawesome) {
        console.log('   • FONTAWESOME_NPM_TOKEN');
      }
      if (buildkiteAnalysis?.pipeline?.features?.googleMaps) {
        console.log('   • STOREFRONT_PUBLIC_GOOGLE_MAPS_KEY');
      }
      console.log('3. Configure GitHub environments (development, production' + 
                  (projectInfo.staging ? ', staging' : '') + ')');
      console.log('4. Test the workflow with a feature branch');
      if (!options.keepBuildkite) {
        console.log('5. Remove .buildkite directory once migration is verified');
      }
    }

  } catch (error) {
    spinner.fail('Migration failed');
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

  // Create basic configmap
  const configmap = `apiVersion: v1
kind: ConfigMap
metadata:
  name: ${projectInfo.name}
data:
  NODE_ENV: "staging"
  SENTRY_ENVIRONMENT: "staging"`;

  fs.writeFileSync(path.join(stagingPath, 'configmap.yaml'), configmap);
}

function createGitHubWorkflow(projectInfo, buildkiteAnalysis) {
  const workflowPath = path.join(process.cwd(), '.github', 'workflows');
  
  if (!fs.existsSync(workflowPath)) {
    fs.mkdirSync(workflowPath, { recursive: true });
  }

  const workflow = generateWorkflow(projectInfo, buildkiteAnalysis);
  fs.writeFileSync(path.join(workflowPath, 'ci-cd.yml'), workflow);
}

function listRequiredSecrets(projectInfo, buildkiteAnalysis) {
  const secrets = ['NPM_TOKEN', 'GCP_SA_KEY', 'GITOPS_TOKEN'];
  
  if (buildkiteAnalysis?.pipeline?.secrets) {
    secrets.push(...buildkiteAnalysis.pipeline.secrets);
  }

  console.log(chalk.yellow('\n🔐 Required GitHub Secrets:\n'));
  secrets.forEach(secret => {
    console.log(`  • ${secret}`);
  });
}

module.exports = migrateCommand;