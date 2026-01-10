#!/usr/bin/env bash
# Pull all subtrees from their upstreams, then pull meta-repo
#
# Usage: pull_all.sh [--subtree=name]

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Pull changes from all subtree upstreams and the meta-repo remote.

Options:
  --subtrees-first  Pull subtrees before meta-repo (default: meta-repo first)
  --meta-only       Only pull the meta-repo, skip subtrees
  --subtree=X       Only pull the specified subtree
  --no-meta         Skip pulling meta-repo
  -h, --help        Show this help

Note: Pulling subtrees may create merge commits in your meta-repo.
      Meta-repo pulls use merge (no rebase) to preserve subtree rejoin history.
EOF
    exit 0
}

META_FIRST=true
META_ONLY=false
NO_META=false
SINGLE_SUBTREE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subtrees-first) META_FIRST=false; shift ;;
        --meta-only) META_ONLY=true; shift ;;
        --no-meta) NO_META=true; shift ;;
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

pull_meta() {
    info "=== Pulling meta-repo ==="

    if git rev-parse --abbrev-ref "@{upstream}" &>/dev/null; then
        if git pull --no-rebase; then
            success "Meta-repo pulled successfully"
        else
            error "Failed to pull meta-repo (you may need to resolve conflicts)"
            return 1
        fi
    else
        warn "No upstream configured for current branch"
    fi
    echo
}

pull_subtree() {
    local path="$1"
    local remote="$2"
    local branch="$3"

    info "Pulling subtree: $path <- $remote ($branch)"

    if ! [[ -d "$path" ]]; then
        warn "  Directory '$path' doesn't exist, skipping"
        return 0
    fi

    # Fast check: compare tree hashes to see if there's anything to pull
    info "  Checking for changes..."
    if git fetch "$remote" "$branch" --quiet 2>/dev/null; then
        local upstream_tree local_tree
        upstream_tree=$(git rev-parse "FETCH_HEAD^{tree}" 2>/dev/null) || true
        local_tree=$(git rev-parse "HEAD:$path" 2>/dev/null) || true

        if [[ -n "$upstream_tree" && -n "$local_tree" && "$upstream_tree" == "$local_tree" ]]; then
            info "  Already up to date (skipping)"
            return 0
        fi
    fi

    # Pull from upstream
    # Note: This creates a merge commit in your meta-repo
    info "  Pulling changes..."
    if git subtree pull --prefix="$path" "$remote" "$branch" -m "Merge upstream '$branch' into $path"; then
        success "  Pulled $path successfully"
    else
        error "  Failed to pull $path (conflicts may need resolution)"
        return 1
    fi
}

# Pull meta-repo first if requested
if [[ "$META_FIRST" == "true" && "$NO_META" == "false" ]]; then
    pull_meta
fi

# Pull subtrees
if [[ "$META_ONLY" == "false" ]]; then
    info "=== Pulling subtrees from upstreams ==="
    echo

    subtree_count=0
    while IFS='|' read -r path remote branch install; do
        [[ -z "$path" ]] && continue

        # If single subtree specified, skip others
        if [[ -n "$SINGLE_SUBTREE" && "$path" != "$SINGLE_SUBTREE" ]]; then
            continue
        fi

        pull_subtree "$path" "$remote" "$branch"
        ((subtree_count++)) || true
        echo
    done < <(get_subtrees)

    if [[ $subtree_count -eq 0 ]]; then
        warn "No subtrees configured in $MANIFEST"
    fi
fi

# Pull meta-repo last (default)
if [[ "$META_FIRST" == "false" && "$META_ONLY" == "false" && "$NO_META" == "false" ]]; then
    pull_meta
fi

# Meta-only mode
if [[ "$META_ONLY" == "true" ]]; then
    pull_meta
fi

success "All done!"
