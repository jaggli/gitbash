#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Open the repository's web page
repo() {
  local print_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        gb_help << 'EOF_HELP'
Usage: repo [OPTIONS]

Open the repository's web page in your browser.

Options:
  --print       Print the URL instead of opening it
  -h, --help    Show this help message

Behavior:
  - Uses the URL of the configured remote (GITBASH_REMOTE, default: origin)
  - With the GitHub CLI (gh) installed and logged in, opens it with 'gh repo view --web'
  - Otherwise opens the URL derived from the remote
    (GitHub, GitHub Enterprise, GitLab, Bitbucket, Azure DevOps)
  - Works with SSH and HTTPS remotes; credentials in the remote URL are never used
  - Opens the browser with 'open' (macOS) or 'xdg-open' (Linux), otherwise prints the URL

Examples:
  $ repo
  $ repo --print

EOF_HELP
        return 0
        ;;
      --print)
        print_only=true
        shift
        ;;
      *)
        print_error "Unknown argument: $1"
        echo "Usage: repo [--print]" >&2
        return 1
        ;;
    esac
  done

  require_git_repo || return 1

  local remote remote_url url
  remote=$(gb_remote)
  if ! remote_url=$(git config --get "remote.$remote.url"); then
    print_error "No remote '$remote' found."
    return 1
  fi
  if ! url=$(gb_web_url "$remote_url"); then
    print_error "Don't know how to open '$remote_url' in a browser."
    return 1
  fi

  if [[ "$print_only" == true ]]; then
    echo "$url"
    return 0
  fi

  if [[ "$url" != *gitlab* && "$url" != *bitbucket.org/* && "$url" != *dev.azure.com/* && "$url" != *visualstudio.com/* ]] &&
     command -v gh >/dev/null 2>&1; then
    if GH_PROMPT_DISABLED=1 gh repo view "$url" --web >/dev/null 2>&1; then
      print_success "Opened $url"
      return 0
    fi
  fi

  gb_open_url "$url"
}
