#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

branch() {
    # -----------------------------
    # 0. Check for help/version flag
    # -----------------------------
    if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
    fi
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        gb_help << 'EOF'
Usage: branch [OPTIONS]

Interactive menu to manage git branches.
Choose between creating, switching, or updating branches.

Options:
  -h, --help    Show this help message

Features:
  - Interactive action selection
  - Create: Create a new branch with Jira issue parsing
  - Switch: Switch between branches with fzf selector
  - Update: Update current branch with latest main/master

Navigation:
  ↑/↓           Navigate through options (typing filters the list)
  Enter         Select action
  ESC/Ctrl-C    Abort

Examples:
  $ branch      # pick Create, Switch or Update, then continue as in that command

Actions:
  🌿 Create - Create a new feature branch with Jira parsing
  🔀 Switch - Switch to another branch using fzf
  ⬆️  Update - Update current branch with latest main/master

Requirements:
  - fzf (fuzzy finder)

See also:
  create -h    Show help for create command
  switch -h    Show help for switch command
  update -h    Show help for update command

EOF
        return 0
    fi

    if [[ $# -gt 0 ]]; then
        print_error "Unknown argument: $1"
        echo "Usage: branch [-h|--help]" >&2
        return 1
    fi

    # -----------------------------
    # 1. Check for fzf
    # -----------------------------
    require_fzf || return 1

    # -----------------------------
    # 2. Build action menu
    # -----------------------------
    local create_option="🌿 Create - Create a new feature branch"
    local switch_option="🔀 Switch - Switch to another branch"
    local update_option="⬆️  Update - Update current branch with main/master"
    local abort_label="✖ Abort"

    local choices
    choices=$(
        {
            echo "$create_option"
            echo "$switch_option"
            echo "$update_option"
            echo "$abort_label"
        }
    )

    # -----------------------------
    # 3. Run fzf menu
    # -----------------------------
    local selection
    selection=$(run_fzf --prompt="Branch action > " \
              -i \
              --reverse \
              --border \
              --header="What would you like to do?" \
              --no-multi \
              <<< "$choices"
    ) || true

    # ESC or Ctrl-C
    if [[ -z "$selection" ]]; then
        echo "Aborted."
        return 0
    fi

    # -----------------------------
    # 4. Execute based on selection
    # -----------------------------
    case "$selection" in
        "$create_option")
            gb_run create
            ;;
        "$switch_option")
            gb_run switch
            ;;
        "$update_option")
            gb_run update
            ;;
        "$abort_label")
            echo "Aborted."
            return 0
            ;;
        *)
            echo "Unknown selection."
            return 1
            ;;
    esac
}
