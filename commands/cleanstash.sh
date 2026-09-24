#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"
# shellcheck source=unstash.sh
source "$SOURCE_DIR/unstash.sh"

cleanstash() {
    if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
    fi
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        cat << 'EOF'
Usage: cleanstash [OPTIONS]

Delete git stashes without applying them.
Interactive fuzzy finder (fzf) with preview and multi-select support.

Options:
  -h, --help    Show this help message

Navigation:
  ↑/↓           Navigate through stashes
  TAB           Select/deselect stash (multi-select)
  Enter         Confirm selection
  ESC/Ctrl-C    Abort

Notes:
  - Asks for confirmation before deleting
  - Stashes are deleted from the highest index down, so indices stay valid
  - No changes are applied to your working directory

Requirements:
  - fzf (fuzzy finder)

EOF
        return 0
    fi

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
              --header="Select stashes to delete (TAB for multi-select)" \
              --multi \
              --preview="$(_stash_preview)" \
              <<< "$stash_list"
    ) || true

    if [[ -z "$selection" ]]; then
        echo "Aborted."
        return 0
    fi

    local stash_ids=() stash_id line
    while IFS= read -r line; do
        stash_id=$(printf '%s' "$line" | grep -o '^stash@{[0-9]*}' || true)
        [[ -n "$stash_id" ]] && stash_ids+=("$stash_id")
    done <<< "$selection"

    if [[ ${#stash_ids[@]} -eq 0 ]]; then
        print_error "Could not determine any stash IDs."
        return 1
    fi

    echo "Selected stashes to delete:"
    printf '  - %s\n' "${stash_ids[@]}"
    echo

    if ! gb_confirm "Delete these ${#stash_ids[@]} stash(es)?" n; then
        echo "Deletion cancelled. No stashes were removed."
        return 0
    fi

    # Highest index first, so the remaining indices don't shift
    local sorted_ids=() id
    while IFS= read -r id; do
        sorted_ids+=("$id")
    done < <(printf '%s\n' "${stash_ids[@]}" | sort -t'{' -k2 -rn)

    for stash_id in "${sorted_ids[@]}"; do
        if git stash drop --quiet "$stash_id"; then
            print_success "Deleted $stash_id"
        else
            print_error "Failed to delete $stash_id"
        fi
    done
}
