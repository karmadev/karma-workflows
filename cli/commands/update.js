const fs = require('fs');
const path = require('path');
const chalk = require('chalk');
const ora = require('ora');
const semver = require('semver');
const { detectProject } = require('../utils/projectDetector');

async function updateCommand(options) {
  console.log(chalk.cyan('\n🔄 Karma Deploy Update\n'));

  const spinner = ora('Checking for updates...').start();

  try {
    // Detect current configuration
    const projectInfo = detectProject();
    
    // Check current versions
    const currentVersions = getCurrentVersions();
    spinner.succeed('Current configuration detected');

    if (options.check) {
      // Just check for updates without applying
      console.log(chalk.cyan('\n📊 Version Information:\n'));
      console.log(`  Deploy Script: ${currentVersions.deployScript || 'Not installed'}`);
      console.log(`  Workflow: ${currentVersions.workflow || 'Not installed'}`);
      console.log(`  CLI: ${currentVersions.cli}`);
      
      const updates = checkForUpdates(currentVersions);
      if (updates.length > 0) {
        console.log(chalk.yellow('\n⬆️  Updates available:'));
        updates.forEach(update => {
          console.log(`  • ${update.component}: ${update.current} → ${update.latest}`);
        });
      } else {
        console.log(chalk.green('\n✅ Everything is up to date!'));
      }
      return;
    }

    // Apply updates
    const updates = [];

    if (!options.workflowsOnly) {
      // Update deploy script
      spinner.start('Updating deploy script...');
      if (updateDeployScript()) {
        updates.push('deploy.sh');
        spinner.succeed('Deploy script updated');
      } else {
        spinner.info('Deploy script already up to date');
      }

      // Update .deploy.config if needed
      spinner.start('Checking deployment configuration...');
      if (updateDeployConfig(projectInfo)) {
        updates.push('.deploy.config');
        spinner.succeed('Deployment configuration updated');
      } else {
        spinner.info('Deployment configuration up to date');
      }
    }

    if (!options.scriptsOnly) {
      // Update GitHub Actions workflow
      spinner.start('Updating GitHub Actions workflow...');
      if (updateWorkflow(projectInfo)) {
        updates.push('.github/workflows/ci-cd.yml');
        spinner.succeed('GitHub Actions workflow updated');
      } else {
        spinner.info('GitHub Actions workflow up to date');
      }
    }

    // Summary
    if (updates.length > 0) {
      console.log(chalk.green(`\n✅ Updated ${updates.length} file(s):\n`));
      updates.forEach(file => {
        console.log(`  • ${file}`);
      });
      
      console.log(chalk.cyan('\n📝 Next Steps:\n'));
      console.log('1. Review the updated files');
      console.log('2. Test with: npm run deploy:dev');
      console.log('3. Commit the changes');
    } else {
      console.log(chalk.green('\n✅ Everything is already up to date!'));
    }

  } catch (error) {
    spinner.fail('Update failed');
    console.error(chalk.red(`\n❌ Error: ${error.message}\n`));
    process.exit(1);
  }
}

function getCurrentVersions() {
  const versions = {
    cli: require('../../package.json').version
  };

  // Check deploy script version
  const deployScriptPath = path.join(process.cwd(), 'deploy.sh');
  if (fs.existsSync(deployScriptPath)) {
    const content = fs.readFileSync(deployScriptPath, 'utf8');
    const versionMatch = content.match(/VERSION="([^"]+)"/);
    if (versionMatch) {
      versions.deployScript = versionMatch[1];
    }
  }

  // Check workflow version (from comments)
  const workflowPath = path.join(process.cwd(), '.github', 'workflows', 'ci-cd.yml');
  if (fs.existsSync(workflowPath)) {
    const content = fs.readFileSync(workflowPath, 'utf8');
    const versionMatch = content.match(/# Version: ([^\n]+)/);
    if (versionMatch) {
      versions.workflow = versionMatch[1];
    } else {
      versions.workflow = '1.0.0'; // Default for old workflows
    }
  }

  return versions;
}

function checkForUpdates(currentVersions) {
  const updates = [];
  const latestVersions = {
    deployScript: '2.0.0',
    workflow: '1.1.0',
    cli: require('../../package.json').version
  };

  for (const [component, current] of Object.entries(currentVersions)) {
    if (component === 'cli') continue; // Can't update CLI from within CLI
    
    const latest = latestVersions[component];
    if (current && latest && semver.lt(current, latest)) {
      updates.push({
        component,
        current,
        latest
      });
    }
  }

  return updates;
}

function updateDeployScript() {
  const sourcePath = path.join(__dirname, '../../scripts/deploy.sh');
  const targetPath = path.join(process.cwd(), 'deploy.sh');
  
  if (!fs.existsSync(targetPath)) {
    return false;
  }

  const sourceContent = fs.readFileSync(sourcePath, 'utf8');
  const targetContent = fs.readFileSync(targetPath, 'utf8');
  
  if (sourceContent !== targetContent) {
    fs.writeFileSync(targetPath, sourceContent);
    fs.chmodSync(targetPath, '755');
    return true;
  }
  
  return false;
}

function updateDeployConfig(projectInfo) {
  const configPath = path.join(process.cwd(), '.deploy.config');
  
  if (!fs.existsSync(configPath)) {
    return false;
  }

  const currentConfig = fs.readFileSync(configPath, 'utf8');
  
  // Check if any new configuration options need to be added
  const updates = [];
  
  if (projectInfo.staging && !currentConfig.includes('HAS_STAGING')) {
    updates.push('HAS_STAGING="true"');
  }
  
  if (projectInfo.features.graphql && !currentConfig.includes('HAS_GRAPHQL')) {
    updates.push('HAS_GRAPHQL="true"');
  }
  
  if (updates.length > 0) {
    const newConfig = currentConfig + '\n# Updated by karma-deploy CLI\n' + updates.join('\n') + '\n';
    fs.writeFileSync(configPath, newConfig);
    return true;
  }
  
  return false;
}

function updateWorkflow(projectInfo) {
  const workflowPath = path.join(process.cwd(), '.github', 'workflows', 'ci-cd.yml');
  
  if (!fs.existsSync(workflowPath)) {
    return false;
  }

  const currentContent = fs.readFileSync(workflowPath, 'utf8');
  
  // Check if workflow uses old format
  if (!currentContent.includes('karmadev/karma-workflows')) {
    console.log(chalk.yellow('\n⚠️  Workflow uses old format. Run "karma migrate" to update.'));
    return false;
  }
  
  // Check for missing features
  const updates = [];
  
  if (projectInfo.features.sentry && !currentContent.includes('sentry-release')) {
    updates.push('Sentry release job');
  }
  
  if (projectInfo.staging && !currentContent.includes('staging')) {
    updates.push('Staging environment support');
  }
  
  if (updates.length > 0) {
    console.log(chalk.yellow(`\n⚠️  Workflow may need updates for: ${updates.join(', ')}`));
    console.log('Run "karma init --force" to regenerate the workflow.');
    return false;
  }
  
  return false;
}

module.exports = updateCommand;