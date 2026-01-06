#!/usr/bin/env python3
"""Sync pyproject.toml with installable subtrees.

Uses read-modify-write to preserve existing configuration.
Only updates: project.dependencies, tool.uv.sources, tool.uv.override-dependencies
"""

import sys
from pathlib import Path

try:
    import tomlkit
except ImportError:
    print("Error: tomlkit required. Run: uv pip install tomlkit", file=sys.stderr)
    sys.exit(1)

try:
    import yaml
except ImportError:
    print("Error: pyyaml required. Run: uv pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def get_package_name(path: str) -> str:
    """Convert path to package name (replace _ and / with -)."""
    return path.replace("/", "-").replace("_", "-")


def sync_pyproject():
    workspace = Path(__file__).parent.parent
    manifest_path = workspace / "subtrees.yaml"
    pyproject_path = workspace / "pyproject.toml"

    # Load manifest
    with open(manifest_path) as f:
        manifest = yaml.safe_load(f)

    installable = [st for st in manifest.get("subtrees", []) if st.get("install", False)]
    if not installable:
        print("No installable subtrees found")
        return

    # Load existing pyproject.toml (or create minimal one)
    if pyproject_path.exists():
        with open(pyproject_path) as f:
            config = tomlkit.load(f)
    else:
        config = tomlkit.document()

    # Ensure project section exists
    if "project" not in config:
        config["project"] = tomlkit.table()
        config["project"]["name"] = "workspace"
        config["project"]["version"] = "0.1.0"

    # Update project.dependencies - add installable packages
    dep_names = [get_package_name(st["path"]) for st in installable]
    existing_deps = list(config["project"].get("dependencies", []))

    # Add new deps without duplicating
    for name in dep_names:
        if name not in existing_deps:
            existing_deps.append(name)

    config["project"]["dependencies"] = existing_deps

    # Ensure tool.uv section exists
    if "tool" not in config:
        config["tool"] = tomlkit.table()
    if "uv" not in config["tool"]:
        config["tool"]["uv"] = tomlkit.table()

    # Ensure tool.uv.sources exists
    if "sources" not in config["tool"]["uv"]:
        config["tool"]["uv"]["sources"] = tomlkit.table()

    # Add/update sources for installable packages
    for st in installable:
        name = get_package_name(st["path"])
        source = tomlkit.inline_table()
        source["path"] = f"./{st['path']}"
        source["editable"] = True
        config["tool"]["uv"]["sources"][name] = source

    # Update override-dependencies - add all installable packages
    existing_overrides = list(config["tool"]["uv"].get("override-dependencies", []))
    for name in dep_names:
        if name not in existing_overrides:
            existing_overrides.append(name)

    config["tool"]["uv"]["override-dependencies"] = existing_overrides

    # Write back
    with open(pyproject_path, "w") as f:
        tomlkit.dump(config, f)

    print(f"Updated pyproject.toml with {len(installable)} installable package(s)")


if __name__ == "__main__":
    sync_pyproject()
