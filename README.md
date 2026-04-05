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

### Quick Start

1. **Register an external source** using the `/import-skills` command:
   ```
   /import-skills add https://github.com/example/my-skills.git --name my-skills --path commands
   ```

2. **Import skills** from registered sources:
   ```
   /import-skills import           # import from all sources
   /import-skills import my-skills # import from a specific source
   ```

3. **List available skills** from all registered sources:
   ```
   /import-skills list
   ```

4. **Check status** of imported skills:
   ```
   /import-skills status
   ```

### Manual Configuration

Edit `skills-registry.yaml` directly to add sources:

```yaml
sources:
  - name: pti-skills
    repo: https://github.com/example/pti-skills.git
    branch: main
    path: commands
    prefix: pti-           # optional: prefix imported filenames to avoid conflicts

  - name: team-tools
    repo: https://github.com/example/team-tools.git
    path: .claude/commands
    includes:              # optional: only import matching files
      - "debug-*.md"
      - "perf-*.md"
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `name` | (required) | Unique identifier for this source |
| `repo` | (required) | Git repository URL |
| `branch` | `main` | Branch to pull from |
| `path` | `commands` | Path to commands directory in the external repo |
| `includes` | all `*.md` | Glob patterns to include |
| `excludes` | none | Glob patterns to exclude |
| `prefix` | (empty) | Prefix added to imported filenames |

## Requirements

- Intel oneAPI toolkit (icpx, Level Zero)
- Intel GPU (Arc, Data Center GPU Max, etc.)
- unitrace built from [intel/pti-gpu](https://github.com/intel/pti-gpu)
