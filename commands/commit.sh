#!/usr/bin/env bash
# shellcheck disable=SC2155

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Stage all changes and commit with a message.
# If no commit message argument is given, prompt the user for one.
commit() {
  local should_push=false
  local staged_only=false
  local amend_mode=false
  local show_prefix_menu=false
  local msg_parts=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        cat << 'EOF'
Usage: commit [MESSAGE] [OPTIONS]

Stage all changes (git add -A) and commit with a message.

Options:
  -p, --push      Push to origin after successful commit
  -s, --staged    Commit only staged changes (skip prompt, ignore unstaged)
  -a, --amend     Amend the last commit instead of creating a new one
  -t, --type      Show conventional commit type selector (feat, fix, docs, etc.)
  -h, --help      Show this help message

Conventional Commit Types (with --type):
  feat:     A new feature
  fix:      A bug fix
  docs:     Documentation only changes
  style:    Code style changes (formatting, whitespace)
  refactor: Code change that neither fixes a bug nor adds a feature
  perf:     Performance improvement
  test:     Adding or fixing tests
  build:    Build system or dependency changes
  ci:       CI/CD configuration changes
  chore:    Other changes that don't modify src or test files

Interactive mode (no message):
  $ commit
  Commit message: fix login bug
  [main 1a2b3c4] fix login bug
   1 file changed, 5 insertions(+), 2 deletions(-)

With message argument:
  $ commit implement new feature
  [main 5d6e7f8] implement new feature
   3 files changed, 42 insertions(+), 8 deletions(-)

With type selector:
  $ commit -t fix broken tests
  # Shows type menu, then commits as "fix: broken tests"

Amend last commit:
  $ commit --amend fix typo in docs
  [main abc123] fix typo in docs
   1 file changed, 1 insertion(+)

With push option:
  $ commit update documentation -p
  [main 9a8b7c6] update documentation
   1 file changed, 10 insertions(+), 3 deletions(-)
  Pushing 'main' to origin...
  ✓ Successfully pushed 'main' to origin.

Examples:
  commit                                    # Interactive mode
  commit add user validation                # Quick commit
  commit refactor auth module --push        # Commit and push
  commit -p update dependencies             # Commit and push (short flag)
  commit -s -p fix bug                      # Commit only staged and push
  commit -t add user endpoint               # Conventional commit with type menu
  commit --amend fix typo                   # Amend last commit

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
      -*)
        echo "Unknown option: $1"
        echo "Usage: commit [message] [-p|--push] [-s|--staged] [-a|--amend] [-t|--type]"
        return 1
        ;;
      *)
        # Collect all non-flag arguments as message parts
        msg_parts+=("$1")
        shift
        ;;
    esac
  done

  # Join message parts with spaces (handle empty array for set -u)
  local msg=""
  if [[ ${#msg_parts[@]} -gt 0 ]]; then
    msg="${msg_parts[*]}"
  fi

  # If no commit message was provided...
  if [ -z "$msg" ]; then
    # Prompt the user for a commit message (no newline, no extra spaces)
    prompt_read "Commit message: " msg
  fi

  # Show conventional commit type menu if requested
  if [[ "$show_prefix_menu" == true ]]; then
    if ! command -v fzf >/dev/null 2>&1; then
      print_error "fzf is required for type selector. Install it or provide message directly."
      return 1
    fi

    local type_options
    type_options=$(cat << 'TYPES'
feat     - A new feature
fix      - A bug fix
docs     - Documentation only changes
style    - Code style changes (formatting, whitespace)
refactor - Code change that neither fixes nor adds a feature
perf     - Performance improvement
test     - Adding or fixing tests
build    - Build system or dependency changes
ci       - CI/CD configuration changes
chore    - Other changes that don't modify src/test files
TYPES
)

    local selected_type
    selected_type=$(echo "$type_options" | fzf --prompt="Commit type > " \
              -i \
              --reverse \
              --border \
              --header="Select conventional commit type" \
              --no-multi \
              --bind=enter:accept \
    ) </dev/tty || true

    if [[ -z "$selected_type" ]]; then
      echo "Aborted."
      return 1
    fi

    # Extract just the type keyword (first word)
    local type_keyword
    type_keyword=$(echo "$selected_type" | awk '{print $1}')
    
    # Prepend to message
    msg="${type_keyword}: ${msg}"
    print_info "Commit message: $msg"
  fi

  # Build commit flags
  local commit_flags=()
  if [[ "$amend_mode" == true ]]; then
    commit_flags+=("--amend")
  fi

  # Check if there are staged changes
  local has_staged
  has_staged=$(git diff --cached --name-only)
  
  local has_unstaged
  has_unstaged=$(git diff --name-only)

  # For amend mode, we might not need new changes
  if [[ "$amend_mode" == true ]]; then
    if [[ -z "$has_staged" && -z "$has_unstaged" ]]; then
      print_info "Amending commit message only..."
      git commit --amend -m "$msg"
    else
      # Has changes to add
      if [[ "$staged_only" == true ]]; then
        if [[ -z "$has_staged" ]]; then
          print_info "Amending commit message only (no staged changes)..."
          git commit --amend -m "$msg"
        else
          print_info "Amending with staged changes..."
          git commit --amend -m "$msg"
        fi
      else
        print_info "Amending with all changes..."
        git add -A && git commit --amend -m "$msg"
      fi
    fi
  # If --staged flag is set, only commit staged changes
  elif [[ "$staged_only" == true ]]; then
    if [[ -z "$has_staged" ]]; then
      echo "No staged changes to commit."
      return 1
    fi
    echo "Committing staged changes only..."
    git commit -m "$msg"
  # If there are both staged and unstaged changes, ask what to commit
  elif [[ -n "$has_staged" && -n "$has_unstaged" ]]; then
    echo
    echo "You have both staged and unstaged changes."
    echo
    prompt_read "Commit [s]taged only, or [a]ll changes? (s/a): " commit_choice
    
    case "$commit_choice" in
      [sS])
        # Commit only staged changes
        echo "Committing staged changes only..."
        git commit -m "$msg"
        ;;
      [aA]|*)
        # Stage all and commit
        echo "Staging all changes and committing..."
        git add -A && git commit -m "$msg"
        ;;
    esac
  elif [[ -n "$has_staged" ]]; then
    # Only staged changes exist
    echo "Committing staged changes..."
    git commit -m "$msg"
  else
    # No staged changes, stage all and commit
    git add -A && git commit -m "$msg"
  fi

  # Push if requested and commit was successful
  if [[ $? -eq 0 && "$should_push" == true ]]; then
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Check if remote has updates and pull first
    git fetch origin "$current_branch" 2>/dev/null
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null)
    
    if [[ -n "$remote_commit" && "$local_commit" != "$remote_commit" ]]; then
      # Check if we're behind the remote
      if git merge-base --is-ancestor "$local_commit" "$remote_commit" 2>/dev/null; then
        print_info "Remote has updates. Pulling first..."
        git pull --rebase origin "$current_branch"
        if [[ $? -ne 0 ]]; then
          print_warning "Failed to pull remote changes. Please resolve conflicts and try again."
          return 1
        fi
        print_success "Pulled latest changes."
      elif ! git merge-base --is-ancestor "$remote_commit" "$local_commit" 2>/dev/null; then
        # Branches have diverged
        print_info "Remote has diverged. Pulling with rebase..."
        git pull --rebase origin "$current_branch"
        if [[ $? -ne 0 ]]; then
          print_warning "Failed to pull remote changes. Please resolve conflicts and try again."
          return 1
        fi
        print_success "Rebased on latest changes."
      fi
    fi
    
    print_info "Pushing '$current_branch' to origin..."
    git push origin "$current_branch"
    if [[ $? -eq 0 ]]; then
      print_success "Successfully pushed '$current_branch' to origin."
    else
      print_warning "Failed to push '$current_branch' to origin."
      return 1
    fi
  fi
}
