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
| `/comfyui-benchmark` | Run ComfyUI e2e benchmark workflows and collect performance data. |
| `/sync-skills` | Sync skills between local project and this repo (pull/push). |
| `/import-skills` | Import and sync skills from external repositories defined in `skills-registry.yaml`. |

## Integrating Skills from Other Repositories

You can import skills from any external Git repository by registering it in `skills-registry.yaml`.
Two layout types are supported:

| Type | Repo layout | Imported to | Claude Code usage |
|------|-------------|-------------|-------------------|
| `commands` | flat `.md` files (`commands/foo.md`) | `.claude/commands/` | `/foo` slash command |
| `skills` | directories with `SKILL.md` (`skills/foo/SKILL.md`) | `.claude/skills/` | Auto-loaded context |

### Quick Start

1. **Register an external source** using the `/import-skills` command:
   ```
   /import-skills add https://github.com/jtydhr88/comfyui-custom-node-skills.git
   ```

2. **Import skills** from registered sources:
   ```
   /import-skills import                          # import from all sources
   /import-skills import comfyui-custom-node-skills  # import from a specific source
   ```

3. **List available skills** from all registered sources:
   ```
   /import-skills list
   ```

4. **Check status** of imported skills:
   ```
   /import-skills status
   ```

### Pre-configured Example

The registry ships with [comfyui-custom-node-skills](https://github.com/jtydhr88/comfyui-custom-node-skills) pre-configured.
This source provides 9 Claude Code skills for ComfyUI custom node development:

| Skill | Description |
|-------|-------------|
| `comfyui-node-basics` | V3 node structure, `io.Schema`, `ComfyExtension` registration |
| `comfyui-node-inputs` | INT, FLOAT, STRING, BOOLEAN, COMBO, hidden/optional/lazy inputs |
| `comfyui-node-outputs` | `NodeOutput`, preview helpers, saving files |
| `comfyui-node-datatypes` | IMAGE, LATENT, MASK, MODEL, CLIP, VAE, AUDIO, custom types |
| `comfyui-node-advanced` | MatchType, Autogrow, DynamicCombo, `GraphBuilder`, async |
| `comfyui-node-lifecycle` | `fingerprint_inputs`, `validate_inputs`, execution order |
| `comfyui-node-frontend` | JS hooks, sidebar tabs, commands, settings, toasts, dialogs |
| `comfyui-node-migration` | Converting V1 nodes to V3 |
| `comfyui-node-packaging` | Directory layout, `pyproject.toml`, registry publishing |

Run `/import-skills import comfyui-custom-node-skills` to install them.

### Manual Configuration

Edit `skills-registry.yaml` directly to add sources:

```yaml
sources:
  # Skills layout (directories with SKILL.md)
  - name: comfyui-custom-node-skills
    repo: https://github.com/jtydhr88/comfyui-custom-node-skills.git
    branch: main
    type: skills
    path: skills

  # Commands layout (flat .md files)
  - name: team-commands
    repo: https://github.com/example/team-commands.git
    type: commands
    path: commands
    prefix: team-           # optional: prefix imported filenames to avoid conflicts
    includes:               # optional: only import matching files
      - "debug-*.md"
      - "perf-*.md"
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `name` | (required) | Unique identifier for this source |
| `repo` | (required) | Git repository URL |
| `branch` | `main` | Branch to pull from |
| `type` | `commands` | Layout type: `commands` (flat .md) or `skills` (dirs with SKILL.md) |
| `path` | `commands` or `skills` | Path inside the external repo |
| `includes` | all | Glob patterns to include |
| `excludes` | none | Glob patterns to exclude |
| `prefix` | (empty) | Prefix added to imported filenames/directories |

## Requirements

- Intel oneAPI toolkit (icpx, Level Zero)
- Intel GPU (Arc, Data Center GPU Max, etc.)
- unitrace built from [intel/pti-gpu](https://github.com/intel/pti-gpu)
