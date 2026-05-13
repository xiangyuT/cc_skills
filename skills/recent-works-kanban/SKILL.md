---
name: recent-works-kanban
description: Maintain xiangyuT's personal GitHub Projects v2 kanban at github.com/users/xiangyuT/projects/3 (backed by xiangyuT/recent_works). Use when the user asks to update, sync, add issues to, or reorganize "the kanban" / "看板" / "progress board" / their project tracking, or when creating/modifying issues that track the user's personal work on vLLM / SGLang / Omni / llm-scaler and similar projects. Also defines the gh/git write-scope safety rules the assistant must follow.
---

# Recent Works Kanban Maintenance

Personal progress kanban for xiangyuT's work across vLLM / SGLang / Omni (Intel LLM Scaler ecosystem).
**This is a personal tracker, not a team board** — only record work the user personally drives.

## 1. Kanban identifiers

| Item | Value |
|---|---|
| URL | https://github.com/users/xiangyuT/projects/3 |
| Owner | `xiangyuT` (personal account, private) |
| Project number | `3` |
| Project ID | `PVT_kwHOBoEYb84BXT-m` |
| Backing repo | `xiangyuT/recent_works` |

## 2. Custom fields

| Field | Type | Field ID | Options |
|---|---|---|---|
| Status | SINGLE_SELECT (built-in) | `PVTSSF_lAHOBoEYb84BXT-mzhShowU` | Todo (`3b4a0829`) / In Progress (`e08f5805`) / Validating (`2b1b2cdd`) / Pending (`2ad91140`) / Done (`78e38414`) |
| Priority | SINGLE_SELECT | `PVTSSF_lAHOBoEYb84BXT-mzhSho28` | P0 (`28ca0811`) / P1 (`3bae3a62`) / P2 (`74de61b8`) / P3 (`9c27d49c`) |
| Area | SINGLE_SELECT | `PVTSSF_lAHOBoEYb84BXT-mzhSho9c` | vLLM (`a865ab60`) / SGLang (`aa03fafb`) / Omni (`24c87ab0`) |
| Start date | DATE | `PVTF_lAHOBoEYb84BXT-mzhShtxQ` | — |
| Target date | DATE | `PVTF_lAHOBoEYb84BXT-mzhShu1Q` | — |

These IDs are for the current project; re-fetch via `gh api graphql` if they ever break.

## 3. Milestones (short names)

Use short names when renaming or referencing:
- `SGLang: Qwen3.5 PTL GA` — SGLang main line stage goal
- `omni-b8-dev` — Omni b8 development milestone
- `omni-b7-win-zip` — Omni b7 Windows portable zip packaging

Create new milestones with the same `{area}-{version}-{purpose}` shape to keep them table-friendly.

## 4. Core rules

### 4.1 Scope: only the user's own work
- Do **not** auto-archive releases / features you see in `llm-scaler` README or Releases.md — many of those are coworkers' work.
- Before creating an issue based on a PR or release, verify the user personally drives it (check PR author, ask if unsure).
- The llm-scaler repo README/Releases.md is **background context only**, never a data source for kanban population.

### 4.1.1 Area field — fixed set, don't invent
- Only three valid Area values: **vLLM / SGLang / Omni**. These are the three workstreams the user tracks.
- Do **not** invent new Area options (e.g. ComfyUI / PyTorch-XPU / SYCL) — sub-topics like ComfyUI custom nodes belong under Omni; PyTorch / SYCL work belongs under whichever workstream it supports.
- If a piece of work genuinely doesn't fit, ask the user before adding a new Area option (and remember that adding options wipes existing field values — see §6.3).

### 4.2 Status conventions
- `Todo`: scheduled but not started. Leave Start/Target dates empty.
- `In Progress`: actively working. Fill `Start date` with the actual start date.
- `Validating`: code/work is done on our side; teammate (or downstream team) is validating. Keep `Start date`; leave `Target date` empty.
- `Pending`: blocked / waiting on review, resources, upstream decision, etc. Keep `Start date`; leave `Target date` empty.
- `Done`: finished. Fill `Target date` with the completion date.
- The project has a built-in workflow that auto-closes the underlying issue when Status → Done.

### 4.3 Issue body template and style
```
## Summary
<one-paragraph what/why>

## (optional) Root cause / Approach
...

## (optional) Upstream PR
- intel/<repo>#<num>
- sgl-project/sglang#<num>  (for SGLD feature work)

## (optional) Progress
- [x] <done sub-task> — short evidence (ea6d058)
- [ ] <pending sub-task>

## Area
<one of the Area field options>

## Milestone
<short milestone name if applicable>
```

