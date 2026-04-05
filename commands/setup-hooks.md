---
description: Install, update, or remove Claude Code hooks (e.g. Teams notifications) in settings.json
---

# Setup Hooks

Manage Claude Code hooks in `.claude/settings.json` via a skill — no manual JSON editing needed.

## User Request

$ARGUMENTS

## Determine Action

Parse `$ARGUMENTS` to decide what to do:

- **enable** (default, or "install", "add", "setup", "on"): Install hooks into settings.json
- **disable** (or "remove", "uninstall", "off"): Remove hooks from settings.json
- **status** (or "show", "list", "check"): Show current hook configuration
- **test**: Send a test notification to verify the hook works

If `$ARGUMENTS` specifies a hook type (e.g. "enable teams", "disable notification"), only operate on that hook.
If no hook type is specified, operate on all available hooks.

## Available Hook Types

| Name | Events | Description |
|------|--------|-------------|
| `teams` | Stop + Notification | Teams notifications via `notify-teams.sh` (recommended minimal setup) |
| `teams-full` | Stop + Notification + PreToolUse + PostToolUse | Full Teams notifications (verbose) |

## Common Setup

### Step 1: Locate cc_skills repo

Find the cc_skills repo to get the absolute path to hook scripts:

1. Check if current directory is inside cc_skills repo:
   ```bash
   git remote -v 2>/dev/null | grep cc_skills
   ```
2. Search common locations: `$HOME/cc_skills`, `$HOME/xiangyu/cc_skills`, sibling directories of current workspace
3. If not found, clone:
   ```bash
   git clone https://github.com/xiangyuT/cc_skills.git $HOME/cc_skills
   ```

Store the absolute path as `$CC_SKILLS_PATH`.

### Step 2: Determine settings scope

Check `$ARGUMENTS` for scope:
- `--global` or `global`: Use `~/.claude/settings.json`
- `--project` or `project` (default): Use `.claude/settings.json` in the current project

Store the target file as `$SETTINGS_FILE`.

### Step 3: Read existing settings

```bash
if [ -f "$SETTINGS_FILE" ]; then
  cat "$SETTINGS_FILE"
else
  echo "{}"
fi
```

Parse the existing JSON. Preserve all non-hooks fields unchanged.

## Action: Enable

### Enable `teams` (recommended)

1. Check that `$TEAMS_WEBHOOK_URL` is set:
   ```bash
   echo "${TEAMS_WEBHOOK_URL:-NOT SET}"
   ```
   If not set, warn the user and explain how to set it:
   > Set `TEAMS_WEBHOOK_URL` in your shell profile (`~/.bashrc` or `~/.zshrc`):
   > ```bash
   > export TEAMS_WEBHOOK_URL="https://prod-xx.westus.logic.azure.com:443/workflows/..."
   > ```
   > See `hooks/README.md` for how to create a webhook in Teams.

2. Create `.claude/` directory if needed:
   ```bash
   mkdir -p "$(dirname "$SETTINGS_FILE")"
   ```

3. Build the hooks JSON and merge it into settings. The hooks to add:

   **Stop hook:**
   ```json
   {
     "matcher": "",
     "hooks": [
       {
         "type": "command",
         "command": "TEAMS_NOTIFY_EXIT_CODE=$EXIT_CODE <CC_SKILLS_PATH>/hooks/notify-teams.sh '🔔 Session Ended'"
       }
     ]
   }
   ```

   **Notification hook:**
   ```json
   {
     "matcher": "",
     "hooks": [
       {
         "type": "command",
         "command": "<CC_SKILLS_PATH>/hooks/notify-teams.sh '⏳ Waiting for Input' \"$CLAUDE_NOTIFICATION\""
       }
     ]
   }
   ```

4. Use `python3` or `jq` to merge hooks into the existing settings JSON **without overwriting** other fields:

   ```python
   import json, sys, os

   settings_file = sys.argv[1]
   cc_skills_path = sys.argv[2]

   # Read existing settings
   try:
       with open(settings_file) as f:
           settings = json.load(f)
   except (FileNotFoundError, json.JSONDecodeError):
       settings = {}

   notify_script = f"{cc_skills_path}/hooks/notify-teams.sh"

   # Build hooks
   hooks = settings.get("hooks", {})
   hooks["Stop"] = [
       {
           "matcher": "",
           "hooks": [
               {
                   "type": "command",
                   "command": f"TEAMS_NOTIFY_EXIT_CODE=$EXIT_CODE {notify_script} '🔔 Session Ended'"
               }
           ]
       }
   ]
   hooks["Notification"] = [
       {
           "matcher": "",
           "hooks": [
               {
                   "type": "command",
                   "command": f"{notify_script} '⏳ Waiting for Input' \"$CLAUDE_NOTIFICATION\""
               }
           ]
       }
   ]

   settings["hooks"] = hooks

   with open(settings_file, "w") as f:
       json.dump(settings, f, indent=2, ensure_ascii=False)
       f.write("\n")

   print(f"✅ Hooks written to {settings_file}")
   ```

