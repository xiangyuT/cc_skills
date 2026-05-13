---
description: Install, update, or remove Claude Code hooks (e.g. Teams notifications, review-push) in settings.json
---

# Setup Hooks

Manage Claude Code hooks in `.claude/settings.local.json` — no manual JSON editing needed.

## User Request

$ARGUMENTS

## Determine Action

Parse `$ARGUMENTS` to decide what to do:

- **enable** (default, or "install", "add", "setup", "on"): Install hooks into settings
- **disable** (or "remove", "uninstall", "off"): Remove hooks from settings
- **status** (or "show", "list", "check"): Show current hook configuration
- **test**: Send a test notification to verify the hook works

If `$ARGUMENTS` specifies a hook type (e.g. "enable teams", "disable review-push"), only operate on that hook.
If no hook type is specified, show available hooks and ask which to install.

## Available Hook Types

| Name | Events | Script | Description |
|------|--------|--------|-------------|
| `teams` | Stop + Notification | `notify-teams.sh` | Teams notifications (recommended minimal) |
| `teams-full` | Stop + Notification + PreToolUse + PostToolUse | `notify-teams.sh` | Full Teams notifications (verbose) |
| `review-push` | PreToolUse (git push) | `review-push-hook.sh` | Block push if performance data detected |
| `gh-write-scope` | PreToolUse (Bash) | `gh-write-scope-hook.sh` | Block `gh` writes outside `xiangyuT/*` repos (reads allowed). Pairs with `recent-works-kanban` skill. |
| `git-push-scope` | PreToolUse (Bash, `git push*`) | `git-push-scope-hook.sh` | Block `git push` to remotes whose owner isn't `xiangyuT`. |
| `kanban-scope` | — (alias) | both above | Convenience alias: enables `gh-write-scope` + `git-push-scope` together. Use when activating the kanban workflow. |

## Common Setup

### Locate cc_skills repo

Find cc_skills repo for absolute path to hook scripts:

1. Check sibling directories of current workspace
2. Search: `$HOME/cc_skills`, `$HOME/xiangyu/cc_skills`
3. If not found, clone:
   ```bash
   git clone https://github.com/xiangyuT/cc_skills.git $HOME/cc_skills
   ```

Store as `$CC_SKILLS_PATH`.

### Determine settings file

- `--global`: Use `~/.claude/settings.json`
- Default: Use `.claude/settings.local.json` in current project

### Read existing settings

```bash
cat "$SETTINGS_FILE" 2>/dev/null || echo "{}"
```

Preserve all existing fields. Only modify the `hooks` section.

## Action: Enable

### Enable `teams`

1. Check `$TEAMS_WEBHOOK_URL` is set. If not, warn:
   > Set in shell profile:
   > `export TEAMS_WEBHOOK_URL="https://prod-xx.westus.logic.azure.com:443/workflows/..."`
   > See `hooks/README.md` for how to create a webhook in Teams.

2. Merge into settings using python3:

   ```python
   import json, sys

   settings_file = sys.argv[1]
   cc_skills_path = sys.argv[2]

   try:
       with open(settings_file) as f:
           settings = json.load(f)
   except (FileNotFoundError, json.JSONDecodeError):
       settings = {}

   notify_script = f"{cc_skills_path}/hooks/notify-teams.sh"
   hooks = settings.get("hooks", {})

   hooks.setdefault("Stop", []).append({
       "matcher": "",
       "hooks": [{
           "type": "command",
           "command": f"TEAMS_NOTIFY_EXIT_CODE=$EXIT_CODE {notify_script} 'Session Ended'"
       }]
   })
   hooks.setdefault("Notification", []).append({
       "matcher": "",
       "hooks": [{
           "type": "command",
           "command": f"{notify_script} 'Waiting for Input' \"$CLAUDE_NOTIFICATION\""
       }]
   })

   settings["hooks"] = hooks
   with open(settings_file, "w") as f:
       json.dump(settings, f, indent=2, ensure_ascii=False)
       f.write("\n")
   ```

3. Show the resulting settings file.

### Enable `teams-full`

Same as `teams` but also add PreToolUse and PostToolUse entries. Warn about high notification volume.

### Enable `review-push`

1. Copy `review-push-hook.sh` to `.claude/hooks/`:
   ```bash
   mkdir -p .claude/hooks
   cp "$CC_SKILLS_PATH/hooks/review-push-hook.sh" .claude/hooks/
   chmod +x .claude/hooks/review-push-hook.sh
   ```

