# Teams Notification Hooks

Send Claude Code lifecycle notifications to Microsoft Teams using **Workflows (Power Automate)** webhooks.

> **Note:** The legacy O365 Connector webhook (`*.webhook.office.com`) was retired at the end of 2025. This hook uses the replacement **Workflows (Power Automate)** approach, which requires **Adaptive Card** message format.

## Prerequisites

- Microsoft Teams with **Workflows** app enabled (requires admin approval in some orgs)
- `curl` and `bash` available on the machine running Claude Code

## Step 1: Create a Webhook in Teams

1. Open Microsoft Teams → go to the target **Channel**
2. Click **`...`** (more options) next to the channel name → select **Workflows**
3. Search for the template: **"Post to a channel when a webhook request is received"**
4. Name your workflow (e.g. `Claude Code Notifications`), confirm your Teams account, and select the target Team / Channel
5. Click **Add workflow**
6. **Copy the generated Webhook URL** — it looks like:
   ```
   https://prod-xx.westus.logic.azure.com:443/workflows/xxxxxxxx/triggers/manual/paths/invoke?api-version=2016-06-01&sp=...&sig=...
   ```

## Step 2: Set the Environment Variable

```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export TEAMS_WEBHOOK_URL="https://prod-xx.westus.logic.azure.com:443/workflows/..."
```

## Step 3: Configure Claude Code Hooks

Add hook entries to your project's `.claude/settings.json` (project-level) or `~/.claude/settings.json` (global):

```jsonc
{
  "hooks": {
    // Notify when a Claude Code session starts
    "PreToolUse": [],
    // Notify when a task completes (stop hook)
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/cc_skills/hooks/notify-teams.sh '✅ Task Completed' 'Claude Code session finished.'"
          }
        ]
      }
    ],
    // Notify on subcommand errors
    "PostToolUse": []
  }
}
```

### Example: notify on every session stop with exit code

```jsonc
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "TEAMS_NOTIFY_EXIT_CODE=$EXIT_CODE /path/to/cc_skills/hooks/notify-teams.sh '🔔 Session Ended'"
          }
        ]
      }
    ]
  }
}
```

## Step 4: Test

```bash
export TEAMS_WEBHOOK_URL="https://prod-xx.westus.logic.azure.com:443/workflows/..."
./hooks/notify-teams.sh "🧪 Test Notification" "If you see this in Teams, the webhook works!"
```

Expected output: `Teams notification sent successfully (HTTP 202).`

## Script Reference

### `notify-teams.sh`

| Argument | Description |
|----------|-------------|
| `$1` | Notification title (default: `Claude Code Notification`) |
| `$2` | Message body in markdown (auto-generated from hook context if omitted) |

| Environment Variable | Description |
|---------------------|-------------|
| `TEAMS_WEBHOOK_URL` | **(required)** Power Automate workflow webhook URL |
| `TEAMS_NOTIFY_EXIT_CODE` | Optional exit code to include in the notification |
| `CLAUDE_HOOK_EVENT` | Automatically set by Claude Code (e.g. `Stop`, `PostToolUse`) |
| `CLAUDE_PROJECT_DIR` | Automatically set by Claude Code — current project path |
| `CLAUDE_SESSION_ID` | Automatically set by Claude Code — session identifier |

## Key Difference from Legacy Webhooks

| Feature | Legacy O365 Connector | Workflows (Power Automate) |
|---------|----------------------|---------------------------|
| **Message format** | MessageCard / simple JSON | **Adaptive Card** (required) |
| **URL pattern** | `*.webhook.office.com` | `*.logic.azure.com` |
| **Status** | Retired (end of 2025) | Current recommended approach |
| **Management** | Channel Connector settings | Power Automate / Teams Workflows |
