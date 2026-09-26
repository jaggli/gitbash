#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Print one line per changed file: "<display>\t<XY>\t<path>\t<original path>"
# The path fields are exact (spaces, quotes and renames are handled).
_status_list() {
  local entry xy path orig label display
  while IFS= read -r -d '' entry; do
    xy="${entry:0:2}"
    path="${entry:3}"
    orig=""
    if [[ "${xy:0:1}" == [RC] || "${xy:1:1}" == [RC] ]]; then
      IFS= read -r -d '' orig
    fi
    case "$xy" in
      "??") label="UNTRACKED" ;;
      DD|AU|UD|UA|DU|AA|UU) label="CONFLICT" ;;
      " "?) label="UNSTAGED" ;;
      ?" ") label="STAGED" ;;
      *) label="PARTIAL" ;;
    esac
    display="$path"
    [[ -n "$orig" ]] && display="$orig -> $path"
    printf '%-12s %s  %s\t%s\t%s\t%s\n' "[$label]" "$xy" "$display" "$xy" "$path" "$orig"
  done < <(git status --porcelain=v1 -z 2>/dev/null)
}

# Unstage a file (works before the first commit, too)
_status_unstage() {
  if git rev-parse --verify --quiet HEAD >/dev/null; then
    git restore --staged -- "$@"
  else
    git rm --cached --quiet -r -- "$@"
  fi
}

