# cc_skills

Reusable Claude Code custom commands (skills) for Intel XPU / GPU development.

## Usage

Copy or symlink the commands you need into your project's `.claude/commands/` directory:

```bash
# Option 1: Symlink (recommended, auto-updates)
mkdir -p .claude/commands
ln -s /path/to/cc_skills/commands/unitrace.md .claude/commands/unitrace.md

# Option 2: Copy
mkdir -p .claude/commands
cp /path/to/cc_skills/commands/unitrace.md .claude/commands/

# Option 3: Global (available in all projects)
mkdir -p ~/.claude/commands
ln -s /path/to/cc_skills/commands/unitrace.md ~/.claude/commands/unitrace.md
```

Then in Claude Code, type `/unitrace <your request>` to invoke.

## Available Commands

| Command | Description |
|---------|-------------|
| `/unitrace` | Profile Intel GPU applications using unitrace (PTI-GPU). Supports 4 profiling levels: quick summary, timeline, hardware metrics, selective profiling. |

## Hooks

Reusable hook scripts that integrate with Claude Code's lifecycle events.

| Hook | Description |
|------|-------------|
| [`notify-teams.sh`](hooks/README.md) | Send notifications to Microsoft Teams via Workflows (Power Automate) webhook. Uses Adaptive Card format (replaces retired O365 Connector). |

Set `TEAMS_WEBHOOK_URL` and configure hooks in `.claude/settings.json` — see [`hooks/README.md`](hooks/README.md) for details.

## Requirements

- Intel oneAPI toolkit (icpx, Level Zero)
- Intel GPU (Arc, Data Center GPU Max, etc.)
- unitrace built from [intel/pti-gpu](https://github.com/intel/pti-gpu)
