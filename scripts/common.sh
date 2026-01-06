#!/usr/bin/env bash
# Common functions for workspace subtree management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$WORKSPACE_ROOT/subtrees.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check if yq is available, fall back to python yaml parsing
parse_yaml() {
    if command -v yq &>/dev/null; then
        yq "$@"
    else
        uv run python3 -c "
import sys, yaml
data = yaml.safe_load(open('$MANIFEST'))
subtrees = data.get('subtrees', [])
if not subtrees or subtrees == []:
    sys.exit(0)
for st in subtrees:
    print(f\"{st['path']}|{st['remote']}|{st.get('branch', 'main')}|{st.get('install', False)}\")
"
    fi
}

# Get list of subtrees as: path|remote|branch|install
get_subtrees() {
    if command -v yq &>/dev/null; then
        yq -r '.subtrees[] | "\(.path)|\(.remote)|\(.branch // "main")|\(.install // false)"' "$MANIFEST" 2>/dev/null || true
    else
        parse_yaml
    fi
}

# Check if we're in the workspace root
check_workspace() {
    if [[ ! -f "$MANIFEST" ]]; then
        error "Not in workspace root or subtrees.yaml not found"
        exit 1
    fi
}

cd_workspace() {
    cd "$WORKSPACE_ROOT"
}
