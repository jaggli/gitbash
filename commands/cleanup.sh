#!/usr/bin/env bash
# shellcheck disable=SC2155

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Cleanup local branches that are no longer needed
cleanup() {
    # -----------------------------
    # 0. Check for help/version flag and parse options
    # -----------------------------
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
                cat << 'EOF'
Usage: cleanup [OPTIONS]

Find and delete local branches that are no longer needed.

Options:
  -h, --help       Show this help message
  --json           Output branch data as JSON (non-interactive)
  --dry-run        Show what would be deleted without actually deleting
  --days=N         Override stale threshold (default: 7 days, configurable via GITBASH_CLEANUP_DAYS)

Categories (pre-selected for deletion):
  - Merged branches: Local branches whose remote was merged and deleted
  - Stale branches: Local branches with no commits in N+ days (default 7)

Not pre-selected (but listed):
  - Recent branches: Local branches with commits in the last N days

Navigation:
  ↑/↓ or j/k    Navigate through branches
  TAB           Select/deselect branch
  Enter         Delete selected branch(es)
  ESC/Ctrl-C    Exit without action

Configuration:
  GITBASH_CLEANUP_DAYS - Set default days threshold (run 'gitbash --config')

Notes:
  - Only deletes LOCAL branches (never touches remote)
  - If current branch is selected, switches to main/master first
  - Force deletes branches (even if not fully merged)

Examples:
  $ cleanup
  Local branches to clean up >
  > [MERGED]  feature/old-feature        2 weeks ago
    [STALE]   feature/abandoned          8 days ago
    [RECENT]  feature/work-in-progress   2 days ago
    ✖ Abort

  $ cleanup --dry-run
  # Shows what would be deleted without deleting

  $ cleanup --days=14
  # Use 14-day threshold for stale branches

  $ cleanup --json
  [{"last_change_timestamp":1733123456,"author_email":"dev@example.com",...}]

Requirements:
  - Must be in a git repository
  - fzf (fuzzy finder) - not required for --json mode

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
                if ! [[ "$days_threshold" =~ ^[0-9]+$ ]] || [[ "$days_threshold" -lt 1 ]]; then
                    print_error "Invalid days value: $days_threshold"
                    return 1
                fi
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done
    # -----------------------------
    # 1. Check prerequisites
    # -----------------------------
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if [[ "$json_mode" == true ]]; then
            echo "[]"
        else
            print_error "Not inside a git repository."
        fi
        return 1
    fi

    if [[ "$json_mode" == false ]]; then
        require_fzf || return 1
    fi
    # -----------------------------
    # 2. Fetch and prune to sync with remote
    # -----------------------------
    if ! git fetch --prune origin 2>/dev/null; then
        if [[ "$json_mode" == false ]]; then
            print_warning "Fetch failed; continuing with local data." >&2
        fi
    fi

    # -----------------------------
    # 3. Detect base branch
    # -----------------------------
    local base_branch
    if git show-ref --verify --quiet refs/heads/main; then
        base_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        base_branch="master"
    else
        if [[ "$json_mode" == false ]]; then
            echo "Could not detect 'main' or 'master' locally."
        else
            echo "[]"
        fi
        return 1
    fi

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    # -----------------------------
    # 4. Build branch lists
    # -----------------------------
    local abort_label="✖ Abort"
    local threshold_ago
    threshold_ago=$(date -v-"${days_threshold}d" +%s 2>/dev/null || date -d "${days_threshold} days ago" +%s 2>/dev/null)

    # Get list of remote branches (without origin/ prefix)
    local remote_branches
    remote_branches=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin | sed 's|^origin/||' | grep -v '^HEAD$' || true)

    # Arrays to hold branches by category (format: timestamp|branch|relative_date|author_email|author_name)
    local -a merged_branches
    local -a stale_branches
    local -a recent_branches
    merged_branches=()
    stale_branches=()
    recent_branches=()

    # Variables for loop (declared once to avoid zsh output on redeclaration)
    local last_commit_ts relative_date author_email author_name
    local has_remote configured_upstream entry

    # Process each local branch
    while IFS= read -r branch; do
        # Skip base branch
        [[ "$branch" == "$base_branch" ]] && continue
        [[ -z "$branch" ]] && continue

        # Get last commit info for all branches
        last_commit_ts=$(git log -1 --format='%ct' "$branch" 2>/dev/null)
        relative_date=$(git log -1 --format='%cr' "$branch" 2>/dev/null)
        author_email=$(git log -1 --format='%ae' "$branch" 2>/dev/null)
        author_name=$(git log -1 --format='%an' "$branch" 2>/dev/null)
        
        # Check if remote branch exists
        has_remote=false
        if echo "$remote_branches" | grep -qx "$branch"; then
            has_remote=true
        fi

        # Check if it HAD an upstream (was pushed before)
        configured_upstream=$(git config "branch.$branch.remote" 2>/dev/null)

        # Entry format: timestamp|branch|relative_date|author_email|author_name
        entry="$last_commit_ts|$branch|$relative_date|$author_email|$author_name"

        if [[ "$has_remote" == false && -n "$configured_upstream" ]]; then
            # Had upstream but remote is gone = merged and deleted remotely
            merged_branches+=("$entry")
        elif [[ -n "$last_commit_ts" && "$last_commit_ts" -lt "$threshold_ago" ]]; then
            # Stale: no commits in N+ days (pre-select for deletion)
            stale_branches+=("$entry")
        else
            # Recent: has recent activity (don't pre-select)
            recent_branches+=("$entry")
        fi
    done < <(git for-each-ref --format='%(refname:short)' refs/heads)

    # Sort each category by timestamp (most recent first), compatible with bash 3.x (no mapfile)
    _sort_desc() {
        local _var="$1"
        shift
        local _out=() _line
        while IFS= read -r _line; do
            _out+=("$_line")
        done < <(printf '%s\n' "$@" | sort -t'|' -k1 -rn)
        # shellcheck disable=SC2034  # assigned via eval to caller var
        eval "$_var=(\"\${_out[@]}\")"
    }

    if [[ ${merged_branches+set} && ${#merged_branches[@]} -gt 0 ]]; then
        _sort_desc merged_branches "${merged_branches[@]}"
    fi
    if [[ ${stale_branches+set} && ${#stale_branches[@]} -gt 0 ]]; then
        _sort_desc stale_branches "${stale_branches[@]}"
    fi
    if [[ ${recent_branches+set} && ${#recent_branches[@]} -gt 0 ]]; then
        _sort_desc recent_branches "${recent_branches[@]}"
    fi

    # -----------------------------
    # 5. JSON mode output
    # -----------------------------
    if [[ "$json_mode" == true ]]; then
        local json_output="["
        local first=true
        
        # Helper function to escape JSON strings
        _json_escape() {
            local str="$1"
            str="${str//\\/\\\\}"
            str="${str//\"/\\\"}"
            str="${str//$'\n'/\\n}"
            str="${str//$'\r'/\\r}"
            str="${str//$'\t'/\\t}"
            echo "$str"
        }
        
        # Process all branches for JSON output
        local all_entries=()
        if [[ ${merged_branches+set} ]]; then
            all_entries+=("${merged_branches[@]}")
        fi
        if [[ ${stale_branches+set} ]]; then
            all_entries+=("${stale_branches[@]}")
        fi
        if [[ ${recent_branches+set} ]]; then
            all_entries+=("${recent_branches[@]}")
        fi

        for entry in "${all_entries[@]}"; do
            [[ -z "$entry" ]] && continue
            
            local ts name rel_date email author
            ts=$(echo "$entry" | cut -d'|' -f1)
            name=$(echo "$entry" | cut -d'|' -f2)
            rel_date=$(echo "$entry" | cut -d'|' -f3)
            email=$(echo "$entry" | cut -d'|' -f4)
            author=$(echo "$entry" | cut -d'|' -f5)
            
            # Escape values for JSON
            name=$(_json_escape "$name")
            rel_date=$(_json_escape "$rel_date")
            email=$(_json_escape "$email")
            author=$(_json_escape "$author")
            
            if [[ "$first" == true ]]; then
                first=false
            else
                json_output+=","
            fi
            
            json_output+="{\"last_change_timestamp\":$ts,\"author_email\":\"$email\",\"author_name\":\"$author\",\"name\":\"$name\",\"last_change_relative\":\"$rel_date\"}"
        done
        
        json_output+="]"
        echo "$json_output"
        return 0
    fi

    # -----------------------------
    # 6. Build fzf input with pre-selection markers
    # -----------------------------
    local branch_list=""
    local preselect_list=""
    local idx=0
    local max_branch_len=60

    # Add merged branches (pre-selected)
    if [[ ${merged_branches+set} ]]; then
        for entry in "${merged_branches[@]}"; do
        local branch date display_branch line
        branch=$(echo "$entry" | cut -d'|' -f2)
        date=$(echo "$entry" | cut -d'|' -f3)
        display_branch="$branch"
        if [[ ${#display_branch} -gt $max_branch_len ]]; then
            display_branch="${display_branch:0:$((max_branch_len - 3))}..."
        fi
        line=$(printf "[MERGED]  %-${max_branch_len}s  %s\t%s" "$display_branch" "$date" "$branch")
        branch_list+="$line"$'\n'
        preselect_list+="$line"$'\n'
        ((idx++))
        done
    fi

    # Add stale branches (pre-selected)
    if [[ ${stale_branches+set} ]]; then
        for entry in "${stale_branches[@]}"; do
            local branch date display_branch line
            branch=$(echo "$entry" | cut -d'|' -f2)
            date=$(echo "$entry" | cut -d'|' -f3)
            display_branch="$branch"
            if [[ ${#display_branch} -gt $max_branch_len ]]; then
                display_branch="${display_branch:0:$((max_branch_len - 3))}..."
            fi
            line=$(printf "[STALE]   %-${max_branch_len}s  %s\t%s" "$display_branch" "$date" "$branch")
            branch_list+="$line"$'\n'
            preselect_list+="$line"$'\n'
            ((idx++))
        done
    fi

    # Add recent branches (not pre-selected)
    if [[ ${recent_branches+set} ]]; then
        for entry in "${recent_branches[@]}"; do
            local branch date display_branch line
            branch=$(echo "$entry" | cut -d'|' -f2)
            date=$(echo "$entry" | cut -d'|' -f3)
            display_branch="$branch"
            if [[ ${#display_branch} -gt $max_branch_len ]]; then
                display_branch="${display_branch:0:$((max_branch_len - 3))}..."
            fi
            line=$(printf "[RECENT]  %-${max_branch_len}s  %s\t%s" "$display_branch" "$date" "$branch")
            branch_list+="$line"$'\n'
            ((idx++))
        done
    fi

    if [[ -z "$branch_list" ]]; then
        echo "No local branches to clean up."
        return 0
    fi

    # Add abort option
    branch_list+="$abort_label"$'\t\t'

    # Create temp files
    local branch_file preselect_file
    branch_file=$(mktemp)
    preselect_file=$(mktemp)
    echo -e "$branch_list" > "$branch_file"
    echo -e "$preselect_list" > "$preselect_file"

    # -----------------------------
    # 7. Run fzf picker
    # -----------------------------
    local merged_count=0
    local stale_count=0
    local recent_count=0

    [[ ${merged_branches+set} ]] && merged_count=${#merged_branches[@]}
    [[ ${stale_branches+set} ]] && stale_count=${#stale_branches[@]}
    [[ ${recent_branches+set} ]] && recent_count=${#recent_branches[@]}

    local total_count=$((merged_count + stale_count + recent_count))
    local preselect_count=$((merged_count + stale_count))

    # Build toggle sequence for pre-selection (toggle first N items)
    local toggle_sequence="first"
    for ((i=0; i<preselect_count; i++)); do
        toggle_sequence+="+toggle+down"
    done
    toggle_sequence+="+first"

    local selection
    selection=$(fzf \
        --prompt="Local branches to clean up > " \
        -i \
        --reverse \
        --border \
        --header="[TAB] toggle | [Enter] delete selected | [ESC] exit
Found $total_count branches ($preselect_count pre-selected for deletion)" \
        --multi \
        --delimiter=$'\t' \
        --with-nth=1 \
        --bind=enter:accept \
        --preview='
            line={}
            if [[ "$line" == "✖ Abort"* ]]; then
                echo "Exit without action";
            else
                branch=$(echo "$line" | cut -f2)
                echo "Branch: $branch";
                echo "";
                echo "Recent commits:";
                git log --oneline --color=always -n 15 "$branch" 2>/dev/null || echo "No commits found";
            fi
        ' \
        --preview-window=right:35% \
        --bind "load:$toggle_sequence" \
        < "$branch_file"
    ) </dev/tty || true

    # Cleanup temp files
    rm -f "$branch_file" "$preselect_file"

    # ESC or Ctrl-C
    if [[ -z "$selection" ]]; then
        echo "Exited."
        return 0
    fi

    # Abort option
    if echo "$selection" | grep -q "^$abort_label"; then
        echo "Aborted."
        return 0
    fi

    # -----------------------------
    # 8. Extract branch names and confirm deletion
    # -----------------------------
    local branches_to_delete=()
    local need_switch=false
    local only_merged=true
    local branch_name line

    while IFS= read -r line; do
        [[ "$line" == "✖ Abort"* ]] && continue
        branch_name=$(echo "$line" | cut -f2)
        if [[ -n "$branch_name" ]]; then
            branches_to_delete+=("$branch_name")
            if [[ "$branch_name" == "$current_branch" ]]; then
                need_switch=true
            fi
            # Check if this is not a MERGED branch
            if [[ ! "$line" == "[MERGED]"* ]]; then
                only_merged=false
            fi
        fi
    done <<< "$selection"

    if [[ ${#branches_to_delete[@]} -eq 0 ]]; then
        echo "No branches selected."
        return 0
    fi

    echo ""
    echo "Selected local branches to delete:"
    for branch in "${branches_to_delete[@]}"; do
        if [[ "$branch" == "$current_branch" ]]; then
            echo "  - $branch (current branch)"
        else
            echo "  - $branch"
        fi
    done
    
    if [[ "$need_switch" == true ]]; then
        echo ""
        echo "Note: Will switch to '$base_branch' first (current branch selected for deletion)"
    fi
    echo ""

    # Handle dry-run mode
    if [[ "$dry_run" == true ]]; then
        print_info "Dry run mode - no branches will be deleted"
        echo "Would delete ${#branches_to_delete[@]} branch(es):"
        for branch in "${branches_to_delete[@]}"; do
            echo "  - $branch"
        done
        return 0
    fi

    # Default to Y if only merged branches, otherwise N
    local confirm
    if [[ "$only_merged" == true ]]; then
        prompt_read "Delete these ${#branches_to_delete[@]} local branch(es)? (Y/n): " confirm
        case "$confirm" in
            [nN][oO]|[nN])
                echo "Deletion cancelled."
                return 0
                ;;
        esac
    else
        prompt_read "Delete these ${#branches_to_delete[@]} local branch(es)? (y/N): " confirm
        case "$confirm" in
            [yY][eE][sS]|[yY])
                ;;
            *)
                echo "Deletion cancelled."
                return 0
                ;;
        esac
    fi

    # Switch to base branch if needed
    if [[ "$need_switch" == true ]]; then
        print_info "Switching to '$base_branch'..."
        git checkout "$base_branch" || {
            print_warning "Failed to switch to '$base_branch'. Aborting deletion."
            return 1
        }
    fi

    print_info "Deleting branches..."
    for branch in "${branches_to_delete[@]}"; do
        echo "Deleting $branch ..."
        if git branch -D "$branch" 2>/dev/null; then
            print_success "Deleted $branch"
        else
            print_error "Failed to delete $branch"
        fi
    done
}
