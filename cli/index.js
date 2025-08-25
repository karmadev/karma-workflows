#!/usr/bin/env node

const { program } = require('commander');
const chalk = require('chalk');
const path = require('path');
const fs = require('fs');

// Import commands
const initCommand = require('./commands/init');
const updateCommand = require('./commands/update');
const analyzeCommand = require('./commands/analyze');
const migrateCommand = require('./commands/migrate');

// Version from package.json
const packageJson = require('../package.json');

program
  .name('karma')
  .description('Karma Deployment CLI - Manage CI/CD pipelines and deployment scripts')
  .version(packageJson.version);

program
  .command('init')
  .description('Initialize deployment configuration for current project')
  .option('--force', 'Overwrite existing configuration')
  .option('--analyze', 'Analyze existing Buildkite pipeline if present')
  .option('--staging', 'Include staging environment setup')
  .action(initCommand);

program
  .command('update')
  .description('Update deployment scripts and workflows to latest version')
  .option('--check', 'Check for updates without applying them')
  .option('--scripts-only', 'Only update local scripts (deploy.sh, etc.)')
  .option('--workflows-only', 'Only update GitHub Actions workflows')
  .action(updateCommand);

program
  .command('analyze')
  .description('Analyze existing CI/CD setup (Buildkite, GitHub Actions, etc.)')
  .option('--json', 'Output analysis as JSON')
  .option('--verbose', 'Show detailed analysis')
  .action(analyzeCommand);

program
  .command('migrate')
  .description('Migrate from Buildkite to GitHub Actions')
  .option('--dry-run', 'Show what would be done without making changes')
  .option('--keep-buildkite', 'Keep Buildkite configuration files')
  .action(migrateCommand);

program
  .command('info')
  .description('Show information about current project setup')
  .action(() => {
    const projectInfo = require('./utils/projectDetector').detectProject();
    console.log(chalk.cyan('\n📊 Project Information:\n'));
    console.log(JSON.stringify(projectInfo, null, 2));
  });

// Error handling
program.exitOverride();

try {
  program.parse(process.argv);
} catch (err) {
  if (err.code === 'commander.unknownCommand') {
    console.error(chalk.red(`\n❌ Unknown command: ${err.message}\n`));
    program.outputHelp();
  } else {
    console.error(chalk.red(`\n❌ Error: ${err.message}\n`));
  }
  process.exit(1);
}

// Show help if no command provided
if (!process.argv.slice(2).length) {
  program.outputHelp();
}