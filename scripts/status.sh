#!/usr/bin/env bash
# Show status of all subtrees and meta-repo
#
# Shows:
# - Local uncommitted changes
# - Commits ahead/behind meta-repo remote
# - Whether subtrees have unpushed commits (requires split, can be slow first time)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Show status of the workspace, subtrees, and their upstreams.

Options:
  --quick       Skip upstream comparison (faster, less info)
  --fetch       Fetch from all remotes before showing status
  --subtree=X   Only show status for specified subtree
  -h, --help    Show this help

Status indicators:
  [M] Modified   - Has uncommitted changes
  [A] Ahead      - Has commits not pushed to meta-repo remote
  [B] Behind     - Meta-repo remote has commits not pulled
  [U] Upstream   - Has commits not pushed to subtree upstream
EOF
    exit 0
}

QUICK=false
DO_FETCH=false
SINGLE_SUBTREE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick) QUICK=true; shift ;;
        --fetch) DO_FETCH=true; shift ;;
        --subtree=*) SINGLE_SUBTREE="${1#*=}"; shift ;;
        -h|--help) usage ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

check_workspace
cd_workspace

# Fetch if requested
if [[ "$DO_FETCH" == "true" ]]; then
    info "Fetching from remotes..."
    git fetch --all --quiet 2>/dev/null || true
    echo
fi

echo "=========================================="
echo " Workspace Status"
echo "=========================================="
echo

# Meta-repo status
info "Meta-repo:"

# Check for uncommitted changes
if git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "  Working tree: clean"
else
    echo -e "  Working tree: ${YELLOW}modified${NC}"
    git status --short | head -10 | sed 's/^/    /'
    mod_count=$(git status --short | wc -l)
    if [[ $mod_count -gt 10 ]]; then
        echo "    ... and $((mod_count - 10)) more"
    fi
fi

# Check ahead/behind
current_branch=$(git branch --show-current)
if git rev-parse --abbrev-ref "@{upstream}" &>/dev/null; then
    ahead=$(git rev-list --count "@{upstream}..HEAD" 2>/dev/null || echo "?")
    behind=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo "?")

    if [[ "$ahead" == "0" && "$behind" == "0" ]]; then
        echo "  Remote: up to date"
    else
        [[ "$ahead" != "0" ]] && echo -e "  Remote: ${GREEN}$ahead ahead${NC}"
        [[ "$behind" != "0" ]] && echo -e "  Remote: ${YELLOW}$behind behind${NC}"
    fi
else
    echo -e "  Remote: ${YELLOW}no upstream configured${NC}"
fi

echo

# Subtree status
info "Subtrees:"
echo

subtree_count=0
while IFS='|' read -r path remote branch install; do
    [[ -z "$path" ]] && continue

    # If single subtree specified, skip others
    if [[ -n "$SINGLE_SUBTREE" && "$path" != "$SINGLE_SUBTREE" ]]; then
        continue
    fi

    ((subtree_count++)) || true

    echo -e "  ${BLUE}$path${NC} ($remote @ $branch)"

    if ! [[ -d "$path" ]]; then
        echo -e "    ${RED}Directory missing!${NC}"
        echo
        continue
    fi

    # Check for local changes in subtree
    subtree_changes=$(git status --short -- "$path" | wc -l)
    if [[ $subtree_changes -gt 0 ]]; then
        echo -e "    Local changes: ${YELLOW}$subtree_changes files modified${NC}"
    else
        echo "    Local changes: none"
    fi

    # Check for commits touching this subtree since... when?
    # This is tricky - we look at commits that touch the subtree path
    recent_commits=$(git log --oneline -5 -- "$path" 2>/dev/null | wc -l)
    if [[ $recent_commits -gt 0 ]]; then
        last_commit=$(git log --oneline -1 -- "$path" 2>/dev/null)
        echo "    Last commit: $last_commit"
    fi

    # Upstream comparison (slow - requires split)
    if [[ "$QUICK" == "false" ]]; then
        # Try to fetch the upstream to compare
        # We use a temporary remote name to avoid polluting the remote list
        temp_remote="__temp_${path//\//_}"

        # Add temporary remote if it doesn't exist
        if ! git remote get-url "$temp_remote" &>/dev/null; then
            git remote add "$temp_remote" "$remote" 2>/dev/null || true
        fi

        # Fetch quietly
        if git fetch "$temp_remote" "$branch" --quiet 2>/dev/null; then
            upstream_ref="$temp_remote/$branch"

            # Compare tree hashes: upstream's root tree vs our subtree's tree
            # If they match, the content is identical
            upstream_tree=$(git rev-parse "$upstream_ref^{tree}" 2>/dev/null) || true
            local_tree=$(git rev-parse "HEAD:$path" 2>/dev/null) || true

            if [[ -n "$upstream_tree" && -n "$local_tree" ]]; then
                if [[ "$upstream_tree" == "$local_tree" ]]; then
                    echo -e "    Upstream: ${GREEN}up to date${NC}"
                else
                    echo -e "    Upstream: ${YELLOW}differs from $branch${NC}"
                fi
            else
                echo -e "    Upstream: ${YELLOW}could not compare${NC}"
            fi
        else
            echo -e "    Upstream: ${YELLOW}could not fetch${NC}"
        fi

        # Clean up temp remote
        git remote remove "$temp_remote" 2>/dev/null || true
    else
        echo "    Upstream: (skipped - use without --quick to check)"
    fi

    echo
done < <(get_subtrees)

if [[ $subtree_count -eq 0 ]]; then
    echo "  (no subtrees configured)"
    echo
    echo "  Add subtrees with:"
    echo "    ./scripts/add_subtree.sh <path> <remote> [branch]"
    echo
fi

echo "=========================================="
