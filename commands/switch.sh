#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Print the branch list for fzf: "<label>: <name>\t<type>\t<name>"
_switch_list_branches() {
  local current base="" base_ref merged="" name remote_name local_names
  current=$(gb_current_branch) || current=""
  if base=$(gb_base_branch 2>/dev/null); then
    base_ref=$(gb_base_ref "$base")
    merged=$(git for-each-ref --merged "$base_ref" --format='%(refname:short)' refs/heads 2>/dev/null)
  fi

  local_names=$(git for-each-ref --format='%(refname:short)' refs/heads)
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ "$name" != "$current" && "$name" != "$base" ]] && printf '%s\n' "$merged" | grep -qxF -- "$name"; then
      printf 'merged: %s\tlocal\t%s\n' "$name" "$name"
    else
      printf 'local: %s\tlocal\t%s\n' "$name" "$name"
    fi
  done <<< "$local_names"

  # Remote branches without a local branch of the same name
  local printed_spacer=false
  while IFS= read -r name; do
    # Skip symbolic refs like "origin" (origin/HEAD)
    [[ -z "$name" || "$name" != */* || "$name" == */HEAD ]] && continue
    remote_name="${name#*/}"
    printf '%s\n' "$local_names" | grep -qxF -- "$remote_name" && continue
    if [[ "$printed_spacer" == false ]]; then
      printf '─────────────────────────────\tspacer\t\n'
      printed_spacer=true
    fi
    printf 'remote: %s\tremote\t%s\n' "$name" "$name"
  done < <(git for-each-ref --format='%(refname:short)' refs/remotes)
}

# Delete the local branch of a list line (called from fzf via 'switch --delete-branch')
_switch_delete_branch() {
  local line="$1" type name current count
  type=$(printf '%s' "$line" | cut -f2)
  name=$(printf '%s' "$line" | cut -f3)
  current=$(gb_current_branch) || current=""

  _switch_pause() { prompt_read "Press Enter to continue..." _ || true; }

  if [[ "$type" != "local" ]]; then
    echo "Only local branches can be deleted here. Use 'stale' to delete remote branches."
    _switch_pause
    return 0
  fi
  if [[ "$name" == "$current" ]]; then
    print_warning "'$name' is the current branch - switch to another branch first."
    _switch_pause
    return 0
  fi
  if gb_is_protected "$name"; then
    print_warning "'$name' is protected (GITBASH_PROTECTED_BRANCHES)."
    _switch_pause
    return 0
  fi

  gb_confirm --strict "Delete local branch '$name'?" n || return 0
  if git branch -d "$name" >/dev/null 2>&1; then
    print_success "Deleted $name"
    return 0
  fi

  count=$(git rev-list --count "refs/heads/$name" --not --remotes "$(gb_base_ref "$(gb_base_branch 2>/dev/null || echo HEAD)")" 2>/dev/null || echo "?")
  print_warning "'$name' has $count commit(s) that are not merged or pushed:"
  git log --oneline -n 10 "refs/heads/$name" --not --remotes 2>/dev/null | sed 's/^/    /'
  if gb_confirm --strict "Force-delete '$name' and lose these commits?" n; then
    if git branch -D "$name" >/dev/null 2>&1; then
      print_success "Force-deleted $name"
    else
      print_error "Failed to delete $name"
      _switch_pause
    fi
  fi
}

# Select and switch to a branch using fzf
switch() {
  # Internal entry points used by fzf bindings
  case "${1:-}" in
    --list-branches)
      _switch_list_branches
      return 0
      ;;
    --delete-branch)
      _switch_delete_branch "${2:-}"
      return 0
      ;;
    -v|--version)
      echo "gitbash ${FUNCNAME[0]} v$VERSION"
      return 0
      ;;
    -h|--help)
      gb_help << 'EOF'
Usage: switch [FILTER...]

Select a git branch using fzf and switch to it.

Arguments:
  FILTER...     Optional search words to pre-fill fzf (joined with spaces).
                If exactly one branch name contains them, switches directly.

Options:
  -h, --help    Show this help message

Behavior:
  - Lists local branches ("merged:" = fully merged into the base branch)
    and remote branches that have no local branch yet
  - For remote branches, creates a local tracking branch
  - After switching, offers to fast-forward if the branch is behind its upstream

Keys:
  Enter    Switch to the selected branch
  Del      Delete the selected local branch (asks first, default: no;
           unmerged commits are shown and need a second confirmation)
  Esc      Exit

Examples:
  $ switch
  $ switch captcha
  $ switch LOVE-123

Requirements:
  - Must be in a git repository
  - fzf must be installed

