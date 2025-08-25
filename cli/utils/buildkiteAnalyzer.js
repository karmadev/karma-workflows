const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

class BuildkiteAnalyzer {
  constructor(projectPath = process.cwd()) {
    this.projectPath = projectPath;
    this.buildkitePath = path.join(projectPath, '.buildkite');
  }

  analyze() {
    if (!fs.existsSync(this.buildkitePath)) {
      return null;
    }

    const analysis = {
      exists: true,
      files: [],
      pipeline: null,
      steps: [],
      features: {
        tests: false,
        docker: false,
        deployment: false,
        sentry: false,
        graphql: false,
        notifications: false,
        parallelTests: false,
        matrixBuilds: false
      },
      environments: [],
      dependencies: [],
      customSteps: [],
      secrets: [],
      artifacts: [],
      hooks: []
    };

    // Find pipeline files
    const files = fs.readdirSync(this.buildkitePath);
    
    // Handle .nix files (Karma uses Nix for Buildkite)
    const nixFile = files.find(f => f === 'pipeline.nix');
    if (nixFile) {
      analysis.files.push(nixFile);
      analysis.pipeline = this.analyzeNixPipeline(path.join(this.buildkitePath, nixFile));
    }

    // Handle YAML files
    const yamlFiles = files.filter(f => f.endsWith('.yml') || f.endsWith('.yaml'));
    for (const file of yamlFiles) {
      analysis.files.push(file);
      const yamlContent = this.analyzeYamlPipeline(path.join(this.buildkitePath, file));
      if (yamlContent) {
        analysis.pipeline = yamlContent;
      }
    }

    return analysis;
  }

