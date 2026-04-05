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

If `$ARGUMENTS` also contains a source name (e.g., "import comfyui-custom-node-skills"), only operate on that source.

## Supported Layout Types

The registry supports two layout types via the `type` field:

### type: commands (default)
Flat `.md` command files in a single directory.
```
<repo>/<path>/
  ├── foo.md
  └── bar.md
```
Imported into: `.claude/commands/<prefix><name>.md`

### type: skills
Skill directories, each containing a `SKILL.md` file (Claude Code skills format).
```
<repo>/<path>/
  ├── skill-a/
  │   └── SKILL.md
  └── skill-b/
      └── SKILL.md
```
Imported into: `.claude/skills/<prefix><name>/SKILL.md`

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

2. Determine the layout type (`type` field, default: `commands`).

3. **If type is `commands`** — find flat `.md` files:
   ```bash
   ls "$CACHE_DIR/<source_name>/<path>"/*.md
   ```

   Apply include/exclude filters, then copy:
   ```bash
   for f in <matching_files>; do
     filename="<prefix>$(basename "$f")"
     cp "$f" .claude/commands/"$filename"
   done
   ```

4. **If type is `skills`** — find skill directories (each must contain `SKILL.md`):
   ```bash
   for d in "$CACHE_DIR/<source_name>/<path>"/*/; do
     if [ -f "$d/SKILL.md" ]; then
       dirname=$(basename "$d")
       echo "$dirname"
     fi
   done
   ```

   Apply include/exclude filters on directory names, then copy:
   ```bash
   mkdir -p .claude/skills
   for d in <matching_dirs>; do
     dirname="<prefix>$(basename "$d")"
     mkdir -p .claude/skills/"$dirname"
     cp "$CACHE_DIR/<source_name>/<path>/$(basename "$d")/SKILL.md" \
        .claude/skills/"$dirname"/SKILL.md
   done
   ```

5. Report which skills were imported:
   ```
   Imported from <source_name> (type: <type>):
     ✓ comfyui-node-basics (new)
     ✓ comfyui-node-inputs (updated)
     - comfyui-node-outputs (unchanged, skipped)
   ```

## Action: List

For each source in `skills-registry.yaml`:

1. Clone or update from cache (same as import step 1)

2. List available skills based on type:

   **If type is `commands`:**
   ```bash
   for f in "$CACHE_DIR/<source_name>/<path>"/*.md; do
     desc=$(sed -n '/^---$/,/^---$/{ /^description:/s/^description: *//p }' "$f")
     echo "  $(basename "$f"): $desc"
   done
   ```

   **If type is `skills`:**
   ```bash
   for d in "$CACHE_DIR/<source_name>/<path>"/*/; do
     if [ -f "$d/SKILL.md" ]; then
       # Extract first heading from SKILL.md as description
       desc=$(sed -n 's/^# *//p; T; q' "$d/SKILL.md")
       echo "  $(basename "$d")/: $desc"
     fi
   done
   ```

3. Display output:
   ```
   Source: comfyui-custom-node-skills (type: skills)
     - comfyui-node-basics/: ComfyUI Node Basics
     - comfyui-node-inputs/: ComfyUI Node Inputs
     - comfyui-node-outputs/: ComfyUI Node Outputs
     ...
   ```

## Action: Add Source

Parse `$ARGUMENTS` for the repo URL and optional parameters:

```
/import-skills add <repo_url> [--name <name>] [--type <commands|skills>] [--branch <branch>] [--path <path>] [--prefix <prefix>]
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

3. Auto-detect type if `--type` is not provided:
   - Clone the repo to cache, then check the structure:
     - If `<path>/` contains subdirectories with `SKILL.md` → `type: skills`
     - If `<path>/` contains flat `.md` files → `type: commands`

4. Check for duplicate names in the registry

5. Append the new source to `skills-registry.yaml`:
   ```yaml
   sources:
     - name: <name>
       repo: <repo_url>
       branch: <branch>       # default: main
       type: <type>           # default: commands
       path: <path>           # default: commands or skills based on type
       prefix: <prefix>       # default: empty
   ```

6. Confirm the addition:
   ```
   ✓ Added source '<name>' (type: <type>, <repo_url>)
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

2. Compare imported files/directories with cache based on type:

   **If type is `commands`:**
   ```bash
   diff .claude/commands/<prefix><skill>.md "$CACHE_DIR/<source_name>/<path>/<skill>.md"
   ```

   **If type is `skills`:**
   ```bash
   diff .claude/skills/<prefix><skill>/SKILL.md "$CACHE_DIR/<source_name>/<path>/<skill>/SKILL.md"
   ```

3. Display status:
   ```
   Source: comfyui-custom-node-skills (type: skills)
     ✓ comfyui-node-basics — up-to-date
     ✗ comfyui-node-inputs — outdated (remote has changes)
     ? comfyui-node-frontend — not imported
   ```

## Notes

- External files are copied, not symlinked, to avoid dependency on the cache
- The `prefix` option helps avoid naming conflicts between sources
- Cache directory (`$HOME/.cc_skills_cache/`) can be cleaned with `rm -rf $HOME/.cc_skills_cache`
- If a skill already exists and comes from a different source, warn the user before overwriting
- When adding a new source, verify the repo is accessible before saving to the registry
- All git operations use `--depth 1` for efficiency
- The `type` field determines the import layout:
  - `commands` → `.claude/commands/` (flat `.md` files, used as `/command` in Claude Code)
  - `skills` → `.claude/skills/` (directories with `SKILL.md`, auto-loaded by Claude Code)
