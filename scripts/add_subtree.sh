#!/usr/bin/env bash
# Add a new subtree to the workspace
#
# Usage: add_subtree.sh <path> <remote> [branch]
#
# This adds the subtree AND updates subtrees.yaml

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <path> <remote> [branch] [--no-install]

Add a new git subtree to the workspace.

Arguments:
  path        Directory name for the subtree (e.g., "my-lib")
  remote      Git remote URL
  branch      Branch to track (default: main)
  --no-install  Don't install even if it looks like a Python package

Install is auto-detected based on pyproject.toml:
  - Has [project].name → installable (unless packages=[] in hatch config)

Example:
  $(basename "$0") my-lib git@github.com:user/my-lib.git main
EOF
    exit 1
}

[[ $# -lt 2 ]] && usage

PATH_NAME="$1"
REMOTE="$2"
BRANCH="${3:-main}"
NO_INSTALL=false

# Check for --no-install flag
for arg in "$@"; do
    [[ "$arg" == "--no-install" ]] && NO_INSTALL=true
done

# Remove --no-install from branch if it was passed as branch
[[ "$BRANCH" == "--no-install" ]] && BRANCH="main"

check_workspace
cd_workspace

# Check if path already exists
if [[ -d "$PATH_NAME" ]]; then
    error "Directory '$PATH_NAME' already exists"
    exit 1
fi

info "Adding subtree '$PATH_NAME' from $REMOTE ($BRANCH branch)"

# Add the subtree
git subtree add --prefix="$PATH_NAME" "$REMOTE" "$BRANCH"

success "Subtree added successfully"

# Auto-detect if installable
INSTALL=false
if [[ "$NO_INSTALL" == "false" ]] && [[ -f "$PATH_NAME/pyproject.toml" ]]; then
    # Check if it has [project].name and is not explicitly disabled
    INSTALL=$(uv run python3 <<DETECT
import tomllib
from pathlib import Path

pyproject = Path("$PATH_NAME/pyproject.toml")
try:
    with open(pyproject, "rb") as f:
        config = tomllib.load(f)

    # Must have [project].name
    if not config.get("project", {}).get("name"):
        print("false")
    # Check if explicitly disabled via hatch packages=[]
    elif config.get("tool", {}).get("hatch", {}).get("build", {}).get("packages") == []:
        print("false")
    else:
        print("true")
except Exception:
    print("false")
DETECT
)
fi

if [[ "$INSTALL" == "true" ]]; then
    info "Detected installable Python package"
else
    info "Not an installable package (no pyproject.toml or explicitly disabled)"
fi

# Update manifest
info "Updating subtrees.yaml..."

uv run python3 <<EOF
import yaml

with open('$MANIFEST', 'r') as f:
    data = yaml.safe_load(f)

if data.get('subtrees') is None or data['subtrees'] == []:
    data['subtrees'] = []

# Check if already exists
for st in data['subtrees']:
    if st['path'] == '$PATH_NAME':
        print(f"Entry for '$PATH_NAME' already exists in manifest")
        exit(0)

data['subtrees'].append({
    'path': '$PATH_NAME',
    'remote': '$REMOTE',
    'branch': '$BRANCH',
    'install': $( [[ "$INSTALL" == "true" ]] && echo "True" || echo "False" )
})

with open('$MANIFEST', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)

print(f"Added '$PATH_NAME' to manifest")
EOF

# Sync pyproject.toml if this is an installable package
if [[ "$INSTALL" == "true" ]]; then
    info "Syncing pyproject.toml..."
    uv run python3 "$SCRIPT_DIR/sync_pyproject.py"
fi

# Sync pre-commit config if subtree has one
if [[ -f "$PATH_NAME/.pre-commit-config.yaml" ]]; then
    info "Syncing pre-commit config..."
    uv run python3 "$SCRIPT_DIR/sync_precommit.py"
fi

# Initialize beads database if subtree has .beads
if [[ -d "$PATH_NAME/.beads" ]] && command -v bd &>/dev/null; then
    info "Initializing beads database for $PATH_NAME..."
    (cd "$PATH_NAME" && bd init 2>/dev/null || true)
fi

# Commit everything
info "Committing..."
git add -A
git commit -m "Add subtree: $PATH_NAME

Remote: $REMOTE
Branch: $BRANCH"

success "Done! Subtree '$PATH_NAME' added and committed."
