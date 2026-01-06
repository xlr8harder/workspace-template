# Workspace Template

Meta-repo template for managing multiple related projects via git subtrees with unified dependency management.

## Quick Start

1. **Clone or use as template**:
   ```bash
   git clone <this-repo> my-workspace
   cd my-workspace
   ```

2. **Run setup**:
   ```bash
   ./scripts/setup.sh
   ```
   This installs dependencies, configures git hooks, and sets up the git-subtree bash wrapper (fixes recursion limit on Debian/Ubuntu).

3. **Restart your shell** (or `source ~/.bashrc`) to pick up `GIT_EXEC_PATH`.

4. **Add your first subtree**:
   ```bash
   ./scripts/add_subtree.sh my-lib git@github.com:user/my-lib.git main
   uv sync
   ```

## Adding Subtrees

```bash
./scripts/add_subtree.sh <path> <git-url> [branch] [--no-install]
```

The script automatically:
1. Adds the git subtree
2. Auto-detects if it's an installable Python package
3. Updates `subtrees.yaml` manifest
4. Syncs `pyproject.toml` with editable installs (if installable)
5. Syncs pre-commit config (if subtree has `.pre-commit-config.yaml`)
6. Commits everything

## Daily Workflow

### Pulling Updates
```bash
./scripts/pull_all.sh
```
Pulls meta-repo first, then checks each subtree and only pulls those with upstream changes.

### Pushing Changes
```bash
./scripts/push_all.sh
```
Checks each subtree and only pushes those with local changes, then pushes meta-repo.

### Sync Between Hosts
```bash
./scripts/pull_all.sh && ./scripts/push_all.sh
```
Both are fast (~10-15s) - they skip subtrees already in sync.

### Run All Tests
```bash
./scripts/test_all.sh
```

### Check Status
```bash
./scripts/status.sh
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `setup.sh` | Initialize workspace after clone |
| `add_subtree.sh` | Add new subtree with auto-detection |
| `pull_all.sh` | Smart pull: meta-repo first, skip up-to-date subtrees |
| `push_all.sh` | Smart push: skip up-to-date subtrees, uses split-rejoin |
| `status.sh` | Show subtree status |
| `test_all.sh` | Run tests across all subtrees |
| `sync_pyproject.py` | Sync pyproject.toml from manifest |
| `sync_precommit.py` | Merge subtree pre-commit configs |

## How It Works

### Dependency Management

- Installable subtrees are listed in workspace `pyproject.toml` as editable installs
- `tool.uv.sources` maps package names to local paths
- `tool.uv.override-dependencies` forces local packages over transitive git dependencies

### Pre-commit Hooks

Each subtree can have its own `.pre-commit-config.yaml`. The workspace merges them:
- Remote hooks get scoped with `files: ^subtree/`
- Local hooks get prefixed IDs and adjusted paths

After modifying subtree pre-commit configs:
```bash
uv run python scripts/sync_precommit.py
```

### Git Hooks

The workspace uses custom hooks in `.githooks/`:
- **pre-commit**: Shows reminder, detects modified subtrees, runs pre-commit checks
- **pre-push**: Warns about subtree changes needing separate push

## Platform Notes

### Git Subtree Recursion Limit (Debian/Ubuntu)

The system `git-subtree` uses `/bin/sh` (dash), which has a 1000 recursion limit. `setup.sh` creates a bash wrapper at `~/.local/git-core/git-subtree` and sets `GIT_EXEC_PATH`.

### Subtree Push Performance

- First push after changes creates a rejoin marker, subsequent pushes are fast
- Subtrees with no changes are skipped entirely (tree-hash comparison)