# Show git status with fzf file selector and diff preview
status() {
  if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
    echo "gitbash ${FUNCNAME[0]} v$VERSION"
    return 0
  fi
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    gb_help << 'EOF'
Usage: status [OPTIONS]

Interactive git status: stage, unstage, discard and commit with diff previews.

Options:
  -h, --help    Show this help message

Labels:
  [STAGED]     All changes of the file are staged
  [PARTIAL]    Some changes staged, some not
  [UNSTAGED]   Changes not staged yet
  [UNTRACKED]  New file or directory
  [CONFLICT]   Merge conflict - resolve it in your editor

Keys:
  TAB           Select/deselect file (multi-select)
  Enter         Stage the selected files (unstage them if fully staged)
  Ctrl-R        Discard changes of the selected files (asks first)
  Ctrl-O        Commit the staged changes (then asks whether to push)
  ESC/Ctrl-C    Exit

Requirements:
  - Must be in a git repository
  - fzf

EOF
    return 0
  fi
  if [[ $# -gt 0 ]]; then
    print_error "Unknown argument: $1"
    echo "Usage: status [-h|--help]" >&2
    return 1
  fi

  require_git_repo || return 1
  require_fzf || return 1

  # Commands on file paths must run from the repository root
  local repo_root
  repo_root=$(git rev-parse --show-toplevel) || return 1
  cd "$repo_root" || return 1

  local pager bat_cmd preview
  pager=$(gb_diff_pager)
  bat_cmd=$(gb_bat_cmd)
  preview='
    xy=$(printf "%s" {} | cut -f2); file=$(printf "%s" {} | cut -f3)
    if [[ "$xy" == "??" ]]; then
      echo "=== UNTRACKED ==="; echo
      if [[ -d "$file" ]]; then ls -la "$file"; else __BAT__ "$file" 2>/dev/null || echo "Cannot preview file"; fi
    else
      staged=$(git diff --cached --color=$GB_COLOR -- "$file" 2>/dev/null)
      unstaged=$(git diff --color=$GB_COLOR -- "$file" 2>/dev/null)
      if [[ -n "$staged" ]]; then echo "=== STAGED CHANGES ==="; echo; printf "%s\n" "$staged" | __PAGER__; fi
      if [[ -n "$unstaged" ]]; then
        [[ -n "$staged" ]] && echo
        echo "=== UNSTAGED CHANGES ==="; echo; printf "%s\n" "$unstaged" | __PAGER__
      fi
    fi'
  preview="${preview//__PAGER__/$pager}"
  preview="${preview//__BAT__/$bat_cmd}"

  local status_list
  while true; do
    status_list=$(_status_list)
    if [[ -z "$status_list" ]]; then
      print_success "Working tree clean."
      return 0
    fi

    local output
    output=$(run_fzf \
        --height=100% \
        -i \
        --reverse \
        --border \
        --prompt="Git Status > " \
        --header="[Enter] stage/unstage | [Ctrl-R] discard | [Ctrl-O] commit staged | [TAB] multi-select | [ESC] exit" \
        --multi \
        --delimiter=$'\t' \
        --with-nth=1 \
        --expect=ctrl-r,ctrl-o \
        --preview="$preview" \
        --preview-window=right:60% \
        <<< "$status_list"
    ) || true

    local key_pressed
    key_pressed=$(printf '%s\n' "$output" | head -n 1)
    local selected=() line
    while IFS= read -r line; do
      [[ -n "$line" ]] && selected+=("$line")
    done < <(printf '%s\n' "$output" | tail -n +2)

    if [[ -z "$output" ]]; then
      return 0
    fi

    case "$key_pressed" in
      ctrl-o)
        if git diff --cached --quiet 2>/dev/null; then
          print_warning "Nothing staged yet. Stage files with Enter first."
          continue
        fi
        if gb_run commit --staged; then
          if gb_confirm "Push to the remote?" n; then
            gb_sync_and_push
          fi
        fi
        continue
        ;;
      ctrl-r)
        [[ ${#selected[@]} -eq 0 ]] && continue
        _status_discard "${selected[@]}"
        continue
        ;;
    esac

    [[ ${#selected[@]} -eq 0 ]] && return 0

    # Enter: stage, or unstage fully staged files
    local xy path orig
    for line in "${selected[@]}"; do
      xy=$(printf '%s' "$line" | cut -f2)
      path=$(printf '%s' "$line" | cut -f3)
      orig=$(printf '%s' "$line" | cut -f4)
      case "$xy" in
        DD|AU|UD|UA|DU|AA|UU)
          print_warning "$path has a merge conflict - resolve it in your editor, then stage it."
          ;;
        ?" ")
          echo "Unstaging: $path"
          if [[ -n "$orig" ]]; then
            _status_unstage "$path" "$orig" || print_error "Failed to unstage $path"
          else
            _status_unstage "$path" || print_error "Failed to unstage $path"
          fi
          ;;
        *)
          echo "Staging: $path"
          git add -A -- "$path" || print_error "Failed to stage $path"
          ;;
      esac
    done
  done
}

# Discard changes of the selected status lines (asks first)
_status_discard() {
  local line xy path orig
  local untracked=() added=() tracked=() tracked_orig=()
  for line in "$@"; do
    xy=$(printf '%s' "$line" | cut -f2)
    path=$(printf '%s' "$line" | cut -f3)
    orig=$(printf '%s' "$line" | cut -f4)
    case "$xy" in
      "??") untracked+=("$path") ;;
      A?) added+=("$path") ;;
      *) tracked+=("$path"); [[ -n "$orig" ]] && tracked_orig+=("$orig") ;;
    esac
  done

  if [[ ${#untracked[@]} -gt 0 ]]; then
    echo "Untracked files/directories to delete:"
    printf '  - %s\n' "${untracked[@]}"
    if gb_confirm --strict "Delete these ${#untracked[@]} item(s)? This cannot be undone." n; then
      for path in "${untracked[@]}"; do
        if rm -rf -- "$path"; then
          print_success "Deleted: $path"
        else
          print_error "Failed to delete: $path"
        fi
      done
    fi
  fi

  if [[ ${#added[@]} -gt 0 ]]; then
    echo "Newly added files to unstage:"
    printf '  - %s\n' "${added[@]}"
    if gb_confirm --strict "Unstage these ${#added[@]} file(s)?" n; then
      local delete_too=false
      gb_confirm --strict "Also delete them from disk?" n && delete_too=true
      for path in "${added[@]}"; do
        if ! git rm --cached --quiet -r -- "$path"; then
          print_error "Failed to unstage: $path"
          continue
        fi
        if [[ "$delete_too" == true ]]; then
          rm -rf -- "$path" && print_success "Deleted: $path"
        else
          print_success "Unstaged (file kept): $path"
        fi
      done
    fi
  fi

  if [[ ${#tracked[@]} -gt 0 ]]; then
    if ! git rev-parse --verify --quiet HEAD >/dev/null; then
      print_warning "No commits yet - nothing to restore tracked files from."
      return 0
    fi
    echo "Files to restore to the last commit:"
    printf '  - %s\n' "${tracked[@]}"
    if gb_confirm --strict "Discard all changes in these ${#tracked[@]} file(s)? This cannot be undone." n; then
      for path in "${tracked[@]}"; do
        if git restore --source=HEAD --staged --worktree -- "$path" 2>/dev/null ||
           git restore --staged -- "$path" 2>/dev/null; then
          print_success "Restored: $path"
        else
          print_error "Failed to restore: $path"
        fi
      done
      if [[ ${#tracked_orig[@]} -gt 0 ]]; then
        git restore --source=HEAD --staged --worktree -- "${tracked_orig[@]}" 2>/dev/null
      fi
    fi
  fi
}
