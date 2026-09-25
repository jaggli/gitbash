#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

stash() {
    if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
    fi
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        gb_help << 'EOF'
Usage: stash [NAME...]

Create a git stash with a descriptive name.
If no name is provided, prompts for one interactively.

Options:
  -h, --help    Show this help message

Features:
  - Stashes all changes: staged, unstaged and untracked files
  - Custom stash message for easy identification

Examples:
  $ stash
  Stash name: work in progress on login
  ✓ Created stash: work in progress on login

  $ stash fix for authentication bug
  ✓ Created stash: fix for authentication bug

Requirements:
  - Must be in a git repository with at least one commit
  - Must have changes to stash

See also:
  stashes -h     Show help for stashes menu
  unstash -h     Show help for unstash command
  cleanstash -h  Show help for cleanstash command

EOF
        return 0
    fi

    require_git_repo || return 1

    if ! git rev-parse --verify --quiet HEAD >/dev/null; then
        print_error "Cannot stash before the first commit."
        return 1
    fi

    if [[ -z "$(git status --porcelain)" ]]; then
        echo "No changes to stash."
        return 1
    fi

    local stash_name
    if [[ $# -gt 0 ]]; then
        stash_name="$*"
    else
        prompt_read "Stash name: " stash_name || true
        if [[ -z "$stash_name" ]]; then
            print_error "Stash name cannot be empty."
            return 1
        fi
    fi

    if git stash push --include-untracked -m "$stash_name"; then
        print_success "Created stash: $stash_name"
    else
        print_error "Failed to create stash."
        return 1
    fi
}