**Writing style conventions:**
- Reference commits with short SHA in parens at end of line: `... (ea6d058)`. Multiple related commits: `(ea6d058, 56e3fd2)`.
- Reference PRs with owner-prefix: `intel/llm-scaler#404`, `sgl-project/sglang#18764`. Same-repo refs can use bare `#N`.
- Perf numbers always as `before → after (Nx)` or `before → after (-P%)`: e.g. `TTFT 2121ms → 91ms (23×)`, `decode 31 tok/s → 37 tok/s (+18%)`.
- Sub-task checklists over prose paragraphs — renders well and is easy to update incrementally.
- Don't paste whole investigation docs into issue bodies; keep issue body to triaged findings + checkboxes. See §4.7.

### 4.4 Default priority heuristics (when user doesn't specify)
- **P0** — hard blocker on the user's main workstream (e.g. "no validated SGL docker image on PTL" blocking Qwen3.5 bring-up), or a release-critical bug the user owns
- **P1** — customer-facing b8/release item on the main path (e.g. ComfyUI Manager fails → blocks turnkey install UX for most customers), or a tracked feature the milestone depends on
- **P2** — standalone feature or investigation that doesn't block a release (e.g. "support comfyui-nunchaku-xpu")
- **P3** — nice-to-have / exploratory
- When unsure, pick P2 and state the reasoning in the response so the user can redirect.

