#!/usr/bin/env bash
# Push all subtrees to their upstreams, then push meta-repo
#
# Uses split --rejoin for performance on subsequent pushes

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Tell pre-push hook to skip its messaging (we handle our own)
export WORKSPACE_PUSH_ALL=1

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Push changes to all subtree upstreams and the meta-repo.

Options:
  --dry-run     Show what would be pushed without pushing
  --meta-only   Only push the meta-repo, skip subtrees
  --subtree=X   Only push the specified subtree
  -h, --help    Show this help

This script uses 'git subtree split --rejoin' for efficient incremental pushes.
EOF
    exit 0
}

DRY_RUN=false
META_ONLY=false
SINGLE_SUBTREE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --meta-only) META_ONLY=true; shift ;;
        --subtree=*) SINGLE_SUBTREE="${1#*=}"; shift ;;
        -h|--help) usage ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

check_workspace
cd_workspace

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    warn "You have uncommitted changes. Commit or stash them first."
    git status --short
    exit 1
fi

push_subtree() {
    local path="$1"
    local remote="$2"
    local branch="$3"

    info "Processing subtree: $path -> $remote ($branch)"

    # Check if there are any commits for this subtree
    if ! git log --oneline -1 -- "$path" &>/dev/null; then
        warn "No commits found for $path, skipping"
        return 0
    fi

    # Fast check: compare tree hashes to see if there's anything to push
    # This avoids the expensive split operation when trees are identical
    info "  Checking for changes..."

    # Fetch upstream quietly to compare
    if git fetch "$remote" "$branch" --quiet 2>/dev/null; then
        local upstream_tree local_tree
        upstream_tree=$(git rev-parse "FETCH_HEAD^{tree}" 2>/dev/null) || true
        local_tree=$(git rev-parse "HEAD:$path" 2>/dev/null) || true

        if [[ -n "$upstream_tree" && -n "$local_tree" && "$upstream_tree" == "$local_tree" ]]; then
            info "  Already up to date with upstream (skipping expensive split)"
            return 0
        fi

        # Check if upstream has diverged (would cause non-fast-forward push)
        # If FETCH_HEAD is not an ancestor of HEAD, upstream has commits we don't have
        if ! git merge-base --is-ancestor FETCH_HEAD HEAD 2>/dev/null; then
            warn "  Upstream has diverged! Push would fail (non-fast-forward)"
            warn "  To fix: git subtree pull --prefix=$path $remote $branch"
            warn "  Skipping expensive split"
            return 1
        fi
    fi

    # Create a temporary branch name for the split
    local split_branch="split-${path//\//-}"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would split and push $path to $remote $branch"
        return 0
    fi

    # Check if there's a rejoin marker for this subtree
    if ! git log --oneline --grep="Split '$path/'" -1 | grep -q .; then
        info "  Note: No rejoin marker yet - first split may be slow"
    fi

    # Split with rejoin for performance
    # This creates/updates a branch with just the subtree commits
    info "  Splitting commits (with --rejoin for future performance)..."
    split_output=$(git subtree split --prefix="$path" --rejoin -b "$split_branch" 2>&1) || {
        # Check if it's a real error vs just "no commits"
        if echo "$split_output" | grep -q "recursion depth"; then
            warn "  Split failed: git-subtree recursion limit (complex history)"
            warn "  Try: git subtree push --prefix=$path $remote $branch"
            return 1
        elif echo "$split_output" | grep -q "fatal\|error"; then
            warn "  Split failed (see output above)"
            warn "  Try: git subtree push --prefix=$path $remote $branch"
            return 1
        fi
        info "  No new commits to push"
        return 0
    }

    # Push the split branch to the subtree's remote
    info "  Pushing to upstream..."
    if git push "$remote" "$split_branch:$branch"; then
        success "  Pushed $path successfully"
    else
        error "  Failed to push $path"
        return 1
    fi

    # Clean up local split branch (optional, but keeps things tidy)
    git branch -D "$split_branch" 2>/dev/null || true
}

# Push subtrees
if [[ "$META_ONLY" == "false" ]]; then
    info "=== Pushing subtrees to upstreams ==="
    echo

    subtree_count=0
    while IFS='|' read -r path remote branch install; do
        [[ -z "$path" ]] && continue

        # If single subtree specified, skip others
        if [[ -n "$SINGLE_SUBTREE" && "$path" != "$SINGLE_SUBTREE" ]]; then
            continue
        fi

        push_subtree "$path" "$remote" "$branch"
        ((subtree_count++)) || true
        echo
    done < <(get_subtrees)

    if [[ $subtree_count -eq 0 ]]; then
        warn "No subtrees configured in $MANIFEST"
    fi
fi

# Push meta-repo
info "=== Pushing meta-repo ==="

if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY-RUN] Would push meta-repo"
else
    # Get current branch
    current_branch=$(git branch --show-current)

    # Check if upstream is configured
    if git rev-parse --abbrev-ref "@{upstream}" &>/dev/null; then
        if git push; then
            success "Meta-repo pushed successfully"
        else
            error "Failed to push meta-repo"
            exit 1
        fi
    else
        warn "No upstream configured for branch '$current_branch'"
        warn "Run: git push -u origin $current_branch"
    fi
fi

echo
success "All done!"
