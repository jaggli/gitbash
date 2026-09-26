#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Web URL for creating a pull/merge request for a branch
_pr_create_url() {
  local base="$1" branch="$2" encoded
  encoded=$(gb_urlencode "$branch")
  case "$base" in
    *gitlab*)
      echo "$base/-/merge_requests/new?merge_request%5Bsource_branch%5D=$encoded"
      ;;
    *bitbucket.org/*)
      echo "$base/pull-requests/new?source=$encoded"
      ;;
    *dev.azure.com/*|*visualstudio.com/*)
      echo "$base/pullrequestcreate?sourceRef=$encoded"
      ;;
    *)
      echo "$base/compare/$encoded?expand=1"
      ;;
  esac
}

# Open the current branch's pull request (or the page to create one)
pr() {
  local should_push=false
  local print_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        gb_help << 'EOF'
Usage: pr [OPTIONS]

Open the current branch's pull request in your browser.
If no pull request exists yet, opens the page to create one.

Options:
  -p, --push    Push the current branch before opening
  --print       Print the URL instead of opening it
  -y, --yes     Don't ask for confirmations
  -h, --help    Show this help message

Behavior:
  - Uncommitted changes: offers to commit them first (via 'commit')
  - Branch not on the remote yet: offers to push it
  - With the GitHub CLI (gh) installed and logged in, an existing PR is opened directly
  - Otherwise opens the create page for the hosting service:
      GitHub / GitHub Enterprise   <repo>/compare/<branch>?expand=1
      GitLab                       <repo>/-/merge_requests/new?...
      Bitbucket                    <repo>/pull-requests/new?source=<branch>
      Azure DevOps                 <repo>/pullrequestcreate?sourceRef=<branch>
  - Works with SSH and HTTPS remotes; credentials in the remote URL are never used
  - Opens the browser (macOS, Linux, WSL, Git Bash on Windows), otherwise prints the URL

Examples:
  $ pr
  $ pr -p
  $ pr --print

EOF
        return 0
        ;;
      -p|--push)
        should_push=true
        shift
        ;;
      --print)
        print_only=true
        shift
        ;;
      -y|--yes)
        export GITBASH_ASSUME_YES=1
        shift
        ;;
      *)
        print_error "Unknown argument: $1"
        echo "Usage: pr [-p|--push] [--print] [-y|--yes]" >&2
        return 1
        ;;
    esac
  done

  require_git_repo || return 1

  local remote remote_url branch base
  remote=$(gb_remote)
  if ! remote_url=$(git config --get "remote.$remote.url"); then
    print_error "No remote '$remote' found."
    return 1
  fi
  if ! branch=$(gb_current_branch); then
    print_error "Detached HEAD: check out a branch first."
    return 1
  fi
  if ! base=$(gb_web_url "$remote_url"); then
    print_error "Don't know how to open '$remote_url' in a browser."
    return 1
  fi

  # -----------------------------
  # 1. Uncommitted changes
  # -----------------------------
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "You have uncommitted changes or untracked files."
    if [[ "$should_push" == true ]] || gb_confirm "Commit them first?" y; then
      local before after
      before=$(git rev-parse --verify --quiet HEAD || true)
      if ! gb_run commit; then
        print_error "Commit cancelled or failed. Not opening the pull request."
        return 1
      fi
      after=$(git rev-parse --verify --quiet HEAD || true)
      if [[ "$after" != "$before" && "$should_push" == false ]]; then
        gb_confirm "Push the new commit to '$remote'?" y && should_push=true
      fi
    else
      echo "Continuing without committing..."
    fi
  fi

  # -----------------------------
  # 2. Make sure the branch exists on the remote
  # -----------------------------
  if [[ "$should_push" == false ]]; then
    local on_remote
    on_remote=$(git ls-remote --heads "$remote" "refs/heads/$branch" 2>/dev/null || true)
    if [[ -z "$on_remote" ]]; then
      print_warning "Branch '$branch' is not on '$remote' yet."
      gb_confirm "Push it now?" y && should_push=true
    fi
  fi

  if [[ "$should_push" == true ]]; then
    gb_sync_and_push || return 1
  fi

  # -----------------------------
  # 3. Open existing PR with gh, else the create page
  # -----------------------------
  if [[ "$print_only" == false && "$base" != *gitlab* && "$base" != *bitbucket.org/* ]] &&
     command -v gh >/dev/null 2>&1; then
    if GH_PROMPT_DISABLED=1 gh pr view "$branch" --web >/dev/null 2>&1; then
      print_success "Opened the pull request for '$branch'."
      return 0
    fi
  fi

  local url
  url=$(_pr_create_url "$base" "$branch")
  if [[ "$print_only" == true ]]; then
    echo "$url"
  else
    gb_open_url "$url"
  fi
}
