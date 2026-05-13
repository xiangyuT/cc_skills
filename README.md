# cc_skills

Reusable Claude Code skills and hooks for Intel XPU / GPU development.

## Repo Structure

```
cc_skills/
├── commands/               # Slash command skills (flat .md)
├── skills/                 # In-repo skills (directories with SKILL.md)
├── hooks/                  # Hook scripts (.sh)
├── skills-registry.yaml    # External skill sources
└── README.md
```

## Usage

### Bootstrap a new workspace (Claude-driven)

In a fresh Claude Code session, tell Claude:

> "按 cc_skills 的 BOOTSTRAP.md 初始化这个 workspace"

or point it at the file explicitly: *"读一下
`$HOME/xiangyu/cc_skills/BOOTSTRAP.md` 然后按步骤装好"*.

Claude walks through the steps in [BOOTSTRAP.md](BOOTSTRAP.md):
clone/pull cc_skills → copy commands, skills, hook scripts →
ask which hooks to activate → run `/setup-hooks enable <name>`
accordingly → verify. The bootstrap asks before writing
`settings.local.json` and before pulling external skills.

### Ongoing sync

Once bootstrapped, use the slash commands:

```
/sync-skills pull       # pull latest files from cc_skills
/sync-skills push       # push new/modified files back to cc_skills
/setup-hooks status     # which hooks are active in this workspace
/import-skills import   # pull third-party skills registered in skills-registry.yaml
```

### Manual setup (fallback if scripts unavailable)

```bash
# Commands
mkdir -p .claude/commands
cp /path/to/cc_skills/commands/*.md .claude/commands/

# Skills (directory-based)
mkdir -p .claude/skills
cp -r /path/to/cc_skills/skills/* .claude/skills/

# Hooks (copy scripts; activation is separate)
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

## Available Skills

| Skill | Description |
|-------|-------------|
| `recent-works-kanban` | Maintain xiangyuT's personal GitHub Projects v2 kanban (vLLM / SGLang / Omni workstreams). Covers issue body style, commit-to-progress sync rules, upstream PR merge handling, deep-investigation artifact layout, and the gh/git write-scope safety rules. |

## Available Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `review-push-hook.sh` | PreToolUse (git push) | Scan push diff for performance data, block if found. |
| `gh-write-scope-hook.sh` | PreToolUse (Bash) | Block `gh` writes (issue/pr/release/api mutations) on repos outside `xiangyuT/*`. Reads on any repo still allowed. Pairs with `recent-works-kanban` skill. |
| `git-push-scope-hook.sh` | PreToolUse (Bash) | Block `git push` to remotes whose URL owner isn't `xiangyuT`. Pairs with `recent-works-kanban` skill. |
| `notify-teams.sh` | Stop / Notification | Send notifications to Microsoft Teams via Power Automate webhook. |

Use `/setup-hooks enable <hook>` to configure, or see [hooks/README.md](hooks/README.md) for manual setup.

## In-Repo Skills (methodology)

Skills under [`skills/`](skills/) distill design methodology from
Intel-XPU kernel work. **Kernel source and performance numbers are
intentionally excluded** — what's here is the *why* (patterns,
pitfalls, decision criteria) that transfers across projects.

See [skills/README.md](skills/README.md) for the catalog.

Import into your project via `/import-skills` (the registry section
below) or by copying the relevant subdir into your `.claude/skills/`.

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
