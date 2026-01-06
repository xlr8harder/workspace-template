# Workspace Template

A template for creating git subtree meta-repos that manage multiple related projects with unified dependency management.

## Why This Exists

Managing multiple related repositories is painful:
- **Submodules** require constant `git submodule update`, break on branch switches, and make PRs awkward
- **Monorepos** lose individual project history and make it hard to use projects standalone
- **Separate repos** mean dependency hell and no atomic cross-project changes

**Git subtrees** offer a middle ground: projects live in subdirectories with full history, can be pushed/pulled to their own upstreams, and the workspace commits atomically. But subtrees have friction - manual commands, no dependency coordination, slow operations at scale.

This template eliminates that friction.

## Features

### Smart Pull/Push
Both `pull_all.sh` and `push_all.sh` check each subtree against its upstream and skip those already in sync. What could be minutes of git operations becomes ~10 seconds.

### Unified Python Dependencies
Subtrees that are Python packages get installed as editables. If `pkg-a` depends on `pkg-b @ git+...`, the workspace forces it to use your local `pkg-b/` instead. Edit code, import it, no reinstall needed.

### Merged Pre-commit Hooks
Each subtree can have its own `.pre-commit-config.yaml`. The workspace merges them, scoping each subtree's hooks to its directory. One `pre-commit run` checks everything.

### Cross-Subtree Testing
`test_all.sh` runs each subtree's tests in isolation (avoiding conftest.py conflicts) and reports a unified pass/fail.

### Auto-Detection
Adding a subtree auto-detects if it's an installable Python package and configures dependencies accordingly.

### Platform Fixes
The setup script works around the git-subtree recursion limit on Debian/Ubuntu (dash shell's 1000-call limit breaks with large histories).

## Design Decisions

**Subtrees over submodules**: Subtrees embed code directly - no broken references, simpler mental model, atomic commits across projects.

**Manifest-driven**: `subtrees.yaml` is the source of truth. Scripts read from it rather than inferring state from git.

**Fast by default**: Operations skip unchanged subtrees. First push is slow (creates rejoin marker), subsequent pushes are fast.

**Meta-repo first on pull**: When syncing, pull the workspace first, then subtrees. This matches the typical "switch hosts" workflow.

**Editable installs with overrides**: Python packages install as editables with `tool.uv.override-dependencies` forcing local paths over transitive git deps.

**Isolated test runs**: Rather than fighting pytest's conftest.py conflicts, each subtree's tests run separately.

## Getting Started

### 1. Create Your Workspace

**Option A: Use as GitHub template**
- Click "Use this template" on GitHub
- Clone your new repo

**Option B: Fork and clone**
```bash
# Fork on GitHub, then:
git clone git@github.com:YOUR-USER/my-workspace.git
cd my-workspace
```

**Option C: Clone directly**
```bash
git clone git@github.com:xlr8harder/workspace-template.git my-workspace
cd my-workspace
rm -rf .git && git init
git add -A && git commit -m "Initial workspace from template"
```

### 2. Run Setup

```bash
./scripts/setup.sh
```

This:
- Installs Python dependencies via `uv`
- Configures git hooks
- Sets up the git-subtree bash wrapper (fixes recursion limit on Debian/Ubuntu)

### 3. Restart Your Shell

```bash
source ~/.bashrc  # or restart your terminal
```

Required to pick up `GIT_EXEC_PATH` for the git-subtree fix.

### 4. Add Your Subtrees

```bash
# Add a Python library (auto-detected as installable)
./scripts/add_subtree.sh my-lib git@github.com:user/my-lib.git main

# Add a non-Python project
./scripts/add_subtree.sh my-docs git@github.com:user/my-docs.git main --no-install

# Sync dependencies
uv sync
```

### 5. Set Up Remote

```bash
git remote add origin git@github.com:YOUR-USER/my-workspace.git
git push -u origin main
```

## Daily Workflow

```bash
# Pull updates (meta-repo first, then subtrees)
./scripts/pull_all.sh

# Make changes in subtrees, commit normally
git add -A && git commit -m "Fix bug in my-lib"

# Push to all upstreams
./scripts/push_all.sh

# Run all tests
./scripts/test_all.sh
```

### Switching Between Hosts

```bash
./scripts/pull_all.sh && ./scripts/push_all.sh
```

Both are fast - they skip subtrees already in sync.

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `setup.sh` | Initialize workspace after clone |
| `add_subtree.sh` | Add new subtree with auto-detection |
| `pull_all.sh` | Smart pull: meta-repo first, skip up-to-date subtrees |
| `push_all.sh` | Smart push: skip up-to-date subtrees, uses split-rejoin |
| `status.sh` | Show subtree status vs upstreams |
| `test_all.sh` | Run tests across all subtrees |
| `sync_pyproject.py` | Sync pyproject.toml from subtrees.yaml |
| `sync_precommit.py` | Merge subtree pre-commit configs |

## Configuration Files

### subtrees.yaml

The manifest tracking your subtrees:

```yaml
subtrees:
- path: my-lib
  remote: git@github.com:user/my-lib.git
  branch: main
  install: true  # Add as editable Python dependency
```

### pyproject.toml

Workspace-level Python config. The sync script manages:
- `project.dependencies` - installable subtrees
- `tool.uv.sources` - paths to local packages
- `tool.uv.override-dependencies` - force local over transitive

### CLAUDE.md

Guidance for AI agents working in the workspace. Customize the commented section at the bottom for project-specific instructions.

## Platform Notes

### Git Subtree Recursion Limit (Debian/Ubuntu)

The system `git-subtree` uses `/bin/sh` (dash), which has a 1000 function recursion limit. With enough commits, `git subtree split` fails. `setup.sh` creates a bash wrapper at `~/.local/git-core/git-subtree` and sets `GIT_EXEC_PATH`.

### Push Performance

The `--rejoin` flag caches split state via merge commits:
- **First push to a subtree**: Slow - must traverse entire history to create rejoin marker. For a workspace with ~1000 commits, expect 30-60+ seconds per subtree. The script warns you when no rejoin marker exists.
- **Subsequent pushes**: Fast (~0.5s) - rejoin marker lets git skip already-processed history
- **No changes**: Skipped entirely (tree-hash comparison, ~1s per subtree)
