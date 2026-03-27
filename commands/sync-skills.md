---
description: Sync cc_skills commands from xiangyuT/cc_skills repo to current project
---

# Sync CC Skills

Pull the latest commands from https://github.com/xiangyuT/cc_skills and install them into the current project's `.claude/commands/` directory.

## User Request

$ARGUMENTS

## Instructions

1. Check if cc_skills repo is already cloned locally. Search common locations:
   - `$HOME/cc_skills`
   - `$HOME/xiangyu/cc_skills`
   - Sibling directories of the current workspace
   - If not found, clone it to `$HOME/cc_skills`

2. Pull latest changes:
   ```bash
   cd <cc_skills_path> && git pull origin main
   ```

3. Create `.claude/commands/` in the current project if it doesn't exist

4. Sync all command files (excluding sync-skills.md itself to avoid circular dependency):
   ```bash
   for f in <cc_skills_path>/commands/*.md; do
     name=$(basename "$f")
     [ "$name" = "sync-skills.md" ] && continue
     cp "$f" .claude/commands/"$name"
   done
   ```

5. Report which commands were synced and any new commands added

If `$ARGUMENTS` contains a specific command name (e.g., "unitrace"), only sync that one command instead of all.