EOF
      return 0
      ;;
  esac

  require_git_repo || return 1
  require_fzf || return 1

  local current_branch filter="$*"
  current_branch=$(gb_current_branch) || current_branch="(detached HEAD)"

  local branch_list
  branch_list=$(_switch_list_branches)
  if [[ -z "$branch_list" ]]; then
    echo "No branches found in this repository."
    return 0
  fi

  # -----------------------------
  # Single match: switch directly
  # -----------------------------
  local selected="" query="$filter"
  if [[ -n "$filter" ]]; then
    local matches match_count
    matches=$(printf '%s\n' "$branch_list" | awk -F'\t' '$2 != "spacer"' |
      while IFS= read -r line; do
        printf '%s\n' "$line" | cut -f3 | grep -qiF -- "$filter" && printf '%s\n' "$line"
      done)
    match_count=$(printf '%s' "$matches" | grep -c . || true)
    if [[ "$match_count" == "1" ]]; then
      selected="$matches"
      print_info "Single match found, switching directly..."
    elif [[ "$match_count" == "0" ]]; then
      query=""
    fi
  fi

  # -----------------------------
  # fzf picker
  # -----------------------------
  if [[ -z "$selected" ]]; then
    local bin_q
    printf -v bin_q '%q' "${GITBASH_BIN:-gitbash}"
    selected=$(run_fzf \
        --height=40% \
        --reverse \
        --border \
        -i \
        --query="$query" \
        --delimiter=$'\t' \
        --with-nth=1 \
        --bind="del:execute($bin_q switch --delete-branch {} < /dev/tty > /dev/tty 2>&1)+reload($bin_q switch --list-branches)" \
        --preview="
          type=\$(printf '%s' {} | cut -f2); name=\$(printf '%s' {} | cut -f3)
          case \"\$type\" in
            local) ref=\"refs/heads/\$name\" ;;
            remote) ref=\"refs/remotes/\$name\" ;;
            *) echo 'Spacer - not selectable'; exit 0 ;;
          esac
          git log --color=\$GB_COLOR -n 1 --format='%C(bold cyan)Author:%C(reset) %an%n%C(bold cyan)Date:%C(reset) %ar (%ad)%n%C(bold cyan)Message:%C(reset) %s%n' --date=format:'%Y-%m-%d %H:%M' \"\$ref\" 2>/dev/null
          echo
          git log --oneline --color=\$GB_COLOR -n 10 \"\$ref\" 2>/dev/null
        " \
        --preview-window=right:50% \
        --header="[Enter] switch | [Del] delete local branch | [Esc] exit | Current: $current_branch" \
        <<< "$branch_list"
    ) || true
  fi

  if [[ -z "$selected" ]]; then
    echo "No branch selected."
    return 0
  fi

  local branch_type branch_name
  branch_type=$(printf '%s' "$selected" | cut -f2)
  branch_name=$(printf '%s' "$selected" | cut -f3)
  # Only accept well-formed list lines ("<label>\t<type>\t<name>")
  if [[ ( "$branch_type" != "local" && "$branch_type" != "remote" ) || -z "$branch_name" ]]; then
    echo "No branch selected."
    return 0
  fi

  # -----------------------------
  # Switch
  # -----------------------------
  if [[ "$branch_type" == "local" ]]; then
    git switch "$branch_name" || { print_error "Failed to switch branch."; return 1; }
  else
    local local_branch="${branch_name#*/}"
    if git show-ref --verify --quiet "refs/heads/$local_branch"; then
      git switch "$local_branch" || { print_error "Failed to switch branch."; return 1; }
    else
      echo "Creating local branch '$local_branch' tracking '$branch_name'"
      git switch -c "$local_branch" --track "$branch_name" || { print_error "Failed to switch branch."; return 1; }
    fi
  fi
  print_success "Switched to branch: $(gb_current_branch)"

  # -----------------------------
  # Offer to fast-forward if behind the upstream
  # -----------------------------
  local now upstream_remote upstream_merge behind
  now=$(gb_current_branch) || return 0
  upstream_remote=$(git config "branch.$now.remote" 2>/dev/null) || return 0
  upstream_merge=$(git config "branch.$now.merge" 2>/dev/null) || return 0
  git fetch --quiet "$upstream_remote" "$upstream_merge" 2>/dev/null || return 0
  behind=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null) || return 0
  if [[ "$behind" -gt 0 ]]; then
    print_warning "Branch is $behind commit(s) behind its upstream."
    if gb_confirm "Fast-forward to the latest changes?" y; then
      if git merge --ff-only --quiet "@{upstream}"; then
        print_success "Up to date."
      else
        print_error "Could not fast-forward (you have local commits or changes). Run 'git pull' to reconcile."
        return 1
      fi
    fi
  fi
  return 0
}