5. Show the user what was written:
   ```bash
   cat "$SETTINGS_FILE"
   ```

6. Report success and remind user to ensure `TEAMS_WEBHOOK_URL` is set.

### Enable `teams-full`

Same as `teams` but also add `PreToolUse` and `PostToolUse` entries:
- **PreToolUse**: notify on tool invocation
- **PostToolUse**: notify on tool completion / errors

Warn the user that this generates **significant notification volume**.

## Action: Disable

1. Read `$SETTINGS_FILE`
2. Remove the hooks entries that reference `notify-teams.sh` from each event type (Stop, Notification, PreToolUse, PostToolUse)
3. If a hook event array becomes empty after removal, remove the event key entirely
4. If the entire `hooks` object becomes empty, remove the `hooks` key
5. Write back the settings, preserving all other fields
6. Report what was removed

```python
import json, sys

settings_file = sys.argv[1]

with open(settings_file) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
removed = []

for event in list(hooks.keys()):
    original_len = len(hooks[event])
    hooks[event] = [
        h for h in hooks[event]
        if not any("notify-teams.sh" in hook.get("command", "")
                    for hook in h.get("hooks", []))
    ]
    if len(hooks[event]) < original_len:
        removed.append(event)
    if not hooks[event]:
        del hooks[event]

if not hooks:
    del settings["hooks"]
else:
    settings["hooks"] = hooks

with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"✅ Removed hooks from events: {', '.join(removed) if removed else '(none found)'}")
```

## Action: Status

1. Read `$SETTINGS_FILE` (both project and global)
2. Display a summary table:

```
📋 Hook Configuration Status

Scope: project (.claude/settings.json)
  Stop:         ✅ notify-teams.sh configured
  Notification: ✅ notify-teams.sh configured
  PreToolUse:   ❌ not configured
  PostToolUse:  ❌ not configured

Scope: global (~/.claude/settings.json)
  (no hooks configured)

Environment:
  TEAMS_WEBHOOK_URL: ✅ set (https://prod-...azure.com/...)
```

3. If hooks reference a script path that doesn't exist, warn:
   ```
   ⚠️  Hook script not found: /old/path/to/notify-teams.sh
      Run `/setup-hooks enable` to fix the path.
   ```

## Action: Test

1. Locate `notify-teams.sh` from `$CC_SKILLS_PATH`
2. Run it with a test message:
   ```bash
   "$CC_SKILLS_PATH/hooks/notify-teams.sh" "🧪 Test from /setup-hooks" "Hook setup verified at $(date -u +%H:%M:%S) UTC"
   ```
3. Report success or failure

## Instructions

1. Parse `$ARGUMENTS` for the action and options
2. If `$ARGUMENTS` is empty or "help", show usage:
   ```
   Usage: /setup-hooks <action> [options]

   Actions:
     enable [teams|teams-full]  Install hooks (default: teams)
     disable                    Remove all notification hooks
     status                     Show current hook configuration
     test                       Send a test notification

   Options:
     --global    Apply to ~/.claude/settings.json (all projects)
     --project   Apply to .claude/settings.json (default)

   Examples:
     /setup-hooks enable              # Install recommended hooks (Stop + Notification)
     /setup-hooks enable --global     # Install globally
     /setup-hooks enable teams-full   # Install all hook events
     /setup-hooks disable             # Remove notification hooks
     /setup-hooks status              # Check what's configured
     /setup-hooks test                # Verify webhook works
   ```
3. Execute the determined action
4. Always show the resulting configuration after changes
5. Remind user about `TEAMS_WEBHOOK_URL` if it's not set

## Notes

- This skill only manages hooks related to cc_skills (identified by `notify-teams.sh` in the command)
- It never removes hooks created by other tools or manual configuration
- The `python3` or `jq` approach ensures valid JSON output and preserves existing settings
- If neither `python3` nor `jq` is available, fall back to showing the user the JSON to paste manually
