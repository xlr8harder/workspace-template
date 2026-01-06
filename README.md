# Workspace Template

A template for creating git subtree meta-repos with unified dependency management.

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

This picks up `GIT_EXEC_PATH` needed for the git-subtree fix.

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

## What You Get

After setup, your workspace can:

- **Pull all subtrees** with one command, skipping those already up-to-date
- **Push changes** back to subtree upstreams efficiently
- **Run tests** across all subtrees
- **Merge pre-commit configs** from subtrees into one workspace config
- **Manage Python dependencies** with editable installs that override transitive deps

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

Both are fast (~10-15s) - they skip subtrees already in sync.

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

## How It Works

### Subtree Manifest

`subtrees.yaml` tracks your subtrees:

```yaml
subtrees:
- path: my-lib
  remote: git@github.com:user/my-lib.git
  branch: main
  install: true  # Add as editable Python dependency
```

### Dependency Management

- Installable subtrees become editable installs in `pyproject.toml`
- `tool.uv.override-dependencies` forces local packages over transitive git deps
- Run `uv run python scripts/sync_pyproject.py` after editing `subtrees.yaml`

### Pre-commit Merging

Each subtree can have its own `.pre-commit-config.yaml`. The workspace merges them:
- Hooks get scoped to their subtree (`files: ^my-lib/`)
- Run `uv run python scripts/sync_precommit.py` after changes

## Platform Notes

### Git Subtree Recursion Limit (Debian/Ubuntu)

The system `git-subtree` uses dash which has a 1000 recursion limit. `setup.sh` creates a bash wrapper that fixes this. Make sure to restart your shell after setup.

### Push Performance

First push to a subtree is slow (creates a rejoin marker). Subsequent pushes are fast (~0.5s). Subtrees with no changes are skipped entirely.

## Customizing

- Edit `CLAUDE.md` to add project-specific guidance for AI agents
- Update workspace name in `pyproject.toml`
- Add subtree-specific info to the commented section in `CLAUDE.md`
