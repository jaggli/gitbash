#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Abort an unfinished merge, rebase, cherry-pick, revert or am
_reset_repo_abort_operations() {
  local path
  if [[ -d "$(git rev-parse --git-path rebase-merge)" || -d "$(git rev-parse --git-path rebase-apply)" ]]; then
    path=$(git rev-parse --git-path rebase-apply)
    if [[ -f "$path/applying" ]]; then
      git am --abort >/dev/null 2>&1
    else
      git rebase --abort >/dev/null 2>&1
    fi
  fi
  [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]] && git merge --abort >/dev/null 2>&1
  [[ -f "$(git rev-parse --git-path CHERRY_PICK_HEAD)" ]] && git cherry-pick --abort >/dev/null 2>&1
  [[ -f "$(git rev-parse --git-path REVERT_HEAD)" ]] && git revert --abort >/dev/null 2>&1
  return 0
}

# Reset the current branch to its state on the remote and delete all
# untracked and ignored files, like a fresh clone
reset-repo() {
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        gb_help << 'EOF_HELP'
Usage: reset-repo [OPTIONS]

Reset the current branch like a fresh clone: discard all local changes and
unpushed commits, and delete untracked and ignored files (build output,
node_modules, ...).

Options:
  -n, --dry-run   Only show what would be reset and deleted
  -y, --yes       Don't ask for confirmation
  -h, --help      Show this help message

Behavior:
  - Fetches the configured remote (GITBASH_REMOTE, default: origin) and resets
    the branch to <remote>/<branch>; a branch that is not on the remote keeps
    its commits and only loses the local changes
  - Aborts an unfinished merge, rebase, cherry-pick or revert first
  - Keeps files matching GITBASH_RESET_KEEP (space-separated .gitignore
    patterns, e.g. '.env .idea/'), .gitbashrc-user and nested repositories
  - Stashes and other branches are not touched
  - Commits that are lost can be recovered with 'git reflog' for a while

Examples:
  $ reset-repo --dry-run
  $ reset-repo

EOF_HELP
        return 0
        ;;
      -n|--dry-run)
        dry_run=true
        shift
        ;;
      -y|--yes)
        export GITBASH_ASSUME_YES=1
        shift
        ;;
      *)
        print_error "Unknown argument: $1"
        echo "Usage: reset-repo [--dry-run] [--yes]" >&2
        return 1
        ;;
    esac
  done

  require_git_repo || return 1

  local repo_root
  repo_root=$(git rev-parse --show-toplevel) || return 1
  cd "$repo_root" || return 1

  # During a rebase HEAD is detached; the branch is the one being rebased
  local branch="" head_name
  for head_name in rebase-merge/head-name rebase-apply/head-name; do
    head_name=$(git rev-parse --git-path "$head_name")
    if [[ -f "$head_name" ]]; then
      branch=$(cat "$head_name")
      branch="${branch#refs/heads/}"
      break
    fi
  done
  if [[ -z "$branch" ]] && ! branch=$(gb_current_branch); then
    print_error "Detached HEAD: check out a branch first."
    return 1
  fi

  local remote target
  remote=$(gb_remote)
  if ! git remote get-url "$remote" >/dev/null 2>&1; then
    print_error "No remote '$remote' configured."
    return 1
  fi
  print_info "Fetching '$remote'..."
  if ! git fetch --quiet --prune "$remote"; then
    print_error "Failed to fetch '$remote'."
    return 1
  fi
  if git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
    target="$remote/$branch"
  else
    target="$branch"
    print_warning "'$branch' is not on '$remote': keeping its commits, only local changes are discarded."
  fi

  # Patterns of files to keep (git clean -e); .gitbashrc-user is always kept
  local -a keep clean_args
  local pattern
  IFS=' ' read -r -a keep <<< "${GITBASH_RESET_KEEP:-}"
  keep+=(".gitbashrc-user")
  clean_args=(-d -x)
  for pattern in "${keep[@]}"; do
    [[ -n "$pattern" ]] && clean_args+=(-e "$pattern")
  done

  # What would be lost
  local lost_commits changes untracked
  lost_commits=$(git log --oneline "$target..refs/heads/$branch")
  changes=$(git status --porcelain --untracked-files=no)
  untracked=$(git clean -n "${clean_args[@]}")

  local head_commit
  head_commit=$(git rev-parse "refs/heads/$branch")
  if [[ -z "$lost_commits" && -z "$changes" && -z "$untracked" &&
        "$(git rev-parse HEAD)" == "$(git rev-parse "$target")" ]]; then
    _reset_repo_abort_operations
    print_success "'$branch' is already like a fresh clone of '$target'."
    return 0
  fi

  echo "Resetting '$branch' to '$target':"
  if [[ -n "$lost_commits" ]]; then
    echo
    print_warning "$(printf '%s\n' "$lost_commits" | wc -l | tr -d ' ') unpushed commit(s) will be removed from '$branch':"
    printf '%s\n' "$lost_commits" | sed 's/^/    /'
  fi
  if [[ -n "$changes" ]]; then
    echo
    echo "Local changes to discard:"
    printf '%s\n' "$changes" | sed 's/^/    /'
  fi
  if [[ -n "$untracked" ]]; then
    echo
    echo "Untracked and ignored files to delete:"
    printf '%s\n' "$untracked" | sed 's/^Would remove /    /'
  fi
  if [[ ${#keep[@]} -gt 1 ]]; then
    echo
    echo "Kept (GITBASH_RESET_KEEP): ${GITBASH_RESET_KEEP}"
  fi
  echo

  if [[ "$dry_run" == true ]]; then
    print_info "Dry run - nothing was changed."
    return 0
  fi

  if ! gb_confirm "Reset '$branch' and delete these files?" n; then
    print_info "Aborted - nothing was changed."
    return 1
  fi

  _reset_repo_abort_operations
  if [[ "$(gb_current_branch)" != "$branch" ]] && ! git switch --quiet --force "$branch"; then
    print_error "Failed to check out '$branch'."
    return 1
  fi
  if ! git reset --quiet --hard "$target"; then
    print_error "Failed to reset '$branch' to '$target'."
    return 1
  fi
  if ! git clean -q -f "${clean_args[@]}"; then
    print_error "Failed to delete untracked files."
    return 1
  fi
  if [[ -f .gitmodules ]]; then
    git submodule update --init --recursive --force --quiet ||
      print_warning "Failed to update submodules."
  fi

  print_success "'$branch' is now like a fresh clone of '$target'."
  if [[ -n "$lost_commits" ]]; then
    print_info "Removed commits can be recovered with 'git reflog' (previous HEAD: ${head_commit:0:12})."
  fi
}
