#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Returns 0 if all changes of the branch are in the base (merged, fast-forwarded or squash-merged)
_cleanup_is_merged() {
  local branch="$1" base_ref="$2" merge_base squashed
  git merge-base --is-ancestor "$branch" "$base_ref" 2>/dev/null && return 0
  # Squash merge: a commit with the branch's combined changes already exists in the base
  merge_base=$(git merge-base "$base_ref" "$branch" 2>/dev/null) || return 1
  squashed=$(git commit-tree "$branch^{tree}" -p "$merge_base" -m "gitbash squash check" 2>/dev/null) || return 1
  [[ "$(git cherry "$base_ref" "$squashed" 2>/dev/null)" == "-"* ]]
}

# Unix timestamp of N days ago
_cleanup_days_ago() {
  local days="$1" ts
  ts=$(date -v-"${days}d" +%s 2>/dev/null) ||
    ts=$(date -d "${days} days ago" +%s 2>/dev/null) ||
    ts=$(( $(date +%s) - days * 86400 ))
  echo "$ts"
}

# Cleanup local branches that are no longer needed
cleanup() {
  local json_mode=false
  local dry_run=false
  local days_threshold="${GITBASH_CLEANUP_DAYS:-7}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version)
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
        ;;
      -h|--help)
        gb_help << 'EOF'
Usage: cleanup [OPTIONS]

Find and delete local branches that are no longer needed.

Options:
  -h, --help       Show this help message
  --json           Output branch data as JSON (non-interactive)
  --dry-run        List the branches that would be pre-selected, without deleting
  --days=N         Override stale threshold (default: 7 days, configurable via GITBASH_CLEANUP_DAYS)
  -y, --yes        Delete the pre-selected branches without the picker (safe delete only)

Labels:
  [MERGED]  All changes are in the base branch (merged, fast-forwarded or squash-merged).
            Pre-selected when the remote branch is gone or it is older than N days.
  [STALE]   No commits in N+ days. Pre-selected only if everything is pushed.
  [GONE]    Remote branch was deleted, but the changes are NOT in the base branch.
  [RECENT]  Commits in the last N days.
  "N unpushed" means N commits exist only on your machine.

Protected branches (base branch and GITBASH_PROTECTED_BRANCHES) are never listed.

Navigation:
  ↑/↓           Navigate through branches
  TAB           Select/deselect branch
  Enter         Delete selected branch(es)
  ESC/Ctrl-C    Exit without action

Deleting:
  - Only deletes LOCAL branches (never touches the remote)
  - If the current branch is selected, switches to the base branch first
  - Uses 'git branch -d'. Branches with unmerged commits are listed and only
    force-deleted after a separate confirmation (default: no).

Examples:
  $ cleanup
  $ cleanup --dry-run
  $ cleanup --days=14
  $ cleanup --json

Requirements:
  - Must be in a git repository
  - fzf (not required for --json, --dry-run or --yes)

