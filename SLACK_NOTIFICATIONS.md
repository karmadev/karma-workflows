# Slack Notifications for GitHub Actions

## Overview
This repository's workflows now support sending deployment notifications to Slack. When a deployment completes successfully, a notification will be sent to your configured Slack channel.

## Setup Instructions

### 1. Create a Slack Webhook

1. Go to your Slack workspace's App Directory
2. Search for "Incoming WebHooks" or go to: https://slack.com/apps/A0F7XDUAZ-incoming-webhooks
3. Click "Add to Slack"
4. Choose the channel where you want notifications (e.g., #deployments, #github-actions)
5. Click "Add Incoming WebHooks integration"
6. Copy the Webhook URL (it will look like: `https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX`)

### 2. Organization Secret Already Configured

The organization-wide secret `SLACK_WEBHOOK_URL` is already configured and available to all repositories. No additional setup is needed!

### 3. How It Works

The workflows automatically use the organization-wide `SLACK_WEBHOOK_URL` secret. When you use the `node-service-pipeline.yml` workflow, it will automatically send notifications:

```yaml
jobs:
  deploy:
    uses: karmadev/karma-workflows/.github/workflows/node-service-pipeline.yml@main
    with:
      service-name: my-service
      # ... other inputs
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      GCP_SA_KEY: ${{ secrets.GCP_SA_KEY }}
      GITOPS_TOKEN: ${{ secrets.GITOPS_TOKEN }}
      SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}  # Automatically available from org
```

## What Gets Notified

Slack notifications are sent when:
- ✅ A deployment to Kubernetes completes successfully
- 📦 The deployment has been pushed to the GitOps repository
- 🚀 ArgoCD is ready to sync the changes

Each notification includes:
- Service name
- Environment (development/staging/production)
- Version or image tag
- Who triggered the deployment
- Link to the commit
- Link to the workflow run

## Notification Format

The Slack message will appear like this:

```
🚀 my-service Deployed to production
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Service: my-service
Environment: production
Version: v1.2.3
Deployed by: username

Commit: abc123def
Workflow: View Details
```

## Customizing Notifications

To customize the notification format, edit the `payload` in the `Send Slack Notification` step in `deploy-k8s.yml`.

The payload uses Slack's Block Kit format. You can design custom messages using:
- [Slack Block Kit Builder](https://app.slack.com/block-kit-builder)

## Troubleshooting

### Notifications Not Sending
1. Check that `SLACK_WEBHOOK_URL` is set in the repository secrets
2. Verify the webhook URL is correct and active
3. Check the workflow logs for any errors in the "Send Slack Notification" step

### Wrong Channel
1. Webhooks are tied to specific channels
2. To change the channel, create a new webhook for the desired channel

### Testing
To test your webhook, you can use curl:

```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test notification from GitHub Actions"}' \
  YOUR_WEBHOOK_URL
```

## Security Notes

- **Never commit webhook URLs to your repository**
- Webhook URLs should only be stored in GitHub Secrets
- If a webhook URL is compromised, regenerate it in Slack immediately
- Consider using separate webhooks for different environments

## Note on Environments

All environments (development, staging, production) use the same `SLACK_WEBHOOK_URL` organization secret and post to the same Slack channel. The environment name is included in each notification message for clarity.

## Support

For issues or questions about Slack notifications:
1. Check the GitHub Actions logs
2. Verify webhook configuration in Slack
3. Ensure secrets are properly set in GitHub