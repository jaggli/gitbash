#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Stage changes and commit with a message.
# If no commit message argument is given, prompt the user for one.
commit() {
  local should_push=false
  local staged_only=false
  local amend_mode=false
  local show_prefix_menu=false
  local force_with_lease=false
  local msg_parts=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        cat << 'EOF'
Usage: commit [OPTIONS] [MESSAGE...] [-- MESSAGE...]

Commit your changes with a message.

Options:
  -p, --push              Push to the remote after a successful commit
  -s, --staged            Commit only staged changes
  -a, --amend             Amend the last commit (keeps its message if none is given)
  -t, --type              Show conventional commit type selector (feat, fix, docs, etc.)
  -y, --yes               Don't ask for confirmations (untracked files, staged/all)
      --force-with-lease  Allow overwriting the remote branch when pushing (after amend/rebase)
  --                      Everything after this is the message (even if it starts with '-')
  -h, --help              Show this help message

What gets committed:
  - Only staged changes          → commits them
  - Only unstaged/untracked      → stages everything (lists new files first) and commits
  - Both staged and unstaged     → asks: [s]taged only (default) or [a]ll

Pushing (-p):
  - New branches are pushed with tracking (-u)
  - If the remote has new commits you don't have, they are fast-forwarded
  - If your branch and the remote diverged, you are asked whether to rebase,
    merge or abort. Nothing is rewritten without asking.
  - After --amend, you are asked before force-pushing (--force-with-lease)

Conventional Commit Types (with --type):
  feat, fix, docs, style, refactor, perf, test, build, ci, chore

Examples:
  commit                                    # Interactive mode
  commit add user validation                # Quick commit
  commit refactor auth module --push        # Commit and push
  commit -s -p fix bug                      # Commit only staged and push
  commit -t add user endpoint               # Conventional commit with type menu
  commit --amend                            # Amend, keep the message
  commit --amend fix typo                   # Amend with a new message
  commit -- -1 is not a valid index         # Message starting with '-'

EOF
        return 0
        ;;
      -p|--push)
        should_push=true
        shift
        ;;
      -s|--staged)
        staged_only=true
        shift
        ;;
      -a|--amend)
        amend_mode=true
        shift
        ;;
      -t|--type)
        show_prefix_menu=true
        shift
        ;;
      -y|--yes)
        GITBASH_ASSUME_YES=1
        shift
        ;;
      --force-with-lease)
        force_with_lease=true
        shift
        ;;
      --)
        shift
        msg_parts+=("$@")
        break
        ;;
      -*)
        print_error "Unknown option: $1"
        echo "Usage: commit [-p] [-s] [-a] [-t] [-y] [--force-with-lease] [message...]" >&2
        return 1
        ;;
      *)
        msg_parts+=("$1")
        shift
        ;;
    esac
  done

  require_git_repo || return 1

  local msg=""
  if [[ ${#msg_parts[@]} -gt 0 ]]; then
    msg="${msg_parts[*]}"
  fi

  # -----------------------------
  # 1. Decide what to commit (before asking for a message)
  # -----------------------------
  local has_staged has_unstaged untracked
  has_staged=$(git diff --cached --name-only 2>/dev/null)
  has_unstaged=$(git diff --name-only 2>/dev/null)
  # ls-files only looks below the current directory; 'git add -A' stages the whole repository
  untracked=$(git -C "$(git rev-parse --show-toplevel)" ls-files --others --exclude-standard 2>/dev/null)

  # mode: staged | all | none (amend without new changes)
  local mode
  if [[ "$staged_only" == true ]]; then
    if [[ -z "$has_staged" && "$amend_mode" == false ]]; then
      print_error "No staged changes to commit."
      return 1
    fi
    mode="staged"
  elif [[ -n "$has_staged" && ( -n "$has_unstaged" || -n "$untracked" ) ]]; then
    echo "You have both staged and unstaged changes."
    local choice="s"
    if [[ "${GITBASH_ASSUME_YES:-}" != "1" ]]; then
      gb_choice choice "Commit [s]taged only or [a]ll changes? (S/a):" "sa" "s"
    fi
    if [[ "$choice" == "a" ]]; then mode="all"; else mode="staged"; fi
  elif [[ -n "$has_staged" ]]; then
    mode="staged"
  elif [[ -n "$has_unstaged" || -n "$untracked" ]]; then
    mode="all"
  elif [[ "$amend_mode" == true ]]; then
    mode="none"
  else
    echo "Nothing to commit - working tree clean."
    return 1
  fi

  # List new files before staging everything, so secrets don't slip in unnoticed
  if [[ "$mode" == "all" && -n "$untracked" ]]; then
    echo "New (untracked) files that will be added:"
    printf '%s\n' "$untracked" | sed 's/^/  + /'
    if ! gb_confirm "Add these files to the commit?" y; then
      echo "Commit cancelled. Stage what you want and use 'commit -s', or add files to .gitignore."
      return 1
    fi
  fi

  # -----------------------------
  # 2. Commit message
  # -----------------------------
  if [[ -z "$msg" && ( "$amend_mode" == false || "$show_prefix_menu" == true ) ]]; then
    prompt_read "Commit message: " msg
  fi
  if [[ -z "$msg" && "$amend_mode" == false ]]; then
    print_error "Empty commit message - commit cancelled."
    return 1
  fi

  if [[ "$show_prefix_menu" == true ]]; then
    if [[ -z "$msg" ]]; then
      print_error "Empty commit message - commit cancelled."
      return 1
    fi
    require_fzf || return 1

    local type_options="feat     - A new feature
fix      - A bug fix
docs     - Documentation only changes
style    - Code style changes (formatting, whitespace)
refactor - Code change that neither fixes nor adds a feature
perf     - Performance improvement
test     - Adding or fixing tests
build    - Build system or dependency changes
ci       - CI/CD configuration changes
chore    - Other changes that don't modify src/test files"

    local selected_type
    selected_type=$(run_fzf --prompt="Commit type > " \
              -i \
              --reverse \
              --border \
              --header="Select conventional commit type" \
              --no-multi \
              <<< "$type_options"
    ) || true

    if [[ -z "$selected_type" ]]; then
      echo "Commit cancelled."
      return 0
    fi

    msg="${selected_type%% *}: ${msg}"
    print_info "Commit message: $msg"
  fi

  # -----------------------------
  # 3. Commit
  # -----------------------------
  local commit_args=()
  if [[ "$amend_mode" == true ]]; then
    commit_args+=("--amend")
  fi
  if [[ -n "$msg" ]]; then
    commit_args+=("-m" "$msg")
  else
    commit_args+=("--no-edit")
  fi

  if [[ "$mode" == "all" ]]; then
    if ! git add -A; then
      print_error "Failed to stage changes."
      return 1
    fi
  fi

  if ! git commit "${commit_args[@]}"; then
    print_error "Commit failed."
    return 1
  fi

  # -----------------------------
  # 4. Push
  # -----------------------------
  if [[ "$should_push" == true ]]; then
    local push_args=()
    [[ "$amend_mode" == true ]] && push_args+=("--amend")
    [[ "$force_with_lease" == true ]] && push_args+=("--force-with-lease")
    gb_sync_and_push ${push_args[@]+"${push_args[@]}"} || return 1
  fi
  return 0
}
