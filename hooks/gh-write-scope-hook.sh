#!/bin/bash
# PreToolUse hook: block gh write operations on repos outside xiangyuT/*
#
# Rules:
#  - xiangyuT/* : allow
#  - other owner : block write verbs (issue/pr/repo/release/label/workflow/secret/cache/ruleset)
#  - gh api : only block REST endpoints on /repos/<owner>/<name> with mutating methods
#  - gh api graphql : allowed (can't statically parse target; user Projects live here)
#  - gh auth / config / alias / completion / gist / codespace : allowed (not repo-scoped)
#
# Input: JSON on stdin from Claude Code with .tool_input.command
# Exit 0 = allow, exit 2 = block (stderr shown to model)

set -euo pipefail

OWNER_ALLOWLIST="xiangyuT"

INPUT="$(cat)"
CMD="$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

[ -z "$CMD" ] && exit 0

# Quick filter: only care about lines containing "gh "
echo "$CMD" | grep -qE '(^|[;&|`$(/[:space:]])gh[[:space:]]' || exit 0

block() {
    echo "BLOCKED: $1" >&2
    echo "Only writes to ${OWNER_ALLOWLIST}/* are allowed from Claude Code." >&2
    echo "To push work to other orgs, fork to ${OWNER_ALLOWLIST}/* and PR from there, or run the command yourself outside Claude Code." >&2
    exit 2
}

# Extract all gh invocations on separate lines (handles ; && || | chains, newlines)
# Note: this is a best-effort parse, not a full shell parser.
while IFS= read -r line; do
    # trim
    line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" =~ ^gh[[:space:]] ]] || continue

    # Tokenize with python shlex for safe quote handling
    TOKENS_JSON="$(python3 -c '
import shlex, sys, json
try:
    print(json.dumps(shlex.split(sys.argv[1])))
except Exception:
    print("[]")
' "$line")"
    # tokens as bash array
    mapfile -t TOK < <(python3 -c 'import json,sys; [print(t) for t in json.loads(sys.argv[1])]' "$TOKENS_JSON")

    [ "${#TOK[@]}" -lt 2 ] && continue
    SUB="${TOK[1]}"
    ACTION="${TOK[2]:-}"

    # Safe subcommands (no repo-scoped writes)
    case "$SUB" in
        auth|config|alias|completion|extension|status|help|--help|-h|--version)
            continue ;;
        gist|codespace|ssh-key|gpg-key)
            continue ;;
    esac

    # Read-only verbs -> allow
    case "$ACTION" in
        list|view|status|diff|checkout|ls|ready)
            continue ;;
    esac

    # Identify write verbs we care about
    IS_WRITE=0
    case "$SUB" in
        issue|pr)
            case "$ACTION" in
                create|edit|close|reopen|delete|comment|merge|review|ready|lock|unlock|pin|unpin|transfer|develop)
                    IS_WRITE=1 ;;
            esac ;;
        repo)
            case "$ACTION" in
                create|edit|delete|archive|unarchive|rename|fork|sync|deploy-key|clone)
                    # clone/fork/sync target xiangyuT acceptable, but fork creates repo under user by default - allow
                    [ "$ACTION" = "clone" ] && continue
                    [ "$ACTION" = "fork" ] && continue
                    [ "$ACTION" = "sync" ] && continue
                    IS_WRITE=1 ;;
            esac ;;
        release|label|workflow|cache|ruleset|secret|variable)
            case "$ACTION" in
                create|edit|delete|update|upload|download|run|enable|disable|rerun|cancel|set|remove)
                    # download/run/rerun/cancel on workflow/release touch others' actions; treat as write
                    IS_WRITE=1 ;;
            esac ;;
        project)
            # Project writes always target xiangyuT in our usage; still check --owner if present
            case "$ACTION" in
                create|edit|delete|close|copy|field-create|field-delete|item-add|item-archive|item-create|item-delete|item-edit|mark-template|unmark-template|link|unlink)
                    IS_WRITE=1 ;;
                *)
                    continue ;;
            esac ;;
        api)
            # Only block if -X POST/PATCH/DELETE/PUT *and* path contains /repos/<owner>/<name>
            METHOD=""
            ENDPOINT=""
            i=2
            while [ $i -lt ${#TOK[@]} ]; do
                t="${TOK[$i]}"
                case "$t" in
                    -X|--method)
                        METHOD="${TOK[$((i+1))]:-}"
                        i=$((i+2)); continue ;;
                    -XPOST|-XPATCH|-XPUT|-XDELETE)
                        METHOD="${t#-X}"
                        i=$((i+1)); continue ;;
                    graphql)
                        ENDPOINT="graphql"
                        break ;;
                    -H|-F|-f|--field|--raw-field|--header|-q|--jq|-t|--template|--hostname|--cache|--input)
                        # flags that consume a value
                        i=$((i+2)); continue ;;
                    -*)
                        i=$((i+1)); continue ;;
                    *)
                        [ -z "$ENDPOINT" ] && ENDPOINT="$t"
                        i=$((i+1)); continue ;;
                esac
            done
            [ "$ENDPOINT" = "graphql" ] && continue
            # Default method is GET; only check if mutating
            case "${METHOD^^}" in
                POST|PATCH|PUT|DELETE) : ;;
                *) continue ;;
            esac
            # Extract owner from endpoint like repos/<owner>/<name>/...
            OWNER_FROM_API="$(echo "$ENDPOINT" | sed -nE 's#^/?repos/([^/]+)/[^/]+.*#\1#p')"
            if [ -z "$OWNER_FROM_API" ]; then
                # Not a /repos/ endpoint (could be /user, /orgs/... reads etc); allow
                continue
            fi
            if [ "$OWNER_FROM_API" = "$OWNER_ALLOWLIST" ]; then
                continue
            fi
            block "gh api $METHOD on /repos/$OWNER_FROM_API/... (only $OWNER_ALLOWLIST/* allowed)"
            ;;
        *)
            continue ;;
    esac

    [ "$IS_WRITE" -eq 0 ] && continue

    # For repo-scoped writes, find --repo <owner>/<name> or URL owner
    REPO_OWNER=""
    for ((i=2; i<${#TOK[@]}; i++)); do
        t="${TOK[$i]}"
        case "$t" in
            -R|--repo)
                NXT="${TOK[$((i+1))]:-}"
                REPO_OWNER="$(echo "$NXT" | sed -nE 's#^(https?://github\.com/)?([^/]+)/[^/]+.*#\2#p')"
                ;;
            --owner)
                REPO_OWNER="${TOK[$((i+1))]:-}" ;;
            https://github.com/*)
                REPO_OWNER="$(echo "$t" | sed -nE 's#^https?://github\.com/([^/]+)/.*#\1#p')"
                ;;
        esac
    done

    # If no explicit --repo/--owner and subcommand is issue/pr/release/label/...
    # gh infers from cwd git remote. Leave that to git-push-scope or trust cwd.
    if [ -z "$REPO_OWNER" ]; then
        # project writes default --owner to @me (xiangyuT); allow
        [ "$SUB" = "project" ] && continue
        # Otherwise we can't tell; be conservative and allow (cwd-based).
        # git-push-scope-hook covers push-side risk.
        continue
    fi

    if [ "$REPO_OWNER" = "$OWNER_ALLOWLIST" ]; then
        continue
    fi

    block "gh $SUB $ACTION targeting $REPO_OWNER/... (only $OWNER_ALLOWLIST/* allowed)"

done <<< "$(echo "$CMD" | tr ';&|`' '\n')"

exit 0
