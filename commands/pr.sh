## pr opens the current pr, if in repo
pr() {
  local should_push=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        cat << 'EOF'
Usage: pr [OPTIONS]

Open the current branch's pull request in your browser.
If no PR exists, opens GitHub's compare page to create one.

Options:
  -p, --push    Push current branch to origin before opening PR
  -h, --help    Show this help message

Behavior:
  - Must be run inside a git repository
  - Uses the 'origin' remote URL
  - Opens a compare URL for the current branch
  - Automatically converts SSH URLs to HTTPS

Examples:
  $ pr
  # Opens: https://github.com/user/repo/compare/feature-branch?expand=1

  $ git checkout feature/helix/LOVE-123-fix-bug
  $ pr
  # Opens: https://github.com/user/repo/compare/feature/helix/LOVE-123-fix-bug?expand=1

  # Push before opening PR
  $ pr -p
  Pushing 'feature-branch' to origin...
  ✓ Successfully pushed 'feature-branch' to origin.
  # Opens: https://github.com/user/repo/compare/feature-branch?expand=1

Notes:
  - Works with both SSH and HTTPS remote URLs
  - Opens in your default browser using the 'open' command
  - Branch name is automatically URL-encoded by the browser

EOF
        return 0
        ;;
      -p|--push)
        should_push=true
        shift
        ;;
      -*)
        echo "Unknown option: $1"
        echo "Usage: pr [-p|--push]"
        return 1
        ;;
      *)
        echo "Unknown argument: $1"
        echo "Usage: pr [-p|--push]"
        return 1
        ;;
    esac
  done

  # Ensure we're inside a Git repo
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a git repository."
    return 1
  fi

  # Check for uncommitted changes
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "You have uncommitted changes."
    echo ""
    
    # Source _utils.sh for prompt_read
    if ! declare -f prompt_read >/dev/null 2>&1; then
      SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
      source "$SOURCE_DIR/_utils.sh"
    fi
    
    prompt_read "Would you like to commit them first? (Y/n): " commit_answer
    case "$commit_answer" in
      [nN][oO]|[nN])
        echo "Continuing without committing..."
        ;;
      *)
        # Find gitbash root directory (two levels up from commands/)
        SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
        GITBASH_ROOT="$(cd "$SOURCE_DIR/.." && pwd)"
        
        # Run commit with stage flag (without push) using local gitbash
        "$GITBASH_ROOT/bin/gitbash" commit -s
        if [[ $? -ne 0 ]]; then
          echo "Commit cancelled or failed. Aborting PR creation."
          return 1
        fi
        
        # If -p wasn't specified, offer to push the fresh commit
        if [[ "$should_push" != true ]]; then
          echo ""
          prompt_read "Push the fresh commit to origin? (Y/n): " push_answer
          case "$push_answer" in
            [nN][oO]|[nN])
              echo "Continuing without pushing..."
              ;;
            *)
              should_push=true
              ;;
          esac
        fi
        ;;
    esac
    echo ""
  fi

  # Remote URL (e.g. git@github.com:user/repo.git or https://github.com/user/repo.git)
  remote=$(git config --get remote.origin.url)

  if [[ -z "$remote" ]]; then
    echo "No remote 'origin' found."
    return 1
  fi

  # Convert SSH URLs to HTTPS URLs
  remote_https=$remote
  remote_https=${remote_https/git@github.com:/https://github.com/}
  remote_https=${remote_https%.git}

  # Current branch
  branch=$(git rev-parse --abbrev-ref HEAD)

  # Push if requested
  if [[ "$should_push" == true ]]; then
    # Check if remote has updates and pull first
    git fetch origin "$branch" 2>/dev/null
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/$branch" 2>/dev/null)
    
    if [[ -n "$remote_commit" && "$local_commit" != "$remote_commit" ]]; then
      # Check if we're behind the remote
      if git merge-base --is-ancestor "$local_commit" "$remote_commit" 2>/dev/null; then
        echo "Remote has updates. Pulling first..."
        git pull --rebase origin "$branch"
        if [[ $? -ne 0 ]]; then
          echo "⚠ Failed to pull remote changes. Please resolve conflicts and try again."
          return 1
        fi
        echo "✓ Pulled latest changes."
      elif ! git merge-base --is-ancestor "$remote_commit" "$local_commit" 2>/dev/null; then
        # Branches have diverged
        echo "Remote has diverged. Pulling with rebase..."
        git pull --rebase origin "$branch"
        if [[ $? -ne 0 ]]; then
          echo "⚠ Failed to pull remote changes. Please resolve conflicts and try again."
          return 1
        fi
        echo "✓ Rebased on latest changes."
      fi
    fi
    
    echo "Pushing '$branch' to origin..."
    git push origin "$branch"
    if [[ $? -eq 0 ]]; then
      echo "✓ Successfully pushed '$branch' to origin."
    else
      echo "⚠ Failed to push '$branch' to origin."
      return 1
    fi
  fi

  # Construct compare URL
  url="$remote_https/compare/$branch?expand=1"

  # Open in browser
  open "$url"
}
