const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

class ProjectDetector {
  constructor(projectPath = process.cwd()) {
    this.projectPath = projectPath;
    this.packageJson = this.loadPackageJson();
  }

  loadPackageJson() {
    const packagePath = path.join(this.projectPath, 'package.json');
    if (fs.existsSync(packagePath)) {
      return JSON.parse(fs.readFileSync(packagePath, 'utf8'));
    }
    return null;
  }

  detectProject() {
    const info = {
      name: this.packageJson?.name || path.basename(this.projectPath),
      type: this.detectProjectType(),
      deployment: this.detectDeploymentType(),
      environments: this.detectEnvironments(),
      cicd: this.detectCICD(),
      features: this.detectFeatures(),
      dependencies: this.detectKeyDependencies(),
      staging: this.requiresStaging()
    };

    return info;
  }

  detectProjectType() {
    // Check for Next.js
    if (this.packageJson?.dependencies?.next || this.packageJson?.devDependencies?.next) {
      return 'nextjs';
    }

    // Check for React (without Next.js)
    if (this.packageJson?.dependencies?.react && !this.packageJson?.dependencies?.next) {
      // Check for Gatsby
      if (this.packageJson?.dependencies?.gatsby) {
        return 'gatsby';
      }
      return 'react';
    }

    // Check for Node.js service
    if (fs.existsSync(path.join(this.projectPath, 'src', 'server.ts')) ||
        fs.existsSync(path.join(this.projectPath, 'src', 'server.js')) ||
        fs.existsSync(path.join(this.projectPath, 'src', 'index.ts'))) {
      return 'node-service';
    }

    // Check for Cloud Functions
    if (this.packageJson?.main?.includes('function') || 
        fs.existsSync(path.join(this.projectPath, 'functions'))) {
      return 'cloud-functions';
    }

    // Check for Firebase
    if (fs.existsSync(path.join(this.projectPath, 'firebase.json'))) {
      return 'firebase';
    }

    return 'unknown';
  }

  detectDeploymentType() {
    // Check for Kubernetes
    if (fs.existsSync(path.join(this.projectPath, 'kubernetes')) ||
        fs.existsSync(path.join(this.projectPath, 'k8s')) ||
        fs.existsSync(path.join(this.projectPath, 'Dockerfile'))) {
      return 'kubernetes';
    }

    // Check for Firebase
    if (fs.existsSync(path.join(this.projectPath, 'firebase.json'))) {
      return 'firebase';
    }

    // Check for Cloud Functions
    if (fs.existsSync(path.join(this.projectPath, 'functions'))) {
      return 'cloud-functions';
    }

    return 'unknown';
  }

  detectEnvironments() {
    const environments = [];
    
    // Check Kubernetes overlays
    const overlaysPath = path.join(this.projectPath, 'kubernetes', 'overlays');
    if (fs.existsSync(overlaysPath)) {
      const dirs = fs.readdirSync(overlaysPath).filter(dir => 
        fs.statSync(path.join(overlaysPath, dir)).isDirectory()
      );
      environments.push(...dirs);
    }

    // Check for common environment indicators
    if (environments.length === 0) {
      // Default environments
      if (fs.existsSync(path.join(this.projectPath, '.env.development'))) {
        environments.push('development');
      }
      if (fs.existsSync(path.join(this.projectPath, '.env.production'))) {
        environments.push('production');
      }
    }

    // If still no environments found, use defaults
    if (environments.length === 0) {
      environments.push('development', 'production');
    }

    return environments;
  }

  detectCICD() {
    const cicd = {
      current: null,
      buildkite: false,
      githubActions: false,
      configs: []
    };

    // Check for Buildkite
    const buildkitePath = path.join(this.projectPath, '.buildkite');
    if (fs.existsSync(buildkitePath)) {
      cicd.buildkite = true;
      cicd.current = 'buildkite';
      
      // Find pipeline files
      const pipelineFiles = fs.readdirSync(buildkitePath)
        .filter(file => file.endsWith('.yml') || file.endsWith('.yaml') || file.endsWith('.nix'));
      
      cicd.configs.push(...pipelineFiles.map(file => 
        path.join('.buildkite', file)
      ));
    }

    // Check for GitHub Actions
    const githubPath = path.join(this.projectPath, '.github', 'workflows');
    if (fs.existsSync(githubPath)) {
      cicd.githubActions = true;
      cicd.current = cicd.current ? 'both' : 'github-actions';
      
      const workflowFiles = fs.readdirSync(githubPath)
        .filter(file => file.endsWith('.yml') || file.endsWith('.yaml'));
      
      cicd.configs.push(...workflowFiles.map(file => 
        path.join('.github', 'workflows', file)
      ));
    }

    return cicd;
  }

