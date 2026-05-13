# Bootstrap a new Claude Code workspace from cc_skills

This file is a **Claude-driven** runbook. To set up a new workspace,
tell Claude:

> "读一下 `/home/arda/xiangyu/cc_skills/BOOTSTRAP.md` 然后按步骤给这个
> workspace 装好。"

or in a new session: *"按 cc_skills 的 BOOTSTRAP.md 初始化这个 workspace"*.

Claude will work through the steps below with your confirmation at the
gated checkpoints (§0 pre-flight, §4 hook activation).

---

## 0. Pre-flight checks (Claude should run these first)

```bash
# a. cc_skills repo path (resolve once; store as $CC_SKILLS)
for p in $HOME/cc_skills $HOME/xiangyu/cc_skills $(dirname "$PWD")/cc_skills; do
  [ -d "$p/.git" ] && CC_SKILLS="$p" && break
done
[ -z "$CC_SKILLS" ] && git clone https://github.com/xiangyuT/cc_skills.git $HOME/cc_skills && CC_SKILLS=$HOME/cc_skills

# b. pull latest
(cd "$CC_SKILLS" && git fetch origin && git status -sb)
```

Ask the user before `git pull` if the local repo is dirty or ahead of
origin. Otherwise `git pull --ff-only origin main`.

Record the resolved `$CC_SKILLS` path and pass it into every subsequent
`cp` as an absolute path — **do not** rely on shell cwd persistence
between Bash tool calls.

## 1. Directory skeleton

```bash
mkdir -p .claude/commands .claude/skills .claude/hooks
```

Only create directories that don't exist. Never overwrite an existing
`settings.local.json` — that's §4's job.

## 2. Commands (6 files, flat copy)

```bash
cp "$CC_SKILLS"/commands/*.md .claude/commands/
ls .claude/commands/
```

Expected files: `comfyui-benchmark.md`, `import-skills.md`,
`review-push.md`, `setup-hooks.md`, `sync-skills.md`, `unitrace.md`.

## 3. Skills (11 directories, including MEMORY.md + README.md)

```bash
cp -r "$CC_SKILLS"/skills/* .claude/skills/
ls .claude/skills/
```

Expected entries:
- `recent-works-kanban/` — kanban maintenance (triggers on 看板/kanban keywords)
- 10 `omni-*` + `sycl-esimd-wheel-build-linux/` — Intel XPU kernel methodology skills
- `MEMORY.md`, `README.md` — index/catalog files (harmless if copied; cleared by `/import-skills` if not wanted)

**Skills auto-trigger by description matching.** Nothing else needs to
be configured — they activate when the user's request matches the
`description:` frontmatter. Don't bother asking the user which to keep;
the unused ones cost nothing.

## 4. Hooks (copy scripts, then activate in settings)

### 4a. Copy hook scripts

```bash
cp "$CC_SKILLS"/hooks/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh
ls .claude/hooks/
```

Expected: `gh-write-scope-hook.sh`, `git-push-scope-hook.sh`,
`notify-teams.sh`, `review-push-hook.sh`.

### 4b. Activation — ASK THE USER before writing settings.local.json

Copying a hook script doesn't activate it. Activation = an entry in
`.claude/settings.local.json`. Ask the user which hooks to enable:

```
Available hooks (scripts copied, not yet active):

  [recommended defaults for kanban/cc workflow]
  - kanban-scope     Block gh/git writes outside xiangyuT/* (pairs with
                     recent-works-kanban skill)
  - review-push      Block git push containing perf data

  [optional — need Teams webhook URL]
  - teams            Stop + Notification → Teams (recommended minimal)
  - teams-full       + PreToolUse + PostToolUse (verbose)

Which do you want enabled? [default: kanban-scope + review-push]
```

Then run `/setup-hooks enable <name>` **once per selected hook**.
`setup-hooks` edits `.claude/settings.local.json` safely (preserves
other fields, idempotent).

- For `kanban-scope` → run `/setup-hooks enable gh-write-scope` and
  `/setup-hooks enable git-push-scope`.
- For `teams*` → verify `$TEAMS_WEBHOOK_URL` is exported first; if not,
  show the export snippet and ask the user to set it, then continue.

## 5. External skills (optional, ask first)

`skills-registry.yaml` has pre-configured sources (currently
`comfyui-custom-node-skills`). These are **not** pulled by default —
they're only relevant to ComfyUI custom-node development workspaces.

Ask:
> "要拉外部 skill 源（目前注册的：comfyui-custom-node-skills，ComfyUI 自定义节点开发 9 个 skill）吗？"

If yes: `/import-skills import`. Otherwise skip.

## 6. Verification

```bash
ls -la .claude/commands .claude/skills .claude/hooks
test -f .claude/settings.local.json && echo "settings present" && jq '.hooks | keys' .claude/settings.local.json
```

Then tell the user what's active:

```
Workspace bootstrapped. Installed:
  commands: 6 (unitrace, comfyui-benchmark, review-push, sync-skills, setup-hooks, import-skills)
  skills:   11 (recent-works-kanban + 10 omni kernel methodology)
  hooks:    <N> active (<names>)

Next steps:
  - Test kanban access: ask "列出看板" → should trigger recent-works-kanban skill
  - Test write-scope:   /setup-hooks test gh-write-scope
```

---

## Staying in sync later

### Pull updates

```
/sync-skills pull
```

Rewalks §2–§4a (cp from cc_skills to `.claude/`). Does **not** modify
`settings.local.json` — if a new hook type was added upstream, the
script is copied but you still need to `/setup-hooks enable <name>`.

### Push local changes back

```
/sync-skills push
```

Pushes new/modified commands or skill directories from this workspace
back to the cc_skills repo. Hooks get pushed the same way.

### Check what's outdated

```
/sync-skills list        # show what's in the cc_skills repo
/setup-hooks status      # show which hooks are active in this workspace
```

---

## Resource relationship cheat sheet

| Resource | Where it lives in cc_skills | Where it lands | How it's used |
|---|---|---|---|
| Slash commands | `commands/*.md` | `.claude/commands/*.md` | User types `/name args` |
| Skills | `skills/<name>/SKILL.md` | `.claude/skills/<name>/` | Auto-triggered by description match |
| Hook scripts | `hooks/*.sh` | `.claude/hooks/*.sh` | Referenced by settings.local.json |
| Hook activation | — | `.claude/settings.local.json` → `hooks.*` | `/setup-hooks enable <name>` writes here |
| External sources | `skills-registry.yaml` | (applied by `/import-skills import`) | Pulls third-party skill repos |

Three slash commands for maintenance:
- **`/sync-skills`** — cc_skills ↔ workspace (commands/skills/hooks files)
- **`/setup-hooks`** — activate/deactivate hooks in settings.local.json
- **`/import-skills`** — pull third-party skills from external git repos (registered in skills-registry.yaml)
