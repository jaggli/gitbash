#!/usr/bin/env bash
## switch selects and switches git branches using fzf
# shellcheck shell=bash
# shellcheck disable=SC2155

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Select and switch to a branch using fzf
switch() {
  # -----------------------------
  # 0. Check for help/version flag
  # -----------------------------
  if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
    echo "gitbash ${FUNCNAME[0]} v$VERSION"
    return 0
  fi
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat << 'EOF'
Usage: switch [FILTER...]

Select a git branch using fzf and switch to it.

Arguments:
  FILTER...     Optional search filter words to pre-fill fzf (joined with spaces)

Options:
  -h, --help    Show this help message

Behavior:
  - Lists both local and remote branches
  - Remote branches are hidden if a local branch with the same name exists
  - Uses fzf for interactive selection
  - Automatically switches to the selected branch
  - For remote branches, creates a local tracking branch if needed
  - Current branch is highlighted with an asterisk (*)

Examples:
  $ switch
  # Opens fzf with list of branches, select one to switch

  $ switch captcha
  # Opens fzf with 'captcha' pre-filled as filter

  $ switch LOVE-123
  # Opens fzf filtering for branches containing 'LOVE-123'

  $ switch update figma guidelines
  # Opens fzf with 'update figma guidelines' pre-filled as filter

Requirements:
  - Must be in a git repository
  - fzf must be installed

EOF
    return 0
  fi

  # -----------------------------
  # 1. Check prerequisites
  # -----------------------------
  require_git_repo || return 1
  require_fzf || return 1

  # -----------------------------
  # 2. Get current branch and filter
  # -----------------------------
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  
  local filter="$*"

  # -----------------------------
  # 3. List branches and select with fzf
  # -----------------------------
  # Get local branches
  local local_branches
  local_branches=$(git branch --format='%(refname:short)')
  # Get merged local branches (merged into HEAD) in a portable way
  local merged_local_branches
  merged_local_branches=$(git branch --merged | sed 's/^..//' | sed '/^$/d' || true)
  
  # Get remote branches, filter out those that already exist locally
  local remote_branches
  remote_branches=$(git branch -r --format='%(refname:short)' | grep -v 'HEAD' | grep -v '^origin$' | while read -r remote; do
    local_name="${remote#*/}"  # Remove origin/ prefix
    # Only include if no local branch with this name exists
    if ! echo "$local_branches" | grep -qx "$local_name"; then
      echo "$remote"
    fi
  done || true)
  
  local selected_branch
  local branch_list
  branch_list=$(
    {
      # List local branches, marking merged ones as 'merged:' (but keep current branch as local)
      echo "$local_branches" | while IFS= read -r lb; do
        # Skip empty lines
        [[ -z "$lb" ]] && continue
        if [[ "$lb" == "$current_branch" ]]; then
          echo "local: $lb"
        elif [[ "$lb" == "master" || "$lb" == "main" ]]; then
          # Keep main branches labelled as local
          echo "local: $lb"
        elif echo "$merged_local_branches" | grep -xq -- "${lb}" 2>/dev/null; then
          echo "merged: $lb"
        else
          echo "local: $lb"
        fi
      done
      # Spacer (only if there are remote branches to show)
      if [[ -n "$remote_branches" ]]; then
        echo "─────────────────────────────"
        # List filtered remote branches
        echo "$remote_branches" | sed 's/^/remote: /'
      fi
    }
  )

  # If no branches were found, bail out to avoid fzf listing files
  if [[ -z "$(echo "$branch_list" | sed -n '1p' || true)" ]]; then
    echo "No branches found in this repository."
    return 0
  fi

  # -----------------------------
  # 3b. Check for single match when filter is provided
  # -----------------------------
  if [[ -n "$filter" ]]; then
    # Filter branch list (case-insensitive), excluding spacer
    local matching_branches
    matching_branches=$(echo "$branch_list" | grep -iv '───' | grep -i "$filter" || true)
    local match_count
    match_count=$(echo "$matching_branches" | grep -c . 2>/dev/null || echo "0")
    # Ensure match_count is numeric
    [[ -z "$match_count" ]] && match_count=0
    
    if [[ "$match_count" == "1" ]]; then
      # Single match - skip fzf
      selected_branch="$matching_branches"
      print_info "Single match found, switching directly..."
    fi
    # If provided filter yields no matches, clear the query so fzf opens unfiltered
    if [[ "$match_count" == "0" ]]; then
      filter_for_fzf=""
    else
      filter_for_fzf="$filter"
    fi
  fi

  # -----------------------------
  # 3c. Use fzf if no single match
  # -----------------------------
  if [[ -z "$selected_branch" ]]; then
    # Write branch list to a temp file so fzf can reload after deletions
      branches_file=$(mktemp)
      printf '%s\n' "$branch_list" > "$branches_file"

    # Create a small helper script to delete the selected branch safely (asks for confirmation).
    delete_script=$(mktemp)
    cat > "$delete_script" <<'DEL_SH'
#!/usr/bin/env bash
line="$1"
branches_file="$2"

if [[ "$line" == *───* ]]; then
  echo "Spacer - not deletable"
  exit 0
fi

type="${line%%:*}"
branch="${line#*: }"

if [[ "$type" == "local" || "$type" == "merged" ]]; then
  # Ask for confirmation via the terminal (/dev/tty). Default answer is Yes when empty.
  while true; do
    printf "Delete local branch '%s'? [Y/n]: " "$branch" > /dev/tty
    read -r answer < /dev/tty
    case "$answer" in
      ''|[yY]|[yY][eE][sS])
        break
        ;;
      [nN]|[nN][oO])
        echo "Aborted deletion of $branch"
        exit 0
        ;;
      *)
        echo "Please answer y or n" > /dev/tty
        ;;
    esac
  done

  if git branch -D "$branch"; then
    echo "Deleted local $branch"
    awk -v l="$line" '$0!=l' "$branches_file" > "$branches_file".new && mv "$branches_file".new "$branches_file"
  else
    echo "Failed to delete $branch"
  fi
