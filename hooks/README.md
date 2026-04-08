# Hooks

Reusable hook scripts for Claude Code lifecycle events.

## Available Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `review-push-hook.sh` | PreToolUse (git push) | Scan push diff for performance data, block if found. |
| `notify-teams.sh` | Stop / Notification | Send notifications to Microsoft Teams via Workflows (Power Automate) webhook. |

## notify-teams.sh

Send Claude Code lifecycle notifications to Microsoft Teams using Adaptive Card format.

### Prerequisites

- Microsoft Teams with **Workflows** app enabled
- `curl` and `bash`

### Step 1: Create a Webhook in Teams

1. Open Microsoft Teams -> target **Channel** or **Chat**
2. Click **`...`** -> **Workflows**
3. Search: **"Post to a channel when a webhook request is received"**
4. Name the workflow, configure target (Channel or Chat with recipient)
5. Copy the generated Webhook URL

### Step 1.5: Configure Adaptive Card Template in Power Automate

Edit the workflow's **"Post card in a chat or channel"** action,将 `messageBody` 字段替换为：

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.4",
  "body": [
    {"type":"TextBlock","text":"@{triggerBody()?['title']}","weight":"Bolder","size":"Medium","wrap":true},
    {"type":"TextBlock","text":"@{triggerBody()?['message']}","wrap":true},
    {"type":"FactSet","facts":[
      {"title":"Event","value":"@{triggerBody()?['event']}"},
      {"title":"Project","value":"@{triggerBody()?['project']}"},
      {"title":"Time","value":"@{triggerBody()?['timestamp']}"}
    ]}
  ]
}
```

This template uses Power Automate expressions (`@{...}`) to insert dynamic content from the webhook payload.

### Step 2: Set Environment Variable

```bash
# Add to ~/.bashrc or ~/.zshrc
export TEAMS_WEBHOOK_URL="https://prod-xx.westus.logic.azure.com:443/workflows/..."
```

### Step 3: Configure Hooks

Use `/setup-hooks enable` or manually add to `.claude/settings.local.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "TEAMS_NOTIFY_EXIT_CODE=$EXIT_CODE /path/to/cc_skills/hooks/notify-teams.sh 'Session Ended'"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/cc_skills/hooks/notify-teams.sh 'Waiting for Input' \"$CLAUDE_NOTIFICATION\""
          }
        ]
      }
    ]
  }
}
```

### Step 4: Test

```bash
export TEAMS_WEBHOOK_URL="https://..."
./hooks/notify-teams.sh "Test" "If you see this, webhook works!"
```

### Script Reference

| Argument | Description |
|----------|-------------|
| `$1` | Notification title (default: `Claude Code Notification`) |
| `$2` | Message body (auto-generated from hook context if omitted) |

| Environment Variable | Description |
|---------------------|-------------|
| `TEAMS_WEBHOOK_URL` | **(required)** Power Automate workflow webhook URL |
| `TEAMS_NOTIFY_EXIT_CODE` | Optional exit code to include in the notification |
| `CLAUDE_HOOK_EVENT` | Auto-set by Claude Code (e.g. `Stop`, `Notification`) |
| `CLAUDE_NOTIFICATION` | Auto-set by Claude Code for `Notification` events |
| `CLAUDE_PROJECT_DIR` | Auto-set by Claude Code — current project path |
| `CLAUDE_SESSION_ID` | Auto-set by Claude Code — session identifier |

## review-push-hook.sh

Scans `upstream..HEAD` diff for precise performance data patterns (timing, throughput, latency, benchmark files, etc.). Returns `permissionDecision: deny` to block `git push` if found.

Configure in `.claude/settings.local.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/review-push-hook.sh",
            "if": "Bash(git push*)",
            "timeout": 30,
            "statusMessage": "Scanning push diff for performance data..."
          }
        ]
      }
    ]
  }
}
```
