---
description: Sync skills and hooks between local project and xiangyuT/cc_skills repo (pull/push)
---

# Sync CC Skills

Sync commands and hooks between the local project's `.claude/` and https://github.com/xiangyuT/cc_skills.

## User Request

$ARGUMENTS

## Determine Action

Parse `$ARGUMENTS` to decide which action to take:

- **pull** (default if no action specified, or "sync", "update", "pull"): Download latest from repo to current project
- **push** (or "push", "publish", "contribute", "upload"): Upload new/modified files from current project to the repo
- **list**: Show available resources in the repo

### Scope

By default, sync ALL resource types. If `$ARGUMENTS` specifies a scope, only sync that:

- `commands` or `skills`: only `.claude/commands/*.md`
- `hooks`: only `.claude/hooks/*`
- A specific name (e.g., "push unitrace"): only that one file

## Repo Structure

```
cc_skills/
├── commands/           # Slash command skills (.md)
│   ├── unitrace.md
│   ├── review-push.md
│   └── ...
├── hooks/              # Hook scripts (.sh)
│   ├── review-push-hook.sh
│   └── ...
└── README.md
```

## Common Setup

1. Find or clone the cc_skills repo locally:
   - Search: `$HOME/cc_skills`, `$HOME/xiangyu/cc_skills`, sibling directories of current workspace
   - If not found, clone to `$HOME/cc_skills`:
     ```bash
     git clone https://github.com/xiangyuT/cc_skills.git $HOME/cc_skills
     ```

2. Pull latest:
   ```bash
   cd <cc_skills_path> && git pull origin main
   ```

## Action: Pull (repo -> project)

### 1. Sync Commands

```bash
mkdir -p .claude/commands
for f in <cc_skills_path>/commands/*.md; do
  cp "$f" .claude/commands/$(basename "$f")
done
```

### 2. Sync Hooks

```bash
mkdir -p .claude/hooks
for f in <cc_skills_path>/hooks/*; do
  cp "$f" .claude/hooks/$(basename "$f")
  chmod +x ".claude/hooks/$(basename "$f")"
done
```

After copying hooks, check if the project's `.claude/settings.local.json` (or `.claude/settings.json`) has the corresponding hook entries configured. If a hook script exists but no matching hook config is found in settings, **warn the user** and show the suggested config snippet. Do NOT auto-modify settings.json — hooks need user review before activation.

### 3. Report

Report what was synced:
- Commands: N synced (list names)
- Hooks: N synced (list names), M need hook config

## Action: Push (project -> repo)

### 1. Push Commands

1. Identify new/modified `.claude/commands/*.md` files:
   ```bash
   diff .claude/commands/<name>.md <cc_skills_path>/commands/<name>.md
   ```
2. Copy changed files to repo:
   ```bash
   cp .claude/commands/<name>.md <cc_skills_path>/commands/<name>.md
   ```
3. If the command is new, update `<cc_skills_path>/README.md` Available Commands table

### 2. Push Hooks

1. Identify new/modified `.claude/hooks/*` files:
   ```bash
   diff .claude/hooks/<name> <cc_skills_path>/hooks/<name>
   ```
2. Copy changed files to repo:
   ```bash
   mkdir -p <cc_skills_path>/hooks
   cp .claude/hooks/<name> <cc_skills_path>/hooks/<name>
   ```

### 3. Commit and Push

```bash
cd <cc_skills_path>
git add -A
git commit -s -m "Add/update <resource_type>: <names>"
git push origin main
```

Review the diff with the user before committing if the changes are large.

## Action: List

List all available resources in the repo:

```
Commands:
  /unitrace          - Profile Intel GPU applications using unitrace
  /review-push       - Review git push diff for performance data
  ...

Hooks:
  review-push-hook.sh - Pre-push performance data scanner
  ...
```

Read the `description` from frontmatter (commands) or the first comment line (hooks/snippets).

## Notes

- Commit messages should be in English and use `git commit -s` for Signed-off-by
- When pushing, review the diff with the user before committing if the changes are large
- The sync-skills.md command itself should also be synced (it's self-updating)
- Hook scripts must be `chmod +x` after syncing
- Settings.json hook configs are NOT synced (project-specific) — only the scripts themselves
