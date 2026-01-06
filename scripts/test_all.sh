#!/usr/bin/env bash
# Run tests across all subtrees
#
# Each subtree's tests run in isolation to avoid conftest conflicts.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- pytest-args]

Run tests across all subtrees with test directories.

Options:
  --subtree=X   Only test the specified subtree
  -h, --help    Show this help

Examples:
  $(basename "$0")                    # Run all tests
  $(basename "$0") --subtree=my-lib   # Only test my-lib
  $(basename "$0") -- -v -k "test_foo"  # Pass args to pytest
EOF
    exit 0
}

SINGLE_SUBTREE=""
PYTEST_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subtree=*) SINGLE_SUBTREE="${1#*=}"; shift ;;
        -h|--help) usage ;;
        --) shift; PYTEST_ARGS=("$@"); break ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

check_workspace
cd_workspace

# Collect subtrees with tests
test_dirs=()
while IFS='|' read -r path remote branch install; do
    [[ -z "$path" ]] && continue

    # If single subtree specified, skip others
    if [[ -n "$SINGLE_SUBTREE" && "$path" != "$SINGLE_SUBTREE" ]]; then
        continue
    fi

    if [[ -d "$path/tests" ]]; then
        test_dirs+=("$path")
    fi
done < <(get_subtrees)

if [[ ${#test_dirs[@]} -eq 0 ]]; then
    warn "No test directories found"
    exit 0
fi

info "Running tests for ${#test_dirs[@]} subtree(s): ${test_dirs[*]}"
echo

failed=()
passed=()

for subtree in "${test_dirs[@]}"; do
    info "=== Testing: $subtree ==="

    if uv run pytest "$subtree/tests" "${PYTEST_ARGS[@]}" ; then
        passed+=("$subtree")
        success "  $subtree: PASSED"
    else
        failed+=("$subtree")
        error "  $subtree: FAILED"
    fi
    echo
done

# Summary
info "=== Summary ==="
if [[ ${#passed[@]} -gt 0 ]]; then
    success "Passed: ${passed[*]}"
fi
if [[ ${#failed[@]} -gt 0 ]]; then
    error "Failed: ${failed[*]}"
    exit 1
fi

success "All tests passed!"
