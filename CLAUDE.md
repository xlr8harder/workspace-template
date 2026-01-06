# Workspace

Meta-repo managing multiple related projects via git subtrees with unified dependency management.

> **Note**: When working in a subtree directory, also read that subtree's `CLAUDE.md` (if it exists) for project-specific guidance.

## Subtree Management

### Adding a Subtree

```bash
./scripts/add_subtree.sh <path> <git-url> [branch] [--no-install]
```

The script automatically:
1. Adds the git subtree
2. **Auto-detects** if it's an installable Python package:
   - Has `pyproject.toml` with `[project].name` → installable
   - Has `[tool.hatch.build] packages = []` → NOT installable
3. Updates `subtrees.yaml` manifest
4. Syncs `pyproject.toml` with editable installs (if installable)
5. Syncs pre-commit config (if subtree has `.pre-commit-config.yaml`)
6. Commits everything

Use `--no-install` to override auto-detection.

### Pulling Updates

```bash
./scripts/pull_all.sh
```

Pulls meta-repo first, then checks each subtree and only pulls those with upstream changes. Run `uv sync` afterward if dependencies changed.

### Pushing Changes

```bash
./scripts/push_all.sh
```

Checks each subtree and only pushes those with local changes, then pushes meta-repo. Uses `git subtree split --rejoin` for efficient incremental pushes.

### Checking Status

```bash
./scripts/status.sh
```

Shows status of all subtrees relative to their upstreams.

## Testing

Run tests across all subtrees:
```bash
./scripts/test_all.sh
```

Test a specific subtree:
```bash
./scripts/test_all.sh --subtree=my-lib
```

Pass arguments to pytest:
```bash
./scripts/test_all.sh -- -v -k "test_foo"
```

Each subtree's tests run in isolation to avoid conftest conflicts.

## Dependency Management

### How It Works

1. **Installable subtrees** are listed in workspace `pyproject.toml` as editable installs
2. **`tool.uv.sources`** maps package names to local paths
3. **`tool.uv.override-dependencies`** forces local packages over transitive git dependencies

Example: If `pkg-a` depends on `pkg-b @ git+...`, the override forces it to use the local `pkg-b/` instead.

### Syncing Dependencies

After modifying `subtrees.yaml`:
```bash
uv run python scripts/sync_pyproject.py
uv sync
```

The sync script uses read-modify-write to preserve custom configuration.

## Pre-commit Hooks

### How It Works

Each subtree can have its own `.pre-commit-config.yaml`. The workspace merges them:

1. **Remote hooks** (e.g., ruff) get scoped with `files: ^subtree/`
2. **Local hooks** get prefixed IDs and adjusted paths
3. **Names** show subtree prefix: `[my-lib] ruff`, `[my-lib] ruff-format`

### Syncing Pre-commit Config

After adding/modifying subtree pre-commit configs:
```bash
uv run python scripts/sync_precommit.py
```

The generated `.pre-commit-config.yaml` is auto-generated - don't edit directly.

### Running Pre-commit

```bash
uv run pre-commit run --all-files
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `setup.sh` | Initialize workspace after clone (deps, hooks) |
| `add_subtree.sh` | Add new subtree with auto-detection |
| `pull_all.sh` | Smart pull: meta-repo first, skip up-to-date subtrees |
| `push_all.sh` | Smart push: skip up-to-date subtrees, uses split-rejoin |
| `status.sh` | Show subtree status |
| `test_all.sh` | Run tests across all subtrees |
| `sync_pyproject.py` | Sync pyproject.toml from manifest |
| `sync_precommit.py` | Merge subtree pre-commit configs |
| `common.sh` | Shared bash utilities |

## Git Hooks

The workspace uses custom hooks in `.githooks/` (configured via `git config core.hooksPath`):

### pre-commit
- Shows reminder box: "WORKSPACE META-REPO"
- Detects which subtrees are modified in the commit
- Shows push commands for affected subtrees
- Runs merged pre-commit checks via `uv run pre-commit`

### pre-push
- Detects if pushing to workspace remote vs subtree upstream
- **Workspace push**: Warns that subtree changes need separate push, shows commands
- **Subtree push**: Brief confirmation message
- **Via push_all.sh**: Hook is silenced (script handles its own messaging)

## Common Workflows

### Add a New Project

```bash
./scripts/add_subtree.sh my-project git@github.com:user/my-project.git main
uv sync
```

### Update All Projects

```bash
./scripts/pull_all.sh
uv sync
```

### Sync Between Hosts

When switching between machines:
```bash
./scripts/pull_all.sh && ./scripts/push_all.sh
```

Both scripts are fast (~10-15s) - they skip subtrees that are already in sync.

### Make Changes and Push Back

```bash
# Edit files in subtree
vim my-lib/src/my_lib/main.py

# Commit in workspace
git add -A && git commit -m "Fix bug in my-lib"

# Push to upstream
./scripts/push_all.sh
```

## Platform Notes

### Git Subtree Recursion Limit (Debian/Ubuntu)

The system `git-subtree` script uses `/bin/sh` (dash on Debian/Ubuntu), which has a hard 1000 function recursion limit. With enough commits in the workspace, `git subtree split` will fail with a "recursion depth" error.

**Solution**: `setup.sh` creates a wrapper at `~/.local/git-core/git-subtree` that runs the real script under bash, and sets `GIT_EXEC_PATH` in your shell rc file. Git uses `GIT_EXEC_PATH` (not `PATH`) to find subcommands.

**After running setup.sh**: Restart your shell (or `source ~/.bashrc`) to pick up `GIT_EXEC_PATH`.

### Subtree Push Performance

The `--rejoin` flag caches split state via merge commits. However:
- **First push after changes**: Creates the rejoin marker, subsequent pushes are fast (~0.5s)
- **Subtrees with no local changes**: `push_all.sh` does a fast tree-hash comparison and skips the expensive split entirely
- **New subtrees**: Until you make your first local change and push, there's no rejoin marker

<!--
## Current Subtrees

Add your subtrees here as you add them:

| Path | Install | Description |
|------|---------|-------------|
| example-lib | true | Example library |

## Project-Specific Notes

Add any project-specific guidance here.
-->
