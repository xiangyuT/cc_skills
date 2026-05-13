#!/bin/bash
# PreToolUse hook: block `git push` to remotes not owned by xiangyuT.
# Works by reading the target remote URL and extracting the owner.
#
# Exit 0 = allow, exit 2 = block.

set -euo pipefail

OWNER_ALLOWLIST="xiangyuT"

INPUT="$(cat)"
CMD="$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

[ -z "$CMD" ] && exit 0
echo "$CMD" | grep -qE '(^|[[:space:];&|])git[[:space:]]+push([[:space:]]|$)' || exit 0

# Extract explicit remote arg if present: `git push <remote> ...`
REMOTE="$(echo "$CMD" | python3 -c '
import shlex, sys, re
line = sys.stdin.read()
# Find the first `git push` occurrence
m = re.search(r"git\s+push\b(.*)", line, re.S)
if not m:
    sys.exit(0)
rest = m.group(1)
try:
    toks = shlex.split(rest)
except Exception:
    sys.exit(0)
# skip flags
remote = ""
for t in toks:
    if t.startswith("-"):
        continue
    remote = t
    break
print(remote)
' || true)"

REMOTE="${REMOTE:-origin}"

# Resolve remote URL; requires cwd to be inside a git repo
URL="$(git remote get-url "$REMOTE" 2>/dev/null || true)"

if [ -z "$URL" ]; then
    # Could be push to a URL directly
    if [[ "$REMOTE" =~ ^(https://|git@|ssh://) ]]; then
        URL="$REMOTE"
    else
        # Not in a git repo or unknown remote — let git handle it
        exit 0
    fi
fi

# Extract owner
OWNER="$(echo "$URL" | sed -nE '
    s#^https?://[^/]+/([^/]+)/[^/]+(\.git)?.*#\1#p
    s#^git@[^:]+:([^/]+)/[^/]+(\.git)?.*#\1#p
    s#^ssh://git@[^/]+/([^/]+)/[^/]+(\.git)?.*#\1#p
' | head -1)"

if [ -z "$OWNER" ]; then
    exit 0
fi

if [ "$OWNER" = "$OWNER_ALLOWLIST" ]; then
    exit 0
fi

echo "BLOCKED: git push to $OWNER/... (remote '$REMOTE' -> $URL)" >&2
echo "Only pushes to ${OWNER_ALLOWLIST}/* are allowed from Claude Code." >&2
echo "To contribute to other orgs, push to your fork under ${OWNER_ALLOWLIST}/* and open a PR on github.com." >&2
exit 2
