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
- **list**: Show registered sources and their available skills
- **add** (or "register", "add-source"): Add a new external repo to the registry
- **remove** (or "unregister", "remove-source"): Remove a source from the registry
- **status**: Show which imported skills are up-to-date vs outdated

If `$ARGUMENTS` contains a source name (e.g., "import comfyui-custom-node-skills"), only operate on that source.

## Supported Layout Types

### type: commands (default)
Flat `.md` command files in a single directory.
```
<repo>/<path>/
  ├── foo.md
  └── bar.md
```
Imported into: `.claude/commands/<prefix><name>.md`

### type: skills
Skill directories, each containing a `SKILL.md` file.
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
   - Check sibling directories of current workspace
   - Check `$HOME/cc_skills`, `$HOME/xiangyu/cc_skills`

2. Read and parse `skills-registry.yaml`:
   ```bash
   cat <cc_skills_root>/skills-registry.yaml
   ```

3. If registry is empty or doesn't exist, inform user and suggest `add` first.

## Action: Import

For each source in `skills-registry.yaml` (or the specified source):

1. Clone or update into cache:
   ```bash
   CACHE_DIR="$HOME/.cc_skills_cache"
   mkdir -p "$CACHE_DIR"

   if [ ! -d "$CACHE_DIR/<source_name>" ]; then
     git clone --depth 1 --branch <branch> <repo_url> "$CACHE_DIR/<source_name>"
   else
     cd "$CACHE_DIR/<source_name>"
     git fetch origin <branch> --depth 1
     git checkout FETCH_HEAD
   fi
   ```

2. Based on `type`:

   **commands:**
   ```bash
   mkdir -p .claude/commands
   for f in "$CACHE_DIR/<source_name>/<path>"/*.md; do
     filename="<prefix>$(basename "$f")"
     cp "$f" .claude/commands/"$filename"
   done
   ```

   **skills:**
   ```bash
   mkdir -p .claude/skills
   for d in "$CACHE_DIR/<source_name>/<path>"/*/; do
     if [ -f "$d/SKILL.md" ]; then
       dirname="<prefix>$(basename "$d")"
       mkdir -p .claude/skills/"$dirname"
       cp "$d/SKILL.md" .claude/skills/"$dirname"/SKILL.md
     fi
   done
   ```

3. Apply `includes`/`excludes` glob filters if specified.

4. Report results:
   ```
   Imported from <source_name> (type: <type>):
     + comfyui-node-basics (new)
     ~ comfyui-node-inputs (updated)
     = comfyui-node-outputs (unchanged)
   ```

## Action: List

For each source, clone/update cache, then list available items:

**commands:** List `.md` files with frontmatter `description`.
**skills:** List directories with first heading from `SKILL.md`.

```
Source: comfyui-custom-node-skills (type: skills)
  comfyui-node-basics     - ComfyUI Node Basics
  comfyui-node-inputs     - ComfyUI Node Inputs
  comfyui-node-outputs    - ComfyUI Node Outputs
  ...
```

## Action: Add

```
/import-skills add <repo_url> [--name <name>] [--type <commands|skills>] [--branch <branch>] [--path <path>] [--prefix <prefix>]
```

1. Validate repo URL:
   ```bash
   git ls-remote <repo_url> >/dev/null 2>&1
   ```

2. Default name from URL if `--name` not given:
   ```bash
   basename <repo_url> .git
   ```

3. Auto-detect type if `--type` not given: clone to cache, check if `<path>/` contains subdirs with `SKILL.md` (skills) or flat `.md` files (commands).

4. Check for duplicate names.

5. Append to `skills-registry.yaml`.

6. Confirm:
   ```
   Added source '<name>' (type: <type>)
   Run `/import-skills import <name>` to fetch.
   ```

## Action: Remove

```
/import-skills remove <source_name>
```

1. Remove entry from `skills-registry.yaml`
2. Optionally clean cache: `rm -rf "$HOME/.cc_skills_cache/<source_name>"`
3. Do NOT delete already-imported files

## Action: Status

Compare imported files with cache and remote:

```
Source: comfyui-custom-node-skills (type: skills)
  + comfyui-node-basics     — up-to-date
  ~ comfyui-node-inputs     — outdated (remote has changes)
  ? comfyui-node-frontend   — not imported
```

## Notes

- Files are copied, not symlinked
- `prefix` option avoids naming conflicts between sources
- Cache at `$HOME/.cc_skills_cache/` can be cleaned with `rm -rf`
- If a skill already exists from a different source, warn before overwriting
- All git operations use `--depth 1` for efficiency
- If `$ARGUMENTS` is empty or "help", show usage summary