EOF
        return 0
        ;;
      --json)
        json_mode=true
        shift
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --days=*)
        days_threshold="${1#--days=}"
        if ! [[ "$days_threshold" =~ ^[1-9][0-9]*$ ]]; then
          print_error "Invalid days value: $days_threshold"
          return 1
        fi
        shift
        ;;
      -y|--yes)
        GITBASH_ASSUME_YES=1
        shift
        ;;
      *)
        print_error "Unknown option: $1"
        return 1
        ;;
    esac
  done

  local interactive=true
  if [[ "$json_mode" == true || "$dry_run" == true || "${GITBASH_ASSUME_YES:-}" == "1" ]]; then
    interactive=false
  fi

  # -----------------------------
  # 1. Prerequisites
  # -----------------------------
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "$json_mode" == true ]]; then echo "[]"; else print_error "Not inside a git repository."; fi
    return 1
  fi
  if [[ "$interactive" == true ]]; then
    require_fzf || return 1
  fi

  local remote
  remote=$(gb_remote)
  if ! git fetch --prune --quiet "$remote" 2>/dev/null; then
    [[ "$json_mode" == false ]] && print_warning "Fetch failed; continuing with local data."
  fi

  local base_branch base_ref
  if ! base_branch=$(gb_base_branch); then
    if [[ "$json_mode" == true ]]; then echo "[]"; else print_error "Could not detect the base branch. Set GITBASH_BASE_BRANCH."; fi
    return 1
  fi
  GB_BASE="$base_branch"
  base_ref=$(gb_base_ref "$base_branch")

  local current_branch
  current_branch=$(gb_current_branch) || current_branch=""

  # -----------------------------
  # 2. Classify local branches
  # -----------------------------
  local threshold_ago
  threshold_ago=$(_cleanup_days_ago "$days_threshold")

  # Entry: preselect|label|timestamp|branch|relative_date|email|unpushed|name (name last: it may contain "|")
  local entries=()
  local sep=$'\x1f'
  local branch ts rel email name _upstream track unpushed merged label preselect
  while IFS="$sep" read -r branch ts rel email _upstream track name; do
    [[ -z "$branch" ]] && continue
    gb_is_protected "$branch" && continue

    unpushed=$(git rev-list --count "refs/heads/$branch" --not --remotes 2>/dev/null || echo 0)
    merged=false
    _cleanup_is_merged "refs/heads/$branch" "$base_ref" && merged=true

    preselect=0
    if [[ "$merged" == true ]]; then
      label="MERGED"
      if [[ "$track" == "[gone]" || "$ts" -lt "$threshold_ago" ]]; then
        preselect=1
      fi
    elif [[ "$track" == "[gone]" ]]; then
      label="GONE"
    elif [[ "$ts" -lt "$threshold_ago" ]]; then
      label="STALE"
      [[ "$unpushed" == "0" ]] && preselect=1
    else
      label="RECENT"
    fi
    entries+=("$preselect|$label|$ts|$branch|$rel|$email|$unpushed|$name")
  done < <(git for-each-ref \
      --format="%(refname:short)%1f%(committerdate:unix)%1f%(committerdate:relative)%1f%(authoremail)%1f%(upstream:short)%1f%(upstream:track)%1f%(authorname)" \
      refs/heads 2>/dev/null)

  # Pre-selected first, then newest first
  local sorted=()
  if [[ ${#entries[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      sorted+=("$line")
    done < <(printf '%s\n' "${entries[@]}" | sort -t'|' -k1,1rn -k3,3rn)
  fi

  # -----------------------------
  # 3. JSON output
  # -----------------------------
  if [[ "$json_mode" == true ]]; then
    local json="[" first=true entry
    for entry in ${sorted[@]+"${sorted[@]}"}; do
      IFS='|' read -r preselect label ts branch rel email unpushed name <<< "$entry"
      email="${email#<}"
      email="${email%>}"
      [[ "$first" == true ]] && first=false || json+=","
      json+="{\"last_change_timestamp\":$ts,\"author_email\":\"$(gb_json_escape "$email")\",\"author_name\":\"$(gb_json_escape "$name")\",\"name\":\"$(gb_json_escape "$branch")\",\"last_change_relative\":\"$(gb_json_escape "$rel")\",\"category\":\"$(echo "$label" | tr '[:upper:]' '[:lower:]')\",\"preselected\":$([[ "$preselect" == 1 ]] && echo true || echo false),\"unpushed_commits\":$unpushed}"
    done
    echo "$json]"
    return 0
  fi

  if [[ ${#sorted[@]} -eq 0 ]]; then
    echo "No local branches to clean up."
    return 0
  fi

  # -----------------------------
  # 4. Select branches
  # -----------------------------
  local selected=()
  local preselect_count=0 entry
  for entry in "${sorted[@]}"; do
    [[ "${entry%%|*}" == "1" ]] && preselect_count=$((preselect_count + 1))
  done

  if [[ "$interactive" == false ]]; then
    for entry in "${sorted[@]}"; do
      IFS='|' read -r preselect label ts branch rel email unpushed name <<< "$entry"
      [[ "$preselect" == "1" ]] && selected+=("$branch")
    done
    if [[ ${#selected[@]} -eq 0 ]]; then
      echo "No branches to clean up (none pre-selected)."
      return 0
    fi
    if [[ "$dry_run" == true ]]; then
      echo "Would delete ${#selected[@]} branch(es):"
      printf '  - %s\n' "${selected[@]}"
      return 0
    fi
  else
    local abort_label="✖ Abort" list="" display note
    local max_len=60
    for entry in "${sorted[@]}"; do
      IFS='|' read -r preselect label ts branch rel email unpushed name <<< "$entry"
      display="$branch"
      if [[ ${#display} -gt $max_len ]]; then
        display="${display:0:$((max_len - 3))}..."
      fi
      note=""
      [[ "$unpushed" != "0" ]] && note="  ($unpushed unpushed)"
      [[ "$branch" == "$current_branch" ]] && note+="  (current)"
      list+=$(printf "%-9s %-${max_len}s  %s%s" "[$label]" "$display" "$rel" "$note")
      list+=$'\t'"$branch"$'\n'
    done
    list+="$abort_label"$'\t'

    # Toggle the first N (pre-selected) items once the list is loaded
    local toggle_sequence="first" i
    for ((i = 0; i < preselect_count; i++)); do
      toggle_sequence+="+toggle+down"
    done
    toggle_sequence+="+first"

    local selection
    selection=$(run_fzf \
        --prompt="Local branches to clean up > " \
        -i \
        --reverse \
        --border \
        --header="[TAB] toggle | [Enter] delete selected | [ESC] exit
${#sorted[@]} branches, $preselect_count pre-selected" \
        --multi \
        --delimiter=$'\t' \
        --with-nth=1 \
        --preview='
            branch=$(printf "%s" {} | cut -f2)
            if [[ -z "$branch" ]]; then echo "Exit without action"; exit 0; fi
            echo "Branch: $branch"
            echo
            unpushed=$(git log --oneline --color=always "refs/heads/$branch" --not --remotes 2>/dev/null)
            if [[ -n "$unpushed" ]]; then
                echo "Unpushed commits (only on this machine):"
                echo "$unpushed"
                echo
            fi
            echo "Recent commits:"
            git log --oneline --color=always -n 15 "refs/heads/$branch" 2>/dev/null
        ' \
        --preview-window=right:40% \
        --bind "load:$toggle_sequence" \
        <<< "$list"
    ) || true

    if [[ -z "$selection" ]]; then
      echo "Exited."
      return 0
    fi

    local line
    while IFS= read -r line; do
      branch=$(printf '%s' "$line" | cut -f2)
      [[ -n "$branch" ]] && selected+=("$branch")
    done <<< "$selection"

    if [[ ${#selected[@]} -eq 0 ]]; then
      echo "Aborted."
      return 0
    fi
  fi

  # -----------------------------
  # 5. Confirm and delete
  # -----------------------------
  local need_switch=false only_merged=true merged_list=" " label_of
  for entry in "${sorted[@]}"; do
    IFS='|' read -r preselect label ts branch rel email unpushed name <<< "$entry"
    [[ "$label" == "MERGED" ]] && merged_list+="$branch "
  done
  echo "Selected local branches to delete:"
  for branch in "${selected[@]}"; do
    label_of=""
    [[ "$branch" == "$current_branch" ]] && { need_switch=true; label_of=" (current branch)"; }
    [[ "$merged_list" == *" $branch "* ]] || only_merged=false
    echo "  - $branch$label_of"
  done
  if [[ "$need_switch" == true ]]; then
    echo "Will switch to '$base_branch' first."
  fi

  local default="n"
  [[ "$only_merged" == true ]] && default="y"
  if ! gb_confirm "Delete these ${#selected[@]} local branch(es)?" "$default"; then
    echo "Deletion cancelled."
    return 0
  fi

  if [[ "$need_switch" == true ]]; then
    print_info "Switching to '$base_branch'..."
    if ! git switch --quiet "$base_branch"; then
      print_error "Failed to switch to '$base_branch'. Nothing was deleted."
      return 1
    fi
  fi

  local refused=() out
  for branch in "${selected[@]}"; do
    if [[ "$merged_list" == *" $branch "* ]]; then
      # Verified merged (including squash merges): git's own check may not see it
      if git branch -D --quiet "$branch" >/dev/null 2>&1; then
        print_success "Deleted $branch"
      else
        print_error "Failed to delete $branch"
      fi
    elif out=$(git branch -d "$branch" 2>&1); then
      print_success "Deleted $branch"
    else
      refused+=("$branch")
    fi
  done

  if [[ ${#refused[@]} -gt 0 ]]; then
    echo
    print_warning "These branches have commits that are not merged. Deleting them loses those commits:"
    for branch in "${refused[@]}"; do
      echo "  $branch:"
      git log --oneline -n 5 "refs/heads/$branch" --not "$base_ref" --remotes 2>/dev/null | sed 's/^/      /'
    done
    if gb_confirm --strict "Force-delete these ${#refused[@]} branch(es)?" n; then
      for branch in "${refused[@]}"; do
        if git branch -D --quiet "$branch" >/dev/null 2>&1; then
          print_success "Force-deleted $branch"
        else
          print_error "Failed to delete $branch"
        fi
      done
    else
      echo "Kept: ${refused[*]}"
    fi
  fi
  return 0
}
