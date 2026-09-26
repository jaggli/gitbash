#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# fzf preview command for a stash list line
_stash_preview() {
    local pager
    pager=$(gb_diff_pager)
    printf '%s' '
        sel=$(printf "%s" {} | grep -o "^stash@{[0-9]*}" || true)
        if [[ -n "$sel" ]]; then
            { git stash show --include-untracked -p --color=$GB_COLOR "$sel" 2>/dev/null ||
              git stash show -p --color=$GB_COLOR "$sel" 2>/dev/null; } | '"$pager"'
        else
            echo "No preview"
        fi'
}

unstash() {
    if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
    fi
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        gb_help << 'EOF'
Usage: unstash [OPTIONS]

Apply a git stash to your working directory with optional removal.
Interactive fuzzy finder (fzf) with preview support.

Options:
  -y, --yes     Don't ask for confirmations (drops the stash after applying it)
  -h, --help    Show this help message

Workflow:
  1. Select a stash from the list (preview shows its changes)
  2. The stash is applied with 'git stash apply'
  3. Choose whether to drop (delete) it (default: yes)

Notes:
  - If applying fails or causes conflicts, the stash is kept

Requirements:
  - fzf (fuzzy finder)

EOF
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) unstash --help; return 0 ;;
            -y|--yes) export GITBASH_ASSUME_YES=1 ;;
            *)
                print_error "Unknown argument: $1"
                echo "Usage: unstash [-y|--yes]" >&2
                return 1
                ;;
        esac
        shift
    done

    require_git_repo || return 1

    local stash_list
    stash_list=$(git stash list)
    if [[ -z "$stash_list" ]]; then
        echo "No stashes."
        return 0
    fi

    require_fzf || return 1

    local selection
    selection=$(run_fzf --prompt="Available stashes > " \
              -i \
              --reverse \
              --border \
              --header="Select a stash to apply" \
              --no-multi \
              --preview="$(_stash_preview)" \
              <<< "$stash_list"
    ) || true

    if [[ -z "$selection" ]]; then
        echo "Aborted."
        return 0
    fi

    local stash_id
    stash_id=$(printf '%s' "$selection" | grep -o '^stash@{[0-9]*}' || true)
    if [[ -z "$stash_id" ]]; then
        print_error "Could not determine the stash ID."
        return 1
    fi

    echo "Applying $stash_id ..."
    # The restored files are good news: list them in green, not git's red
    if ! git -c color.status.changed=green -c color.status.untracked=green \
            stash apply "$stash_id"; then
        print_error "Apply failed or had conflicts - the stash was kept."
        return 1
    fi

    echo
    if gb_confirm "Drop $stash_id now?" y; then
        git stash drop "$stash_id"
    else
        echo "Stash kept."
    fi
}
