#!/bin/bash
# Set up the workspace after cloning
set -e

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "Setting up workspace..."

# Install dependencies
echo "Installing dependencies..."
uv sync

# Set up git hooks
echo "Configuring git hooks..."
git config core.hooksPath .githooks

# Fix git-subtree recursion limit on Debian/Ubuntu
# The system git-subtree uses /bin/sh (dash) which has a 1000 recursion limit.
# Git uses GIT_EXEC_PATH (not PATH) to find subcommands, so we create a custom
# git-core directory with a wrapper that runs git-subtree under bash.
if [[ -f /usr/lib/git-core/git-subtree ]]; then
    echo "Setting up git-subtree bash wrapper..."
    mkdir -p ~/.local/git-core

    # Symlink all git-core commands
    for f in /usr/lib/git-core/*; do
        ln -sf "$f" ~/.local/git-core/ 2>/dev/null || true
    done

    # Create bash wrapper for git-subtree (overwrites the symlink)
    cat > ~/.local/git-core/git-subtree <<'WRAPPER'
#!/usr/bin/env bash
# Wrapper to run git-subtree under bash instead of dash
# Fixes recursion limit issues on Debian/Ubuntu
# The real git-subtree checks GIT_EXEC_PATH is in PATH, so we set both
export GIT_EXEC_PATH="/usr/lib/git-core"
export PATH="/usr/lib/git-core:$PATH"
exec bash /usr/lib/git-core/git-subtree "$@"
WRAPPER
    chmod +x ~/.local/git-core/git-subtree

    # Detect user's shell and add GIT_EXEC_PATH to the appropriate rc file
    shell_name=$(basename "$SHELL")
    case "$shell_name" in
        zsh)  rc_file="$HOME/.zshrc" ;;
        bash) rc_file="$HOME/.bashrc" ;;
        fish) rc_file="$HOME/.config/fish/config.fish" ;;
        *)    rc_file="$HOME/.profile" ;;
    esac

    if ! grep -q 'GIT_EXEC_PATH=.*local/git-core' "$rc_file" 2>/dev/null; then
        echo '' >> "$rc_file"
        echo '# Use custom git-core with bash-based git-subtree (fixes recursion limit)' >> "$rc_file"
        if [[ "$shell_name" == "fish" ]]; then
            echo 'set -gx GIT_EXEC_PATH "$HOME/.local/git-core"' >> "$rc_file"
        else
            echo 'export GIT_EXEC_PATH="$HOME/.local/git-core"' >> "$rc_file"
        fi
        echo "  Added GIT_EXEC_PATH to $rc_file (restart shell or source it)"
    fi
    echo "  Created ~/.local/git-core/git-subtree wrapper"
fi

# Install bd (beads) if not present
if ! command -v bd >/dev/null 2>&1; then
    echo ""
    echo "Installing bd (beads issue tracker)..."
    curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
fi

# Initialize beads databases in subtrees that use them
echo ""
echo "Initializing beads databases..."
for d in */; do
    if [ -d "${d}.beads" ]; then
        echo "  Initializing ${d%/}..."
        (cd "$d" && bd init)
    fi
done

echo ""
echo "Setup complete!"
