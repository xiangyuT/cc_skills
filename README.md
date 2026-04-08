# cc_skills

Reusable Claude Code skills and hooks for Intel XPU / GPU development.

## Repo Structure

```
cc_skills/
├── commands/               # Slash command skills (.md)
├── hooks/                  # Hook scripts (.sh)
├── skills-registry.yaml    # External skill sources
└── README.md
```

## Usage

### Quick Start

Use `/sync-skills pull` to sync commands and hooks:

```
/sync-skills pull
```

Use `/import-skills` to import from external repos:

```
/import-skills import
```

### Manual Setup

```bash
# Commands
mkdir -p .claude/commands
cp /path/to/cc_skills/commands/*.md .claude/commands/

# Hooks
mkdir -p .claude/hooks
cp /path/to/cc_skills/hooks/*.sh .claude/hooks/
chmod +x .claude/hooks/*
# Then configure hook entries — use /setup-hooks or see hooks/README.md
```

## Available Commands

| Command | Description |
|---------|-------------|
| `/unitrace` | Profile Intel GPU applications using unitrace (PTI-GPU). Supports 4 profiling levels. |
| `/comfyui-benchmark` | Run ComfyUI e2e benchmark workflows and collect performance data. |
| `/review-push` | Review git push diff for sensitive performance data that should not be pushed. |
| `/sync-skills` | Sync skills and hooks between local project and this repo. |
| `/setup-hooks` | Install, update, or remove hooks in settings.json — no manual JSON editing. |
| `/import-skills` | Import skills from external repositories defined in `skills-registry.yaml`. |

## Available Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `review-push-hook.sh` | PreToolUse (git push) | Scan push diff for performance data, block if found. |
| `notify-teams.sh` | Stop / Notification | Send notifications to Microsoft Teams via Power Automate webhook. |

Use `/setup-hooks enable <hook>` to configure, or see [hooks/README.md](hooks/README.md) for manual setup.

## External Skills Integration

Import skills from any external Git repo via `skills-registry.yaml`. Two layout types:

| Type | Repo layout | Imported to |
|------|-------------|-------------|
| `commands` | flat `.md` files | `.claude/commands/` |
| `skills` | directories with `SKILL.md` | `.claude/skills/` |

Pre-configured source: [comfyui-custom-node-skills](https://github.com/jtydhr88/comfyui-custom-node-skills) — 9 skills for ComfyUI custom node development.

```
/import-skills add <repo_url>       # register a source
/import-skills import               # import all
/import-skills list                  # list available
/import-skills status               # check updates
```

## Requirements

- Intel oneAPI toolkit (icpx, Level Zero)
- Intel GPU (Arc, Data Center GPU Max, etc.)
- unitrace built from [intel/pti-gpu](https://github.com/intel/pti-gpu)