### 4.5 Parent/child tracking issues
- Use a parent "tracking" issue for multi-step workstreams (see #3 SGLang Qwen3.5).
- Child issues link back via `Parent: #<n>` in the body.
- Parent body contains a checklist `- [ ] #<n> <title>` — GitHub renders these with live status. Update the checkbox when the child's Status transitions.

### 4.6 Syncing progress from upstream commits
When the user asks "根据 branch 上的 commit 更新 issue" or similar:

```bash
# List recent commits on a branch (upstream or user's fork)
gh api repos/<owner>/<repo>/commits?sha=<branch>\&per_page=30 \
  --jq '.[] | "\(.sha[0:7]) \(.commit.author.date | .[0:10]) \(.commit.author.name) | \(.commit.message | split("\n")[0])"'

# For commits with rich message bodies (perf numbers, validation data):
gh api repos/<owner>/<repo>/commits/<sha> --jq '.commit.message'
```

**What to write into `## Progress`:**
- ✅ Only things the code itself proves: "ESIMD kernel landed", "fallback added", "fix for X symptom with Y before/after metric"
- ❌ Do NOT infer "feature enabled" from `Enable X` / `Support X` / `Add X` commit messages — code presence ≠ working config. See memory `feedback_commit_interpretation.md`. Confirm working-config state with the user before writing "X is enabled".
- For env-gated features, say `env-gated <FLAG>, default OFF` — never "X enabled"
- Cite SHA at end of line

### 4.7 Upstream PR merge → kanban sync
When upstream PRs tied to kanban issues get merged (or state changes):

```bash
# Enumerate recent merged PRs by the user on a repo
gh pr list --repo <org>/<repo> --author xiangyuT --state merged \
  --limit 20 --json number,title,mergedAt,state \
  --jq '.[] | "#\(.number) [\(.mergedAt // "OPEN")] \(.state) \(.title)"'
```

Cross-reference with `gh issue view <kanban-N> --json body` to find the issue referencing each PR.

**Merge ≠ Done automatically.** Ask the user whether each merged-upstream issue should:
- → **Done** (user considers merge = feature complete)
- → **Validating** (merged but awaiting downstream docker image / customer validation)
- → stay **In Progress** (more work required in same issue)

Default suggestion depends on issue type: a one-shot fix PR merge → Done is usually right; a multi-step feature's first PR → Validating or In Progress.

### 4.8 Deep-investigation issues (surveys, feature triage)
For issues that produce research output (example: #14 SGLD feature survey):

- **Full report lives as a local markdown file** in workspace root (e.g. `sgld_p0_p1_deep_dive.md`). Don't paste multi-thousand-word reports into issue bodies.
- **Issue body references the local doc**: `Investigation docs (local): <filename>.md`, then lists triaged findings (P0 / P1 / P2 / Skip) as checkboxes with 1-3 line hooks each.
- **Raw materials** (PR diffs, HEAD snapshots, benchmark JSON) go under `pr_investigation/` or similar topic directory, listed in the issue body for future reference.
- When the report updates, update both the local file AND the relevant bullets in the issue body — never just one.
- Each checkbox entry carries enough context to be actionable standalone (PR number + 1-line what-it-does + porting note + CLI name if relevant). Future triage should not need to re-read the full report.

## 5. Write-scope safety rules (MUST follow)

**Claude Code is restricted to writes on `xiangyuT/*` only.** Enforced by two PreToolUse hooks:
- `.claude/hooks/gh-write-scope-hook.sh` — blocks `gh issue/pr/repo/release/label/workflow/secret` writes and `gh api -X POST/PATCH/PUT/DELETE` on `/repos/<non-xiangyuT>/...`
- `.claude/hooks/git-push-scope-hook.sh` — blocks `git push` to remotes not owned by `xiangyuT`

### What's allowed
- All reads on any repo (`gh issue list`, `gh pr view`, `gh api <GET>`, `gh repo clone`, etc.)
- `gh api graphql` (kanban operations depend on it; target is always the user's own project in practice)
- `gh project *` (kanban operations, default `--owner @me = xiangyuT`)
- `gh auth`, `gh config`, `gh repo fork/clone/sync`

### What's blocked (will hit exit 2)
- Any `gh issue/pr edit/create/close/comment` targeting a non-xiangyuT repo
- `gh api` mutations against `/repos/<other-owner>/...`
- `git push` to remotes whose URL owner isn't `xiangyuT`

### Contribution workflow for org repos (e.g. intel/llm-scaler)
- Fork to `xiangyuT/<repo>`
- Commit and push to the fork (allowed)
- Open the PR on github.com's web UI or via `gh pr create --repo intel/<repo> --head xiangyuT:<branch>` (read on target + push on fork → works without tripping the hook)
- **Don't** try to `gh pr edit` or `gh issue comment` against `intel/*` from Claude Code — run such commands outside Claude Code if needed.

## 6. Common operation recipes

### 6.1 Create a new issue and add to kanban
```bash
# 1. Create issue
gh issue create --repo xiangyuT/recent_works \
  --title "[<Area>] <short title>" \
  --body "$(cat <<'EOF'
## Summary
...
## Area
<Area>
## Milestone
<milestone>
EOF
)" \
  --milestone "<milestone>"   # optional

# 2. Add to project; capture item ID
ITEM=$(gh project item-add 3 --owner xiangyuT \
  --url https://github.com/xiangyuT/recent_works/issues/<N> \
  --format json --jq .id)

# 3. Set fields (use IDs from section 2)
gh project item-edit --project-id PVT_kwHOBoEYb84BXT-m --id "$ITEM" \
  --field-id PVTSSF_lAHOBoEYb84BXT-mzhShowU \
  --single-select-option-id <Status option ID>
# repeat for Area, Priority
```

### 6.2 Set a DATE field
```bash
gh project item-edit --project-id PVT_kwHOBoEYb84BXT-m --id "$ITEM" \
  --field-id PVTF_lAHOBoEYb84BXT-mzhShtxQ --date 2026-05-11
```

### 6.3 Status transitions
- Todo → In Progress: set Status, fill `Start date` = today
- In Progress → Validating / Pending: set Status only (keep `Start date`)
- Validating / Pending → In Progress: set Status only
- In Progress / Validating → Done: set Status, fill `Target date` = today (the auto-workflow will close the issue)

**Important caveat:** `updateProjectV2Field` on any single-select field (Status / Priority / Area) **re-generates all option IDs**, which silently clears every item's current value for that field. Before adding/renaming options, snapshot the existing item→option mapping, then re-apply after the mutation. Also update the IDs in §2 of this skill.

### 6.4 Re-fetch field / option IDs (if this doc drifts)
```bash
gh api graphql -f query='
query {
  node(id: "PVT_kwHOBoEYb84BXT-m") {
    ... on ProjectV2 {
      fields(first: 30) {
        nodes {
          ... on ProjectV2Field { id name dataType }
          ... on ProjectV2SingleSelectField { id name options { id name } }
        }
      }
    }
  }
}'
```

### 6.5 List all items (for a status report)
```bash
gh project item-list 3 --owner xiangyuT --format json --limit 50 \
  | python3 -c "import json,sys; [print(f\"#{i['content'].get('number')} {i['content'].get('title')}\") for i in json.load(sys.stdin)['items']]"
```

## 7. Limitations (know these before promising things)

- **Projects v2 views cannot be created/modified via API.** Layout / group-by / sort / visible columns must be configured in the web UI.
- **Milestone rename is safe**; issue-milestone links are by numeric ID, not title.
- **Fine-grained PAT does not support user-level Projects v2 writes** (GitHub limitation). Token is classic; scope is limited by Claude Code hooks instead.
- **Hook only binds the assistant's bash executions.** Commands run directly in the user's terminal bypass the hook (that's intentional — escape hatch).

## 8. Ask before doing

- Creating more than ~3 issues at once → confirm titles/scope first
- Bulk status changes → summarize what you'll change, get explicit OK
- Renaming milestones → show before/after, get OK
- Creating issues from upstream PRs when author is not the user → always ask
