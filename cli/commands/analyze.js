const chalk = require('chalk');
const { detectProject } = require('../utils/projectDetector');
const BuildkiteAnalyzer = require('../utils/buildkiteAnalyzer');

async function analyzeCommand(options) {
  console.log(chalk.cyan('\n🔍 Karma CI/CD Analysis\n'));

  try {
    // Detect project configuration
    const projectInfo = detectProject();
    
    // Analyze Buildkite
    const buildkiteAnalyzer = new BuildkiteAnalyzer();
    const buildkiteAnalysis = buildkiteAnalyzer.analyze();
    
    const analysis = {
      project: projectInfo,
      buildkite: buildkiteAnalysis,
      comparison: null
    };

    if (buildkiteAnalysis) {
      analysis.comparison = buildkiteAnalyzer.compareWithGitHubActions();
    }

    if (options.json) {
      // Output as JSON for programmatic use
      console.log(JSON.stringify(analysis, null, 2));
      return;
    }

    // Display human-readable analysis
    displayAnalysis(analysis, options.verbose);

  } catch (error) {
    console.error(chalk.red(`\n❌ Error: ${error.message}\n`));
    process.exit(1);
  }
}

function displayAnalysis(analysis, verbose) {
  const { project, buildkite, comparison } = analysis;

  // Project Information
  console.log(chalk.cyan('📦 Project Information:\n'));
  console.log(`  Name: ${chalk.bold(project.name)}`);
  console.log(`  Type: ${project.type}`);
  console.log(`  Deployment: ${project.deployment}`);
  console.log(`  Environments: ${project.environments.join(', ')}`);
  console.log(`  Staging Required: ${project.staging ? '✅' : '❌'}`);

  // Features
  console.log(chalk.cyan('\n🚀 Detected Features:\n'));
  const features = project.features;
  console.log(`  GraphQL: ${features.graphql ? '✅' : '❌'}`);
  console.log(`  Sentry: ${features.sentry ? '✅' : '❌'}`);
  console.log(`  Docker: ${features.docker ? '✅' : '❌'}`);
  console.log(`  Tests: ${features.tests ? '✅' : '❌'}`);
  console.log(`  Linting: ${features.lint ? '✅' : '❌'}`);
  console.log(`  Type Checking: ${features.typecheck ? '✅' : '❌'}`);

  // CI/CD Status
  console.log(chalk.cyan('\n⚙️  CI/CD Configuration:\n'));
  console.log(`  Current System: ${project.cicd.current || 'None'}`);
  console.log(`  GitHub Actions: ${project.cicd.githubActions ? '✅' : '❌'}`);
  console.log(`  Buildkite: ${project.cicd.buildkite ? '✅' : '❌'}`);
  
  if (project.cicd.configs.length > 0) {
    console.log(`  Config Files:`);
    project.cicd.configs.forEach(config => {
      console.log(`    • ${config}`);
    });
  }

  // Buildkite Analysis
  if (buildkite) {
    console.log(chalk.cyan('\n🏗️  Buildkite Pipeline Analysis:\n'));
    console.log(`  Files: ${buildkite.files.join(', ')}`);
    
    if (buildkite.pipeline) {
      const pipeline = buildkite.pipeline;
      
      if (pipeline.features) {
        console.log(`  Features:`);
        Object.entries(pipeline.features).forEach(([feature, enabled]) => {
          if (enabled) {
            console.log(`    • ${feature}`);
          }
        });
      }

      if (pipeline.environments?.length > 0) {
        console.log(`  Deployment Environments: ${pipeline.environments.join(', ')}`);
      }

      if (pipeline.secrets?.length > 0 && verbose) {
        console.log(`  Required Secrets:`);
        pipeline.secrets.forEach(secret => {
          console.log(`    • ${secret}`);
        });
      }

      if (pipeline.dockerBuildArgs?.length > 0 && verbose) {
        console.log(`  Docker Build Args:`);
        pipeline.dockerBuildArgs.forEach(arg => {
          console.log(`    • ${arg}`);
        });
      }
    }
  }

  // Comparison and Recommendations
  if (comparison) {
    console.log(chalk.cyan('\n📊 Migration Readiness:\n'));
    
    if (comparison.recommendations.length > 0) {
      console.log(chalk.yellow('  ⚠️  Action Items:'));
      comparison.recommendations.forEach(rec => {
        console.log(`    • ${rec}`);
      });
    } else {
      console.log(chalk.green('  ✅ Ready for migration!'));
    }
  }

  // Key Dependencies
  if (Object.keys(project.dependencies).length > 0) {
    console.log(chalk.cyan('\n📚 Key Dependencies:\n'));
    Object.entries(project.dependencies).forEach(([dep, version]) => {
      console.log(`  • ${dep}: ${version}`);
    });
  }

  // Recommendations
  console.log(chalk.cyan('\n💡 Recommendations:\n'));
  
  if (!project.cicd.githubActions) {
    console.log('  • Run "karma init" to set up GitHub Actions');
  } else if (project.cicd.buildkite) {
    console.log('  • Run "karma migrate" to complete migration from Buildkite');
  }
  
  if (!project.features.tests) {
    console.log('  • Consider adding test scripts to package.json');
  }
  
  if (!project.features.lint) {
    console.log('  • Consider adding linting configuration');
  }
  
  if (project.staging && !project.environments.includes('staging')) {
    console.log('  • Run "karma init --staging" to add staging environment');
  }
}

module.exports = analyzeCommand;