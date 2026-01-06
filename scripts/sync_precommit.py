#!/usr/bin/env python3
"""
Merge subtree .pre-commit-config.yaml files into workspace config.

For each subtree with a pre-commit config, adds its hooks to the workspace
config with `files: ^subtree_name/` to scope them appropriately.
"""

import yaml
from pathlib import Path


def load_yaml(path: Path) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def scope_hook(hook: dict, subtree: str, is_local: bool = False) -> dict:
    """Add files prefix to scope hook to subtree directory."""
    hook = hook.copy()

    # Prefix the files pattern
    existing = hook.get('files', '')
    if existing:
        # Combine with existing pattern
        hook['files'] = f"^{subtree}/({existing})"
    else:
        hook['files'] = f"^{subtree}/"

    # Prefix exclude pattern if present
    if 'exclude' in hook:
        import re
        exclude = hook['exclude']

        # Handle verbose regex mode (?x) - normalize whitespace
        if '(?x)' in exclude:
            exclude = exclude.replace('(?x)', '')
            exclude = re.sub(r'\s+', '', exclude)  # Remove all whitespace

        # Transform anchored patterns: ^foo$ -> ^subtree/foo$
        if exclude.startswith('^'):
            exclude = f"^{subtree}/" + exclude[1:]
        else:
            exclude = f"^{subtree}/({exclude})"

        hook['exclude'] = exclude

    # Only rename IDs for local hooks (remote repos expect specific IDs)
    if is_local:
        hook['id'] = f"{subtree}-{hook['id']}"
        if 'alias' in hook:
            hook['alias'] = f"{subtree}-{hook['alias']}"
    else:
        # For remote hooks, add alias for display but keep original id
        hook['alias'] = f"{subtree}-{hook['id']}"

    # Always set name to indicate subtree (use existing name or fall back to id)
    hook['name'] = f"[{subtree}] {hook.get('name', hook['id'])}"

    return hook


def scope_local_hook(hook: dict, subtree: str) -> dict:
    """Scope a local hook, handling entry scripts that reference paths."""
    hook = scope_hook(hook, subtree, is_local=True)

    # Prefix entry path for script language hooks
    if hook.get('language') == 'script' and 'entry' in hook:
        hook['entry'] = f"{subtree}/{hook['entry']}"

    return hook


def merge_configs(workspace_root: Path) -> dict:
    """Read all subtree pre-commit configs and merge into one."""

    manifest_path = workspace_root / 'subtrees.yaml'
    if not manifest_path.exists():
        print("No subtrees.yaml found")
        return {'repos': []}

    manifest = load_yaml(manifest_path)
    subtrees = manifest.get('subtrees', [])

    if not subtrees:
        print("No subtrees configured")
        return {'repos': []}

    merged_repos = []
    local_hooks = []

    for st in subtrees:
        subtree_path = st['path']
        config_path = workspace_root / subtree_path / '.pre-commit-config.yaml'

        if not config_path.exists():
            continue

        print(f"Processing {subtree_path}/.pre-commit-config.yaml")
        config = load_yaml(config_path)

        for repo in config.get('repos', []):
            if repo['repo'] == 'local':
                # Collect local hooks separately
                for hook in repo.get('hooks', []):
                    local_hooks.append(scope_local_hook(hook, subtree_path))
            else:
                # Remote repo - scope each hook
                scoped_repo = {
                    'repo': repo['repo'],
                    'rev': repo.get('rev', 'main'),
                    'hooks': [scope_hook(h, subtree_path) for h in repo.get('hooks', [])]
                }
                merged_repos.append(scoped_repo)

    # Add local hooks as a single repo block
    if local_hooks:
        merged_repos.append({
            'repo': 'local',
            'hooks': local_hooks
        })

    return {'repos': merged_repos}


def main():
    workspace_root = Path(__file__).parent.parent

    merged = merge_configs(workspace_root)

    if not merged['repos']:
        print("No pre-commit configs found in subtrees")
        return

    output_path = workspace_root / '.pre-commit-config.yaml'

    with open(output_path, 'w') as f:
        f.write("# AUTO-GENERATED from subtree pre-commit configs\n")
        f.write("# Do not edit directly - run scripts/sync_precommit.py\n\n")
        yaml.dump(merged, f, default_flow_style=False, sort_keys=False)

    print(f"Wrote {output_path}")


if __name__ == '__main__':
    main()