else
  echo "Remote branch deletion is disabled in this UI. Delete remote branches manually with: git push <remote> --delete <branch>"
  exit 0
fi
DEL_SH
    chmod +x "$delete_script"

    # Loop running fzf so we can handle delete keys via --expect and reload after deletion
    selected_branch=""
    while true; do
        fzf_out=$(
          fzf \
            --height=40% \
            --reverse \
            --border \
            --expect=enter,delete \
            --query="${filter_for_fzf:-$filter}" \
            -i \
            --preview="branch=\$(echo {} | sed 's/^[^:]*: //'); if [[ \"\$branch\" == *───* ]]; then echo 'Spacer - not selectable'; else git log --color=always -n 1 --format='%C(bold cyan)Author:%C(reset) %an%n%C(bold cyan)Date:%C(reset) %ar (%ad)%n%C(bold cyan)Message:%C(reset) %s%n' --date=format:'%Y-%m-%d %H:%M' \"\$branch\" 2>/dev/null && echo && git log --oneline --color=always -n 10 \"\$branch\" 2>/dev/null; fi" \
            --preview-window=right:50% \
            --header="[Enter] switch | [Del] delete (local only) | [Esc] exit | Current: $current_branch" \
            < "$branches_file"
        ) </dev/tty || true

      key_pressed=$(echo "$fzf_out" | head -n1)
      selection=$(echo "$fzf_out" | tail -n +2 | head -n1)

      # No selection or escape
      if [[ -z "$key_pressed" && -z "$selection" ]]; then
        selected_branch=""
        break
      fi

      if [[ "$key_pressed" == "enter" ]]; then
        selected_branch="$selection"
        break
      fi

      if [[ "$key_pressed" == "delete" ]]; then
        # perform deletion on the selected line and continue loop
        if [[ -n "$selection" ]]; then
          "$delete_script" "$selection" "$branches_file"
        fi
        continue
      fi

      # If there is a selection without a key, treat as accept
      if [[ -n "$selection" ]]; then
        selected_branch="$selection"
        break
      fi
    done

    # Clean up temp files
    rm -f "$delete_script" "$branches_file"
  fi

  # -----------------------------
  # 4. Handle selection
  # -----------------------------
  if [[ -z "$selected_branch" ]]; then
    echo "No branch selected."
    return 0
  fi

  # Ignore spacer selection
  if [[ "$selected_branch" == *───* ]]; then
    echo "Invalid selection."
    return 0
  fi

  # Extract branch type and name
  local branch_type="${selected_branch%%:*}"
  local branch_name="${selected_branch#*: }"

  # -----------------------------
  # 5. Switch to branch
  # -----------------------------
  local switch_success=false
  if [[ "$branch_type" == "local" || "$branch_type" == "merged" ]]; then
    # Switch to local branch
    echo "Switching to local branch: $branch_name"
    if git checkout "$branch_name"; then
      switch_success=true
    fi
  else
    # Handle remote branch
    local local_branch="${branch_name#*/}"  # Remove origin/ prefix
    
    # Check if local branch already exists
    if git show-ref --verify --quiet "refs/heads/$local_branch"; then
      echo "Switching to existing local branch: $local_branch"
      if git checkout "$local_branch"; then
        switch_success=true
      fi
    else
      echo "Creating local tracking branch: $local_branch (tracking $branch_name)"
      if git checkout -b "$local_branch" --track "$branch_name"; then
        switch_success=true
      fi
    fi
  fi

  if [[ "$switch_success" == true ]]; then
    print_success "Switched to branch: $(git rev-parse --abbrev-ref HEAD)"
    
    # -----------------------------
    # 6. Check if branch is behind upstream and offer to pull
    # -----------------------------
    local upstream behind_count
    upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
    
    if [[ -n "$upstream" ]]; then
      # Fetch to get latest info (silently)
      git fetch origin 2>/dev/null || true
      
      # Check how many commits we're behind
      behind_count=$(git rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")
      
      if [[ "$behind_count" -gt 0 ]]; then
        print_warning "Branch is $behind_count commit(s) behind '$upstream'"
        local pull_answer
        prompt_read "Pull latest changes? (Y/n): " pull_answer
        case "$pull_answer" in
          [nN][oO]|[nN])
            print_info "Skipped pulling. Run 'git pull' when ready."
            ;;
          *)
            if git pull; then
              print_success "Successfully pulled latest changes."
            else
              print_error "Pull failed. You may need to resolve conflicts."
              return 1
            fi
            ;;
        esac
      fi
    fi
  else
    print_error "Failed to switch branch."
    return 1
  fi
}
