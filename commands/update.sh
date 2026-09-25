#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Returns 0 if the branch is checked out in any worktree
_update_is_checked_out() {
  git worktree list --porcelain 2>/dev/null | grep -qxF "branch refs/heads/$1"
}

# Update the current branch with the latest version of the base branch
update() {
  local should_push=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        gb_help << 'EOF'
Usage: update [OPTIONS]

Merge the latest base branch (main/master) from the remote into the current branch.

Options:
  -p, --push    Push the branch after a successful merge
  -y, --yes     Don't ask for confirmations
  -h, --help    Show this help message

Behavior:
  1. Detects the base branch (GITBASH_BASE_BRANCH, the remote's HEAD, main or master)
  2. With local changes, asks: [c]ommit them, [s]tash them (restored afterwards) or [a]bort
  3. Fetches the base branch and merges '<remote>/<base>' into your branch
  4. Also fast-forwards your local base branch when it isn't checked out anywhere
  5. On conflicts, lists the files and opens your merge tool (GITBASH_MERGE_COMMAND)
  6. With --push, pushes the result (asks before rebasing if the remote diverged)

  On the base branch itself, fast-forwards it from the remote instead.

Configuration (run 'gitbash --config'):
  GITBASH_MERGE_COMMAND   Merge tool, e.g. "fork", "code", "gitkraken" (default: fork).
                          Only read from ~/.gitbashrc and .gitbashrc-user.

Examples:
  $ update
  $ update --push

EOF
        return 0
        ;;
      -p|--push)
        should_push=true
        shift
        ;;
      -y|--yes)
        GITBASH_ASSUME_YES=1
        shift
        ;;
      *)
        print_error "Unknown option: $1"
        echo "Usage: update [-p|--push] [-y|--yes]" >&2
        return 1
        ;;
    esac
  done

  require_git_repo || return 1

  local remote current_branch base_branch
  remote=$(gb_remote)
  if ! current_branch=$(gb_current_branch); then
    print_error "Detached HEAD: check out a branch first."
    return 1
  fi
  if ! base_branch=$(gb_base_branch); then
    print_error "Could not detect the base branch. Set GITBASH_BASE_BRANCH with 'gitbash --config'."
    return 1
  fi

  # -----------------------------
  # On the base branch: just fast-forward it
  # -----------------------------
  if [[ "$current_branch" == "$base_branch" ]]; then
    print_info "Pulling latest '$base_branch' from '$remote'..."
    if git pull --ff-only "$remote" "$base_branch"; then
      print_success "'$base_branch' is up to date."
      return 0
    fi
    print_error "Could not fast-forward '$base_branch'. It has local commits or local changes that block the update."
    return 1
  fi

  # -----------------------------
  # Local changes: commit, stash or abort
  # -----------------------------
  local stashed=false
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "You have uncommitted changes:"
    git status --short
    echo
    local choice="c"
    gb_choice choice "[c]ommit them, [s]tash them for the update, or [a]bort? (C/s/a):" "csa" "c"
    case "$choice" in
      c)
        if ! gb_run commit; then
          print_error "Commit failed or was cancelled. Update aborted."
          return 1
        fi
        ;;
      s)
        if ! git stash push --include-untracked --quiet -m "gitbash update: auto-stash"; then
          print_error "Could not stash the changes. Update aborted."
          return 1
        fi
        stashed=true
        print_info "Changes stashed. They are restored after the update."
        ;;
      *)
        echo "Update aborted."
        return 1
        ;;
    esac
  fi

  # -----------------------------
  # Fetch and merge
  # -----------------------------
  print_info "Fetching latest '$base_branch' from '$remote'..."
  if ! git fetch --quiet "$remote" "+refs/heads/$base_branch:refs/remotes/$remote/$base_branch"; then
    print_error "Could not fetch '$base_branch' from '$remote'."
    [[ "$stashed" == true ]] && git stash pop --quiet
    return 1
  fi

  # Keep the local base branch current as well (only if it can fast-forward)
  if git show-ref --verify --quiet "refs/heads/$base_branch" && ! _update_is_checked_out "$base_branch"; then
    git fetch --quiet . "refs/remotes/$remote/$base_branch:refs/heads/$base_branch" 2>/dev/null ||
      print_warning "Local '$base_branch' has its own commits; it was not fast-forwarded."
  fi

  print_info "Merging '$remote/$base_branch' into '$current_branch'..."
  if git merge --no-edit "$remote/$base_branch"; then
    print_success "'$current_branch' is up to date with '$base_branch'."
  else
    local conflicts
    conflicts=$(git diff --name-only --diff-filter=U)
    if [[ -z "$conflicts" ]]; then
      print_error "Merge failed (see git's message above)."
      if [[ "$stashed" == true ]]; then
        git stash pop --quiet || print_warning "Your changes are still in the stash: run 'git stash pop'."
      fi
      return 1
    fi

    print_warning "Merge conflicts in:"
    printf '%s\n' "$conflicts" | sed 's/^/  /'
    echo "Resolve them and run 'git commit', or cancel with 'git merge --abort'."
    [[ "$stashed" == true ]] && echo "Your stashed changes are kept: run 'git stash pop' when done."

    local -a merge_tool
    read -r -a merge_tool <<< "${GITBASH_MERGE_COMMAND:-}"
    if [[ ${#merge_tool[@]} -gt 0 ]] && command -v "${merge_tool[0]}" >/dev/null 2>&1; then
      "${merge_tool[@]}" .
    fi
    return 1
  fi

  if [[ "$stashed" == true ]]; then
    if git stash pop --quiet; then
      print_info "Restored your stashed changes."
    else
      print_warning "Restoring your changes caused conflicts. They are still in the stash (git stash list)."
    fi
  fi

  if [[ "$should_push" == true ]]; then
    gb_sync_and_push || return 1
  fi
  return 0
}
