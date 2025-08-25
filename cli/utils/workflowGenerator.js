const yaml = require('js-yaml');

function generateWorkflow(projectInfo, buildkiteAnalysis) {
  const workflow = {
    name: 'CI/CD Pipeline',
    on: {
      push: {
        tags: ['v*']
      },
      pull_request: {
        branches: ['master', 'main']
      },
      workflow_dispatch: {}
    },
    jobs: {}
  };

  // Main pipeline job
  const pipelineJob = {
    uses: 'karmadev/karma-workflows/.github/workflows/node-service-pipeline.yml@main',
    with: {
      'service-name': projectInfo.name
    },
    secrets: 'inherit'
  };

  // Configure based on project type
  if (projectInfo.type === 'nextjs') {
    pipelineJob.with['node-version'] = '20';
  } else if (projectInfo.type === 'gatsby') {
    pipelineJob.with['node-version'] = '18';
  } else {
    // Default Node version
    pipelineJob.with['node-version'] = detectNodeVersion(projectInfo) || '18';
  }

  // Add features based on detection
  if (projectInfo.features.graphql) {
    pipelineJob.with['has-graphql'] = true;
    
    // Determine Apollo configuration
    if (projectInfo.name.includes('merchant')) {
      pipelineJob.with['apollo-graph'] = 'karma-merchant';
      pipelineJob.with['apollo-subgraph'] = 'Base';
    } else if (projectInfo.name.includes('admin')) {
      pipelineJob.with['apollo-graph'] = 'karma-admin';
      pipelineJob.with['apollo-subgraph'] = 'Base';
    }
  } else {
    pipelineJob.with['has-graphql'] = false;
  }

  // Configure testing and linting
  if (projectInfo.features.tests) {
    pipelineJob.with['run-tests'] = true;
  }
  
  if (projectInfo.features.lint) {
    pipelineJob.with['run-lint'] = true;
  }
  
  if (projectInfo.features.typecheck) {
    pipelineJob.with['run-typecheck'] = true;
  }

  // Add Docker build args from Buildkite analysis
  if (buildkiteAnalysis?.pipeline?.dockerBuildArgs?.length > 0) {
    const buildArgs = [];
    
    // Filter and format build args
    for (const arg of buildkiteAnalysis.pipeline.dockerBuildArgs) {
      if (arg.includes('SENTRY_URL') || arg.includes('SENTRY_ORG') || arg.includes('SENTRY_PROJECT')) {
        // These can be hardcoded
        const [key, value] = arg.split('=');
        if (value && !value.includes('$')) {
          buildArgs.push(arg);
        }
      }
    }
    
    if (buildArgs.length > 0) {
      pipelineJob.with['docker-build-args'] = buildArgs.join('\n        ');
    }
  }

  workflow.jobs.pipeline = pipelineJob;

  // Add Sentry release job if Sentry is detected
  if (projectInfo.features.sentry || buildkiteAnalysis?.pipeline?.features?.sentry) {
    workflow.jobs['sentry-release'] = {
      needs: 'pipeline',
      if: "startsWith(github.ref, 'refs/tags/v')",
      'runs-on': 'ubuntu-latest',
      steps: [
        {
          uses: 'actions/checkout@v4'
        },
        {
          name: 'Determine environment',
          id: 'env',
          run: `TAG=\${GITHUB_REF#refs/tags/}
if [[ "$TAG" == *"-staging"* ]]; then
  echo "environment=staging" >> $GITHUB_OUTPUT
elif [[ "$TAG" == *"-dev"* ]]; then
  echo "environment=development" >> $GITHUB_OUTPUT
else
  echo "environment=production" >> $GITHUB_OUTPUT
fi`
        },
        {
          name: 'Create Sentry Release',
          uses: 'getsentry/action-release@v1',
          env: {
            SENTRY_AUTH_TOKEN: '${{ secrets.SENTRY_AUTH_TOKEN }}',
            SENTRY_ORG: getSentryOrg(projectInfo),
            SENTRY_PROJECT: getSentryProject(projectInfo)
          },
          with: {
            environment: '${{ steps.env.outputs.environment }}',
            version: '${{ github.sha }}'
          }
        }
      ]
    };
  }

  // Convert to YAML string
  return formatYaml(workflow);
}

function detectNodeVersion(projectInfo) {
  // Check package.json engines field
  if (projectInfo.packageJson?.engines?.node) {
    const nodeVersion = projectInfo.packageJson.engines.node;
    // Extract major version
    const match = nodeVersion.match(/(\d+)/);
    if (match) {
      return match[1];
    }
  }
  
  // Check for .nvmrc
  const fs = require('fs');
  const path = require('path');
  const nvmrcPath = path.join(process.cwd(), '.nvmrc');
  if (fs.existsSync(nvmrcPath)) {
    const nvmrc = fs.readFileSync(nvmrcPath, 'utf8').trim();
    const match = nvmrc.match(/(\d+)/);
    if (match) {
      return match[1];
    }
  }
  
  return null;
}

function getSentryOrg(projectInfo) {
  // All Karma projects use the same Sentry org
  return 'karma-0f';
}

function getSentryProject(projectInfo) {
  const name = projectInfo.name;
  
  // Map service names to Sentry projects
  const sentryProjects = {
    'storefront-web': 'karma-storefront',
    'storefront-service': 'karma-storefront-service',
    'karma-merchant-web': 'karma-merchant',
    'karma-merchant-api': 'karma-merchant-api',
    'admin-frontend': 'karma-admin',
    'karma-admin-api': 'karma-admin-api'
  };
  
  return sentryProjects[name] || name;
}

function formatYaml(obj) {
  // Convert to YAML with proper formatting
  let yamlStr = yaml.dump(obj, {
    lineWidth: -1,
    noRefs: true,
    quotingType: '"',
    forceQuotes: false
  });
  
  // Fix formatting for better readability
  yamlStr = yamlStr.replace(/^\s{2}on:/m, '\non:');
  yamlStr = yamlStr.replace(/^\s{2}jobs:/m, '\njobs:');
  
  // Add comments
  const header = `# Generated by Karma Deploy CLI
# Run 'karma update' to update this workflow

`;
  
  return header + yamlStr;
}

module.exports = {
  generateWorkflow
};