2. Add PreToolUse hook entry:
   ```json
   {
     "matcher": "Bash",
     "hooks": [{
       "type": "command",
       "command": "bash .claude/hooks/review-push-hook.sh",
       "if": "Bash(git push*)",
       "timeout": 30,
       "statusMessage": "Scanning push diff for performance data..."
     }]
   }
   ```

### Enable `gh-write-scope`

1. Copy `gh-write-scope-hook.sh` to `.claude/hooks/`:
   ```bash
   mkdir -p .claude/hooks
   cp "$CC_SKILLS_PATH/hooks/gh-write-scope-hook.sh" .claude/hooks/
   chmod +x .claude/hooks/gh-write-scope-hook.sh
   ```

2. Add under the `PreToolUse` → matcher `"Bash"` entry (no `if:` — the hook inspects the command itself):
   ```json
   {
     "matcher": "Bash",
     "hooks": [{
       "type": "command",
       "command": "bash .claude/hooks/gh-write-scope-hook.sh",
       "timeout": 10,
       "statusMessage": "Checking gh write scope..."
     }]
   }
   ```

### Enable `git-push-scope`

1. Copy `git-push-scope-hook.sh` to `.claude/hooks/`:
   ```bash
   mkdir -p .claude/hooks
   cp "$CC_SKILLS_PATH/hooks/git-push-scope-hook.sh" .claude/hooks/
   chmod +x .claude/hooks/git-push-scope-hook.sh
   ```

2. Add PreToolUse hook entry (gated to `git push*`):
   ```json
   {
     "matcher": "Bash",
     "hooks": [{
       "type": "command",
       "command": "bash .claude/hooks/git-push-scope-hook.sh",
       "if": "Bash(git push*)",
       "timeout": 10,
       "statusMessage": "Checking git push target owner..."
     }]
   }
   ```

### Enable `kanban-scope` (alias)

Enables both `gh-write-scope` and `git-push-scope` in a single action.
Run the steps under each of those sections. This is the recommended
minimum when activating the `recent-works-kanban` skill in a workspace.

## Action: Disable

1. Read settings file
2. Remove hook entries that reference the specified script (e.g. `notify-teams.sh` or `review-push-hook.sh`)
3. Clean up empty event arrays and empty `hooks` object
4. Write back, preserving all other fields
5. Report what was removed

## Action: Status

Show a summary of all configured hooks:

```
Hook Configuration Status

Scope: project (.claude/settings.local.json)
  PreToolUse:   review-push-hook.sh (if: git push*)
  Stop:         notify-teams.sh
  Notification: notify-teams.sh

Environment:
  TEAMS_WEBHOOK_URL: set / NOT SET
```

If hook references a script that doesn't exist on disk, warn the user.

## Action: Test

### Test teams

```bash
"$CC_SKILLS_PATH/hooks/notify-teams.sh" "Test from /setup-hooks" "Hook verified at $(date -u +%H:%M:%S) UTC"
```

### Test review-push

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | bash .claude/hooks/review-push-hook.sh
echo "Exit code: $?"
```

### Test gh-write-scope

```bash
# Allowed (reads):
echo '{"tool_name":"Bash","tool_input":{"command":"gh issue list --repo intel/llm-scaler"}}' \
  | bash .claude/hooks/gh-write-scope-hook.sh
echo "Exit: $?"   # expect 0

# Blocked (write on non-xiangyuT):
echo '{"tool_name":"Bash","tool_input":{"command":"gh issue comment 123 --repo intel/llm-scaler --body hi"}}' \
  | bash .claude/hooks/gh-write-scope-hook.sh
echo "Exit: $?"   # expect 2

# Allowed (write on xiangyuT):
echo '{"tool_name":"Bash","tool_input":{"command":"gh issue edit 14 --repo xiangyuT/recent_works --add-label foo"}}' \
  | bash .claude/hooks/gh-write-scope-hook.sh
echo "Exit: $?"   # expect 0
```

### Test git-push-scope

```bash
# Blocked:
echo '{"tool_name":"Bash","tool_input":{"command":"git push intel-origin main"}}' \
  | bash .claude/hooks/git-push-scope-hook.sh
echo "Exit: $?"   # expect 2 if the remote URL owner isn't xiangyuT
```

## Notes

- This skill only manages hooks related to cc_skills (identified by script filenames)
- It never removes hooks created by other tools or manual configuration
- Uses python3 for JSON manipulation to ensure valid output
- If `$ARGUMENTS` is empty or "help", show usage summary
