---
description: Import and sync skills from external repositories defined in skills-registry.yaml
---

# Import External Skills

Fetch, list, or manage skills from external repositories registered in `skills-registry.yaml`.

## User Request

$ARGUMENTS

## Determine Action

Parse `$ARGUMENTS` to decide which action to take:

- **import** (default if no action specified, or "sync", "fetch", "pull"): Import skills from external repos into this project
- **list**: Show registered external sources and their available skills
- **add-source** (or "register", "add"): Add a new external repo to `skills-registry.yaml`
- **remove-source** (or "unregister", "remove"): Remove an external repo from `skills-registry.yaml`
- **status**: Show which imported skills are up-to-date vs outdated

If `$ARGUMENTS` also contains a source name (e.g., "import pti-skills"), only operate on that source.

## Common Setup

1. Locate the cc_skills repo root (where `skills-registry.yaml` lives):
   - Check current working directory and parent directories
   - Check `$HOME/cc_skills`
   - Check sibling directories of current workspace

2. Read and parse `skills-registry.yaml`:
   ```bash
   cat <cc_skills_root>/skills-registry.yaml
   ```

3. If registry is empty or file doesn't exist, inform the user and suggest using `add-source` first.

## Action: Import (external repos -> project)

For each source in `skills-registry.yaml` (or the specified source):

1. Clone or update the external repo into a cache directory:
   ```bash
   CACHE_DIR="$HOME/.cc_skills_cache"
   mkdir -p "$CACHE_DIR"

   # Clone if not cached
   if [ ! -d "$CACHE_DIR/<source_name>" ]; then
     git clone --depth 1 --branch <branch> <repo_url> "$CACHE_DIR/<source_name>"
   else
     cd "$CACHE_DIR/<source_name>"
     git fetch origin <branch> --depth 1
     git checkout FETCH_HEAD
   fi
   ```

2. Find skill files in the source repo:
   ```bash
   ls "$CACHE_DIR/<source_name>/<path>"/*.md
   ```

3. Apply include/exclude filters if configured:
   - `includes`: Only import files matching these glob patterns
   - `excludes`: Skip files matching these glob patterns

4. Copy matching skill files to `<cc_skills_root>/commands/`:
   ```bash
   for f in <matching_files>; do
     filename="<prefix>$(basename "$f")"
     cp "$f" <cc_skills_root>/commands/"$filename"
   done
   ```

5. Report which skills were imported:
   ```
   Imported from <source_name>:
     ✓ <prefix>skill1.md (new)
     ✓ <prefix>skill2.md (updated)
     - skill3.md (unchanged, skipped)
   ```

6. If importing into a project (not the cc_skills repo itself), also copy to `.claude/commands/`:
   ```bash
   mkdir -p .claude/commands
   cp <cc_skills_root>/commands/<imported_files> .claude/commands/
   ```

## Action: List

For each source in `skills-registry.yaml`:

1. Clone or update from cache (same as import step 1)

2. List available skills with descriptions:
   ```bash
   for f in "$CACHE_DIR/<source_name>/<path>"/*.md; do
     # Extract description from YAML frontmatter
     desc=$(sed -n '/^---$/,/^---$/{ /^description:/s/^description: *//p }' "$f")
     echo "  $(basename "$f"): $desc"
   done
   ```

3. Display output:
   ```
   Source: <source_name> (<repo_url>)
     - skill1.md: Description of skill 1
     - skill2.md: Description of skill 2

   Source: <source_name_2> (<repo_url_2>)
     - skill3.md: Description of skill 3
   ```

## Action: Add Source

Parse `$ARGUMENTS` for the repo URL and optional parameters:

```
/import-skills add <repo_url> [--name <name>] [--branch <branch>] [--path <path>] [--prefix <prefix>]
```

1. Validate the repo URL:
   ```bash
   git ls-remote <repo_url> >/dev/null 2>&1
   ```

2. Determine a default name from the repo URL if `--name` is not provided:
   ```bash
   # e.g., https://github.com/user/my-skills.git -> my-skills
   name=$(basename <repo_url> .git)
   ```

3. Check for duplicate names in the registry

4. Append the new source to `skills-registry.yaml`:
   ```yaml
   sources:
     - name: <name>
       repo: <repo_url>
       branch: <branch>       # default: main
       path: <path>           # default: commands
       prefix: <prefix>       # default: empty
   ```

5. Confirm the addition:
   ```
   ✓ Added source '<name>' (<repo_url>)
   Run `/import-skills import <name>` to fetch skills.
   ```

## Action: Remove Source

```
/import-skills remove <source_name>
```

1. Find and remove the source entry from `skills-registry.yaml`
2. Optionally clean up cached clone:
   ```bash
   rm -rf "$HOME/.cc_skills_cache/<source_name>"
   ```
3. Confirm removal (but do NOT delete already-imported skill files)

## Action: Status

For each source in `skills-registry.yaml`:

1. Compare local cached version with remote:
   ```bash
   cd "$HOME/.cc_skills_cache/<source_name>"
   git fetch origin <branch> --depth 1
   LOCAL=$(git rev-parse HEAD)
   REMOTE=$(git rev-parse FETCH_HEAD)
   ```

2. For each imported skill, check if local copy differs from cache:
   ```bash
   diff <cc_skills_root>/commands/<prefix><skill>.md "$CACHE_DIR/<source_name>/<path>/<skill>.md"
   ```

3. Display status:
   ```
   Source: <source_name>
     ✓ skill1.md — up-to-date
     ✗ skill2.md — outdated (remote has changes)
     ? skill3.md — not imported
   ```

## Notes

- External skill files are copied, not symlinked, to avoid dependency on the cache
- The `prefix` option helps avoid filename conflicts between sources (e.g., `pti-debug.md` vs `team-debug.md`)
- Cache directory (`$HOME/.cc_skills_cache/`) can be cleaned with `rm -rf $HOME/.cc_skills_cache`
- If a skill file already exists and comes from a different source, warn the user before overwriting
- When adding a new source, verify the repo is accessible before saving to the registry
- All git operations use `--depth 1` for efficiency