  detectFeatures() {
    const features = {
      graphql: false,
      sentry: false,
      docker: false,
      tests: false,
      lint: false,
      typecheck: false,
      prettier: false,
      database: false,
      authentication: false
    };

    // Check for GraphQL
    if (this.packageJson?.dependencies?.['@apollo/server'] ||
        this.packageJson?.dependencies?.graphql ||
        fs.existsSync(path.join(this.projectPath, 'schema.graphql'))) {
      features.graphql = true;
    }

    // Check for Sentry
    if (this.packageJson?.dependencies?.['@sentry/node'] ||
        this.packageJson?.dependencies?.['@sentry/nextjs']) {
      features.sentry = true;
    }

    // Check for Docker
    if (fs.existsSync(path.join(this.projectPath, 'Dockerfile'))) {
      features.docker = true;
    }

    // Check for test setup
    if (this.packageJson?.scripts?.test) {
      features.tests = true;
    }

    // Check for linting
    if (this.packageJson?.scripts?.lint || 
        this.packageJson?.devDependencies?.eslint) {
      features.lint = true;
    }

    // Check for TypeScript
    if (this.packageJson?.scripts?.['typecheck'] ||
        this.packageJson?.scripts?.['type-check'] ||
        this.packageJson?.scripts?.['typescript-check']) {
      features.typecheck = true;
    }

    // Check for Prettier
    if (this.packageJson?.devDependencies?.prettier) {
      features.prettier = true;
    }

    // Check for database
    if (this.packageJson?.dependencies?.knex ||
        this.packageJson?.dependencies?.sequelize ||
        this.packageJson?.dependencies?.typeorm ||
        this.packageJson?.dependencies?.pg) {
      features.database = true;
    }

    return features;
  }

  detectKeyDependencies() {
    const deps = {};
    
    // Services that have special build requirements
    const importantDeps = [
      '@fortawesome/fontawesome-pro',
      '@karmalicious/realtime-sdk',
      '@karmalicious/inventory-service-sdk',
      '@karmalicious/sale-service-sdk'
    ];

    if (this.packageJson?.dependencies) {
      for (const dep of importantDeps) {
        if (this.packageJson.dependencies[dep]) {
          deps[dep] = this.packageJson.dependencies[dep];
        }
      }
    }

    return deps;
  }

  requiresStaging() {
    const projectName = this.packageJson?.name || '';
    
    // Known projects that use staging
    const stagingProjects = [
      'storefront-web',
      'storefront-service',
      'karma-merchant-web',
      'karma-merchant-api'
    ];

    // Known projects that DON'T use staging
    const noStagingProjects = [
      'admin-frontend',
      'karma-admin-api',
      'karma-admin-frontend',
      'payment-service',
      'inventory-service',
      'location-service',
      'sale-service',
      'user-service',
      'cash-register',
      'karma-mobile-api'
    ];

    // Check explicit lists first
    if (stagingProjects.includes(projectName)) {
      return true;
    }
    
    if (noStagingProjects.includes(projectName)) {
      return false;
    }

    // Check if staging overlay already exists
    if (fs.existsSync(path.join(this.projectPath, 'kubernetes', 'overlays', 'staging'))) {
      return true;
    }

    // For customer-facing services (storefront/merchant), default to true
    // For internal/support services, default to false
    if (projectName.includes('storefront') || projectName.includes('merchant')) {
      return true;
    }

    return false;
  }
}

module.exports = {
  detectProject: () => new ProjectDetector().detectProject(),
  ProjectDetector
};