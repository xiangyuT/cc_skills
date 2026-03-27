---
description: Sync skills between local project and xiangyuT/cc_skills repo (pull/push)
---

# Sync CC Skills

Sync commands between the local project's `.claude/commands/` and https://github.com/xiangyuT/cc_skills.

## User Request

$ARGUMENTS

## Determine Action

Parse `$ARGUMENTS` to decide which action to take:

- **pull** (default if no action specified, or "sync", "update", "pull"): Download latest skills from repo to current project
- **push** (or "push", "publish", "contribute", "upload"): Upload new/modified skills from current project to the repo
- **list**: Show available skills in the repo

If `$ARGUMENTS` also contains a specific command name (e.g., "push unitrace"), only operate on that one command.

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

1. Create `.claude/commands/` in the current project if it doesn't exist

2. Copy command files from repo to project:
   ```bash
   for f in <cc_skills_path>/commands/*.md; do
     cp "$f" .claude/commands/$(basename "$f")
   done
   ```

3. Report which commands were synced

## Action: Push (project -> repo)

1. Identify which `.claude/commands/*.md` files in the current project are new or modified compared to `<cc_skills_path>/commands/`:
   ```bash
   diff .claude/commands/<name>.md <cc_skills_path>/commands/<name>.md
   ```

2. For each new/modified file, copy it to the repo:
   ```bash
   cp .claude/commands/<name>.md <cc_skills_path>/commands/<name>md
   ```

3. If the skill is new, also update `<cc_skills_path>/README.md` to add it to the "Available Commands" table

4. Commit and push:
   ```bash
   cd <cc_skills_path>
   git add -A
   git commit -s -m "Add/update <name> command"
   git push origin main
   ```

5. Report what was pushed

## Action: List

1. List all `.md` files in `<cc_skills_path>/commands/` with their `description` from frontmatter

## Notes

- Commit messages should be in English and use `git commit -s` for Signed-off-by
- When pushing, review the diff with the user before committing if the changes are large
- The sync-skills.md command itself should also be synced (it's self-updating)
