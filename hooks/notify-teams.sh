#!/usr/bin/env bash
# notify-teams.sh — Send Claude Code hook notifications to Microsoft Teams
# via Workflows (Power Automate) webhook.
#
# Usage:
#   Called automatically by Claude Code hooks, or manually:
#     ./notify-teams.sh "Your notification title" "Your message body"
#
# Environment:
#   TEAMS_WEBHOOK_URL  (required) — Power Automate workflow webhook URL
#   TEAMS_NOTIFY_EXIT_CODE — if set, include exit code in notification
#
# Claude Code hook environment variables (automatically set when called as a hook):
#   CLAUDE_SESSION_ID, CLAUDE_PROJECT_DIR, CLAUDE_HOOK_EVENT, etc.

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

if [ -z "${TEAMS_WEBHOOK_URL:-}" ]; then
  echo "ERROR: TEAMS_WEBHOOK_URL is not set. Skipping Teams notification." >&2
  exit 0  # exit 0 so hook doesn't block Claude Code
fi

# ── Parse arguments / hook context ───────────────────────────────────────────

TITLE="${1:-Claude Code Notification}"
BODY="${2:-}"

# Build contextual info from Claude Code hook env vars (if available)
HOOK_EVENT="${CLAUDE_HOOK_EVENT:-unknown}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_ID="${CLAUDE_SESSION_ID:-N/A}"
EXIT_CODE="${TEAMS_NOTIFY_EXIT_CODE:-}"

# Auto-generate body from hook context if not provided
if [ -z "$BODY" ]; then
  BODY="Hook event: **${HOOK_EVENT}**"
  if [ -n "$EXIT_CODE" ]; then
    BODY="${BODY}  \nExit code: \`${EXIT_CODE}\`"
  fi
  BODY="${BODY}  \nProject: \`${PROJECT_DIR}\`  \nSession: \`${SESSION_ID}\`"
fi

# Choose accent color based on exit code
ACCENT_COLOR="Good"  # green
if [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ]; then
  ACCENT_COLOR="Attention"  # red
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Build Adaptive Card payload ──────────────────────────────────────────────
# Power Automate Workflows require Adaptive Card format (not legacy MessageCard).

read -r -d '' PAYLOAD <<EOF || true
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "contentUrl": null,
      "content": {
        "\$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.4",
        "body": [
          {
            "type": "TextBlock",
            "text": "${TITLE}",
            "weight": "Bolder",
            "size": "Medium",
            "color": "${ACCENT_COLOR}",
            "wrap": true
          },
          {
            "type": "TextBlock",
            "text": "${BODY}",
            "wrap": true
          },
          {
            "type": "FactSet",
            "facts": [
              { "title": "Event", "value": "${HOOK_EVENT}" },
              { "title": "Project", "value": "${PROJECT_DIR}" },
              { "title": "Time (UTC)", "value": "${TIMESTAMP}" }
            ]
          }
        ]
      }
    }
  ]
}
EOF

# ── Send to Teams ────────────────────────────────────────────────────────────

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${TEAMS_WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  --connect-timeout 10 \
  --max-time 30)

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "Teams notification sent successfully (HTTP ${HTTP_CODE})."
else
  echo "WARNING: Teams notification failed (HTTP ${HTTP_CODE})." >&2
  # Don't exit 1 — avoid blocking Claude Code hooks
fi
