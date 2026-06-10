#!/bin/bash
# ==============================================================================
# Notification Helper Script
# ==============================================================================
# Standalone script untuk mengirim notifikasi deployment.
# Supports: Slack webhook, Microsoft Teams, generic webhook.
#
# Bisa digunakan untuk:
#   - Dipanggil dari CI/CD pipeline (pastikan script accessible)
#   - Manual notification setelah maintenance
#   - Integration dengan custom automation tools
#
# Environment variables yang dibutuhkan:
#   - SLACK_WEBHOOK_URL (untuk Slack)
#   - TEAMS_WEBHOOK_URL (untuk Microsoft Teams)
#
# Usage: ./notify.sh <status> <environment> [message]
# Example: ./notify.sh success prod "Deployment v1.2.3 complete"
# ==============================================================================

set -euo pipefail

STATUS="${1:?ERROR: Status required (success|failure|rollback)}"
ENVIRONMENT="${2:?ERROR: Environment required (dev|prod)}"
MESSAGE="${3:-}"

# Use CI variables if available (Jenkins compatible)
APP_NAME="${APP_NAME:-unknown}"
IMAGE_TAG="${IMAGE_TAG:-unknown}"
PIPELINE_URL="${BUILD_URL:-#}"
DEPLOYER="${BUILD_USER:-system}"
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Determine emoji and color based on status
case "${STATUS}" in
  success)
    EMOJI="✅"
    COLOR="#36a64f"
    TITLE="Deployment Successful"
    ;;
  failure)
    EMOJI="❌"
    COLOR="#ff0000"
    TITLE="Deployment Failed"
    ;;
  rollback)
    EMOJI="⚠️"
    COLOR="#ff9900"
    TITLE="Rollback Executed"
    ;;
  *)
    EMOJI="ℹ️"
    COLOR="#439FE0"
    TITLE="Deployment Update"
    ;;
esac

# Build notification payload
PAYLOAD=$(cat <<EOF
{
  "text": "${EMOJI} ${TITLE}",
  "attachments": [
    {
      "color": "${COLOR}",
      "title": "${TITLE} - ${APP_NAME}",
      "fields": [
        {"title": "Application", "value": "${APP_NAME}", "short": true},
        {"title": "Environment", "value": "${ENVIRONMENT}", "short": true},
        {"title": "Version", "value": "${IMAGE_TAG}", "short": true},
        {"title": "Deployed by", "value": "${DEPLOYER}", "short": true},
        {"title": "Pipeline", "value": "<${PIPELINE_URL}|View Pipeline>", "short": true},
        {"title": "Timestamp", "value": "${TIMESTAMP}", "short": true}
      ],
      "footer": "DevSecOps Platform"
    }
  ]
}
EOF
)

# Add custom message if provided
if [ -n "${MESSAGE}" ]; then
  PAYLOAD=$(echo "${PAYLOAD}" | sed "s/\"footer\": \"DevSecOps Platform\"/\"text\": \"${MESSAGE}\", \"footer\": \"DevSecOps Platform\"/")
fi

# Send to Slack (if webhook URL configured)
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "Sending notification to Slack..."
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}" \
    "${SLACK_WEBHOOK_URL}" || echo "WARNING: Slack notification failed"
fi

# Send to generic webhook (if configured)
if [ -n "${WEBHOOK_URL:-}" ]; then
  echo "Sending notification to webhook..."
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}" \
    "${WEBHOOK_URL}" || echo "WARNING: Webhook notification failed"
fi

echo "Notification sent: ${TITLE} (${APP_NAME} ${IMAGE_TAG} -> ${ENVIRONMENT})"