  analyzeNixPipeline(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');
    
    const analysis = {
      type: 'nix',
      steps: [],
      features: {},
      environments: [],
      secrets: [],
      dockerBuildArgs: []
    };

    // Extract test steps
    if (content.includes('Test') || content.includes('test')) {
      analysis.features.tests = true;
      
      // Extract test commands
      const testMatch = content.match(/command\s*=\s*''([^']+)''/g);
      if (testMatch) {
        analysis.steps.push({
          type: 'test',
          name: 'Run Tests',
          commands: testMatch.map(m => m.replace(/command\s*=\s*''/, '').replace(/''/, ''))
        });
      }
    }

    // Extract Docker build
    if (content.includes('dockerBuild')) {
      analysis.features.docker = true;
      
      // Extract build args
      const buildArgsMatch = content.match(/additionalBuildArgs\s*=\s*\[([\s\S]*?)\]/);
      if (buildArgsMatch) {
        const args = buildArgsMatch[1].match(/"[^"]+"/g);
        if (args) {
          analysis.dockerBuildArgs = args.map(arg => arg.replace(/"/g, ''));
        }
      }

      // Check for npmAuth
      if (content.includes('npmAuth = true')) {
        analysis.features.npmAuth = true;
      }
    }

    // Extract deployment environments
    const deployMatches = content.matchAll(/deploy\s+"([^"]+)"/g);
    for (const match of deployMatches) {
      analysis.environments.push(match[1]);
    }

    // Check for Sentry
    if (content.includes('SENTRY') || content.includes('sentry')) {
      analysis.features.sentry = true;
      
      // Extract Sentry configuration
      const sentryVars = content.match(/SENTRY_[A-Z_]+/g);
      if (sentryVars) {
        analysis.secrets.push(...new Set(sentryVars));
      }
    }

    // Check for GraphQL/Apollo
    if (content.includes('apollo') || content.includes('APOLLO')) {
      analysis.features.graphql = true;
    }

    // Check for deployment blocks
    if (content.includes('block') && content.includes('deploy')) {
      analysis.features.manualApproval = true;
    }

    // Extract environment-specific builds
    if (content.includes('BUILDKITE_BRANCH') && content.includes('master')) {
      analysis.features.branchBasedDeployment = true;
    }

    // Check for FontAwesome
    if (content.includes('FONTAWESOME')) {
      analysis.features.fontawesome = true;
      analysis.secrets.push('FONTAWESOME_NPM_TOKEN');
    }

    // Check for Google Maps
    if (content.includes('GOOGLE_MAPS_KEY')) {
      analysis.features.googleMaps = true;
    }

    // Extract custom environment variables
    const envMatches = content.matchAll(/getEnv\s+"([^"]+)"/g);
    for (const match of envMatches) {
      if (!analysis.secrets.includes(match[1])) {
        analysis.secrets.push(match[1]);
      }
    }

    return analysis;
  }

  analyzeYamlPipeline(filePath) {
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      const pipeline = yaml.load(content);
      
      const analysis = {
        type: 'yaml',
        steps: [],
        features: {},
        environments: [],
        secrets: []
      };

      if (pipeline.steps) {
        for (const step of pipeline.steps) {
          // Analyze each step
          if (step.label) {
            analysis.steps.push({
              name: step.label,
              commands: step.commands || step.command,
              plugins: step.plugins
            });
          }

          // Check for specific features
          if (step.command?.includes('test') || step.commands?.some(c => c.includes('test'))) {
            analysis.features.tests = true;
          }

          if (step.plugins?.some(p => p['docker-compose'] || p['docker'])) {
            analysis.features.docker = true;
          }
        }
      }

      return analysis;
    } catch (error) {
      console.error(`Error parsing YAML file ${filePath}:`, error);
      return null;
    }
  }

  compareWithGitHubActions() {
    const buildkiteAnalysis = this.analyze();
    if (!buildkiteAnalysis) {
      return { hasBuildkite: false };
    }

    const comparison = {
      hasBuildkite: true,
      missingInGitHub: [],
      recommendations: []
    };

    // Check if GitHub Actions exists
    const githubWorkflowPath = path.join(this.projectPath, '.github', 'workflows', 'ci-cd.yml');
    if (!fs.existsSync(githubWorkflowPath)) {
      comparison.missingInGitHub.push('GitHub Actions workflow not found');
      comparison.recommendations.push('Run "karma init" to create GitHub Actions workflow');
      return comparison;
    }

    // Compare features
    if (buildkiteAnalysis.pipeline?.features) {
      const features = buildkiteAnalysis.pipeline.features;
      
      if (features.sentry) {
        comparison.recommendations.push('Ensure Sentry release creation is configured in GitHub Actions');
      }

      if (features.fontawesome) {
        comparison.recommendations.push('Add FONTAWESOME_NPM_TOKEN to GitHub secrets');
      }

      if (features.googleMaps) {
        comparison.recommendations.push('Add STOREFRONT_PUBLIC_GOOGLE_MAPS_KEY to GitHub secrets');
      }

      if (features.manualApproval) {
        comparison.recommendations.push('Configure GitHub environment protection rules for manual approval');
      }

      if (features.graphql) {
        comparison.recommendations.push('Ensure Apollo schema registration is configured');
      }
    }

    // Check for custom steps
    if (buildkiteAnalysis.pipeline?.steps) {
      for (const step of buildkiteAnalysis.pipeline.steps) {
        if (step.type === 'test' && step.commands) {
          // Check if test commands are complex
          const hasComplexTests = step.commands.some(cmd => 
            cmd.includes('&&') || cmd.includes('||') || cmd.includes('|')
          );
          if (hasComplexTests) {
            comparison.recommendations.push(`Complex test command found: Consider breaking down test steps`);
          }
        }
      }
    }

    // Check for secrets
    if (buildkiteAnalysis.pipeline?.secrets?.length > 0) {
      comparison.recommendations.push(
        `Add these secrets to GitHub: ${buildkiteAnalysis.pipeline.secrets.join(', ')}`
      );
    }

    return comparison;
  }
}

module.exports = BuildkiteAnalyzer;