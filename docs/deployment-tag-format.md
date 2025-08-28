# Development Deployment Tag Format Update

## Overview
We've updated our deployment tag format for development environments to avoid version number confusion and conflicts between development and production deployments.

## New Tag Format

### Development Tags
**Format**: `dev-YYYYMMDD-HHMM-N`

Examples:
- `dev-20250828-1430-1` - First deployment at 14:30 on August 28, 2025
- `dev-20250828-1430-2` - Second deployment at 14:30 (if multiple deploys in same minute)
- `dev-20250828-1535-1` - First deployment at 15:35

### Production/Staging Tags (Unchanged)
- **Production**: `v1.0.0`, `v2.1.3`
- **Staging**: `v1.0.0-staging`, `v2.1.3-staging`

## Why This Change?

### Previous Issues
- Development used tags like `v1.1.2-dev` which created confusion with semantic versioning
- Risk of version conflicts when dev versions exceeded production versions
- Difficult to track when a dev deployment was made
- Package.json version could conflict with tag versions

### Benefits of New Format
- Clear separation between development builds and versioned releases
- Timestamp shows exactly when deployment occurred
- No version number conflicts
- Multiple developers can deploy without conflicts
- Build numbers reset each minute (not daily)

## Migration Guide

### For GitHub Actions Workflows

If your workflow triggers on tags, update the pattern:

**Old Pattern**:
```yaml
on:
  push:
    tags:
      - 'v*'  # This caught v1.0.0-dev, v1.0.0-staging, v1.0.0
```

**New Pattern**:
```yaml
on:
  push:
    tags:
      - 'v*'           # Production and staging (v1.0.0, v1.0.0-staging)
      - 'dev-*'        # Development (dev-20250828-1430-1)
```

### For Environment Detection

Update your environment detection logic:

**Old Logic**:
```yaml
- name: Determine environment
  run: |
    if [[ "${{ github.ref }}" == refs/tags/v*-dev ]]; then
      echo "environment=development" >> $GITHUB_OUTPUT
    elif [[ "${{ github.ref }}" == refs/tags/v*-staging ]]; then
      echo "environment=staging" >> $GITHUB_OUTPUT
    elif [[ "${{ github.ref }}" == refs/tags/v* ]]; then
      echo "environment=production" >> $GITHUB_OUTPUT
    fi
```

**New Logic**:
```yaml
- name: Determine environment
  run: |
    if [[ "${{ github.ref }}" == refs/tags/dev-* ]]; then
      echo "environment=development" >> $GITHUB_OUTPUT
    elif [[ "${{ github.ref }}" == refs/tags/v*-staging ]]; then
      echo "environment=staging" >> $GITHUB_OUTPUT
    elif [[ "${{ github.ref }}" == refs/tags/v* ]]; then
      echo "environment=production" >> $GITHUB_OUTPUT
    fi
```

### For Kustomization Files

Update image tag patterns in your kustomization.yaml:

**Old**:
```yaml
images:
- name: my-service
  newTag: v1.1.2-dev
```

**New**:
```yaml
images:
- name: my-service
  newTag: dev-20250828-1430-1
```

### For ArgoCD Applications

If you have ArgoCD automated sync based on tag patterns, update the regex:

**Old**:
```yaml
spec:
  source:
    targetRevision: HEAD
    # or
    targetRevision: v*-dev
```

**New**:
```yaml
spec:
  source:
    targetRevision: HEAD
    # or
    targetRevision: dev-*
```

## Deploy Script Updates

### Getting the Updated Script

The updated deploy script is available in these repositories:
- `karma-merchant-web/deploy.sh`
- `Karma-Merchant-API/deploy.sh`
- `storefront-web/deploy.sh`
- `storefront-functions/deploy.sh`

### Key Changes in Deploy Script

1. **New function for dev builds**:
```bash
get_next_dev_build() {
    local datetime=$(date +%Y%m%d-%H%M)
    local latest_build=0
    
    # Look for tags from this minute
    local current_tags=$(git tag -l "dev-${datetime}-*" 2>/dev/null | grep -E "^dev-${datetime}-[0-9]+$" || true)
    
    if [ -n "$current_tags" ]; then
        latest_build=$(echo "$current_tags" | sed "s/dev-${datetime}-//" | sort -n | tail -n 1)
    fi
    
    echo "${datetime}-$((latest_build + 1))"
}
```

2. **Updated tag creation**:
```bash
if [ "$env" = "development" ] || [ "$env" = "dev" ]; then
    tag="dev-${version}"  # version is now YYYYMMDD-HHMM-N
elif [ "$env" = "staging" ]; then
    tag="${VERSION_PREFIX}${version}-staging"
else
    tag="${VERSION_PREFIX}${version}"  # Production
fi
```

3. **Updated recent tags display**:
```bash
# Show recent dev builds with datetime format
git tag -l "dev-*" | grep -E "^dev-[0-9]{8}-[0-9]{4}-[0-9]+$" | sort -t- -k2,3 | tail -5
```

## Rollout Plan

### Phase 1: Update Deploy Scripts (Completed)
- ✅ Update deploy.sh in main repositories
- ✅ Test new tag format
- ✅ Document changes

### Phase 2: Update CI/CD Workflows
- Update GitHub Actions workflows to recognize new tag format
- Update environment detection logic
- Test deployments with new tags

### Phase 3: Clean Up Old Dev Tags
After confirming all systems work with new format:
```bash
# List old dev tags
git tag -l "v*-dev"

# Delete old dev tags locally (be careful!)
git tag -l "v*-dev" | xargs -n 1 git tag -d

# Delete from remote (be VERY careful!)
git tag -l "v*-dev" | xargs -n 1 git push origin --delete
```

## FAQ

**Q: What happens to existing v*-dev tags?**  
A: They remain functional but deprecated. New deployments use the new format. Old tags can be cleaned up after migration.

**Q: Can I still deploy specific versions to dev?**  
A: Yes, but dev always uses the datetime format now. Use staging for testing specific versions.

**Q: What if two people deploy at the exact same minute?**  
A: The script handles this with the `-N` counter. First deploy gets `-1`, second gets `-2`, etc.

**Q: How do I find a specific dev deployment?**  
A: The datetime in the tag tells you exactly when it was deployed: `dev-20250828-1430-1` = August 28, 2025 at 14:30.

## Support

For questions or issues with the new tag format:
1. Check this documentation
2. Review the updated deploy.sh script
3. Contact the DevOps team

## Related Documents
- [CI/CD Pipeline Documentation](./ci-cd-pipeline.md)
- [GitHub Actions Workflows](./github-actions.md)
- [Deployment Best Practices](./deployment-best-practices.md)