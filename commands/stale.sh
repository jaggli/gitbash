#!/usr/bin/env bash
# shellcheck disable=SC2155

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

stale() {
    # -----------------------------
    # 0. Check for help/version flag and parse options
    # -----------------------------
    local json_mode=false
    local my_mode=false
    local all_mode=false
    local filter_args=()
    local stale_months="${GITBASH_STALE_MONTHS:-3}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                echo "gitbash ${FUNCNAME[0]} v$VERSION"
                return 0
                ;;
            -h|--help)
                cat << 'EOF'
Usage: stale [OPTIONS] [FILTER...]

Show a list of remote branches ordered by last modification date (oldest first).
Useful for identifying stale branches that may need cleanup.

Arguments:
  FILTER...     Optional search filter words to pre-fill fzf (joined with spaces)

Options:
  -h, --help      Show this help message
  -a, --all       Start in 'all branches' mode (default is stale mode)
  -m, --my        Pre-fill filter with your git username (from git config user.name)
  --json          Output branch data as JSON (non-interactive)
  --age=N         Override stale threshold in months (default: 3, configurable via GITBASH_STALE_MONTHS)

Features:
  - Lists all remote branches sorted by last commit date (oldest first)
  - By default, only shows branches older than N months (default 3)
  - Shows branch name, relative date, and author
  - Interactive selection with fzf
  - Preview shows recent commits on the selected branch
  - Delete selected branches directly from the list

Configuration:
  GITBASH_STALE_MONTHS - Set default threshold in months (run 'gitbash --config')

Navigation:
  ↑/↓ or j/k    Navigate through branches
  TAB           Select/deselect branch (multi-select)
  Ctrl-A        Toggle showing all branches (including recent ones)
  Enter         Delete selected branch(es)
  ESC/Ctrl-C    Exit without action

Examples:
  $ stale
  Stale branches (oldest first) >
  > feature/very-old                       6 months ago    Bob Wilson
    feature/another-old-one                4 months ago    Jane Smith
    feature/old-feature                    3 months ago    John Doe
    ✖ Abort

  $ stale --age=1
  # Show branches older than 1 month

  $ stale --age=6
  # Show branches older than 6 months

  $ stale --all
  # Start with all branches visible (including recent ones)
  # Press Ctrl-A to toggle between all/stale view

  $ stale --my
  # Pre-fills fzf filter with your git username to show only your branches

  $ stale Product refactoring
  # Pre-fills fzf filter with "Product refactoring"

  $ stale --json
  # Output JSON for scripting

Output format:
  <branch-name>                            <relative-date>  <author>

Requirements:
  - Must be in a git repository
  - fzf (fuzzy finder) - will prompt to install if not found (not required for --json)

EOF
                return 0
                ;;
            --json)
                json_mode=true
                shift
                ;;
            -a|--all)
                all_mode=true
                shift
                ;;
            -m|--my)
                my_mode=true
                shift
                ;;
            --age=*)
                stale_months="${1#--age=}"
                if ! [[ "$stale_months" =~ ^[0-9]+$ ]] || [[ "$stale_months" -lt 1 ]]; then
                    print_error "Invalid age value: $stale_months"
                    return 1
                fi
                shift
                ;;
            *)
                filter_args+=("$1")
                shift
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
            echo "Not inside a git repository."
        fi
        return 1
    fi

    if [[ "$json_mode" == false ]]; then
        require_fzf || return 1
    fi

    # -----------------------------
    # 2. Handle filter (--my flag or arbitrary words)
    # -----------------------------
    local filter=""
    if [[ "$my_mode" == true ]]; then
        filter=$(git config user.name)
        if [[ -z "$filter" && "$json_mode" == false ]]; then
            echo "Warning: git config user.name is not set."
        fi
    elif [[ ${#filter_args[@]} -gt 0 ]]; then
        filter="${filter_args[*]}"
    fi

    # -----------------------------
    # 3. Fetch latest from remote
    # -----------------------------
    if [[ "$json_mode" == false ]]; then
        echo "Fetching latest from remote..."
    fi
    if ! git fetch --prune origin 2>/dev/null; then
        if [[ "$json_mode" == false ]]; then
            echo "⚠ Fetch failed; continuing with local data." >&2
        fi
    fi

    # -----------------------------
    # 4. Build branch list sorted by date (oldest first)
    # -----------------------------
    local abort_label="✖ Abort"
    local max_branch_length=65
    
    # Calculate date N months ago (based on stale_months)
    local threshold_ago
    threshold_ago=$(date -v-"${stale_months}m" +%s 2>/dev/null || date -d "${stale_months} months ago" +%s 2>/dev/null)
    
    # Build full branch list (all branches)
    # Format: display_branch | date | author | full_branch (tab-separated, last field is full branch for operations)
    local all_branch_list
    all_branch_list=$(git for-each-ref --sort=committerdate --format='%(refname:short)|%(committerdate:relative)|%(authorname)|%(committerdate:unix)' refs/remotes/origin | \
        grep -v 'origin/HEAD' | \
        grep -v '^origin|' | \
        while IFS='|' read -r branch date author timestamp; do
            # Remove origin/ prefix for display
            local full_branch="${branch#origin/}"
            local display_branch="$full_branch"
            # Truncate branch name if too long
            if [[ ${#display_branch} -gt $max_branch_length ]]; then
                display_branch="${display_branch:0:$((max_branch_length - 3))}..."
            fi
            # Format: display branch (padded), date, author, TAB, full branch name
            printf "%-${max_branch_length}s  %-20s %-25s\t%s\n" "$display_branch" "$date" "$author" "$full_branch"
        done || true)
    
    # Build stale branch list (only branches older than 3 months)
    local stale_branch_list
    stale_branch_list=$(git for-each-ref --sort=committerdate --format='%(refname:short)|%(committerdate:relative)|%(authorname)|%(committerdate:unix)' refs/remotes/origin | \
        grep -v 'origin/HEAD' | \
        grep -v '^origin|' | \
        while IFS='|' read -r branch date author timestamp; do
            # Only include if older than 3 months
            if [[ "$timestamp" -lt "$threshold_ago" ]]; then
                # Remove origin/ prefix for display
                local full_branch="${branch#origin/}"
                local display_branch="$full_branch"
                # Truncate branch name if too long
                if [[ ${#display_branch} -gt $max_branch_length ]]; then
                    display_branch="${display_branch:0:$((max_branch_length - 3))}..."
                fi
                # Format: display branch (padded), date, author, TAB, full branch name
                printf "%-${max_branch_length}s  %-20s %-25s\t%s\n" "$display_branch" "$date" "$author" "$full_branch"
            fi
        done || true)

    if [[ -z "$all_branch_list" ]]; then
        if [[ "$json_mode" == true ]]; then
            echo "[]"
        else
            echo "No remote branches found."
        fi
        return 0
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
        
        # Build JSON from branches (all or stale based on --all flag)
        {
        while IFS='|' read -r branch rel_date author_name author_email timestamp; do
            [[ -z "$branch" ]] && continue
            # Include based on all_mode flag
            if [[ "$all_mode" == true ]] || [[ "$timestamp" -lt "$threshold_ago" ]]; then
                local name="${branch#origin/}"
                # Remove angle brackets from email
                author_email="${author_email#<}"
                author_email="${author_email%>}"
                
                # Escape values for JSON
                name=$(_json_escape "$name")
                rel_date=$(_json_escape "$rel_date")
                author_email=$(_json_escape "$author_email")
                author_name=$(_json_escape "$author_name")
                
                if [[ "$first" == true ]]; then
                    first=false
                else
                    json_output+=","
                fi
                
                json_output+="{\"last_change_timestamp\":$timestamp,\"author_email\":\"$author_email\",\"author_name\":\"$author_name\",\"name\":\"$name\",\"last_change_relative\":\"$rel_date\"}"
            fi
        done < <(git for-each-ref --sort=committerdate --format='%(refname:short)|%(committerdate:relative)|%(authorname)|%(authoremail)|%(committerdate:unix)' refs/remotes/origin 2>/dev/null | grep -v 'origin/HEAD' | grep -v '^origin|' || true)
        } &>/dev/null
        json_output+="]"
        echo "$json_output"
        return 0
    fi
    
    # Create temp files for fzf reload
    local stale_file=$(mktemp)
    local all_file=$(mktemp)
    local state_file=$(mktemp)
    local toggle_script=$(mktemp)
    
    # Ensure cleanup on exit
    trap 'rm -f "$stale_file" "$all_file" "$state_file" "$toggle_script"' EXIT INT TERM
    
    # Write stale branches with header
    {
        echo "══ Stale branches (>${stale_months}mo, oldest first) ══ [TAB] select | [Ctrl-A] toggle all/stale | [Enter] delete | [ESC] exit"
        if [[ -n "$stale_branch_list" ]]; then
            echo "$stale_branch_list"
        fi
        echo "$abort_label"
    } > "$stale_file"
    
    # Write all branches with header
    {
        echo "══ All branches (oldest first) ══ [TAB] select | [Ctrl-A] toggle all/stale | [Enter] delete | [ESC] exit"
        if [[ -n "$all_branch_list" ]]; then
            echo "$all_branch_list"
        fi
        echo "$abort_label"
    } > "$all_file"
    
    # Set initial state based on --all flag
    if [[ "$all_mode" == true ]]; then
        printf "all" > "$state_file"
    else
        printf "stale" > "$state_file"
    fi

    # -----------------------------
    # 6. Run fzf picker with preview
    # -----------------------------
    local stale_count=$(echo "$stale_branch_list" | grep -c . || echo "0")
    local all_count=$(echo "$all_branch_list" | grep -c . || echo "0")
    
    # Create toggle script
    cat > "$toggle_script" << TOGGLE_EOF
#!/bin/bash
state=\$(cat "$state_file" | tr -d '\n')
# Toggle: if currently stale, switch to all; if currently all, switch to stale
if [[ "\$state" == "stale" ]]; then
    # Switching FROM stale TO all
    printf "all" > "$state_file"
    cat "$all_file"
else
    # Switching FROM all TO stale
    printf "stale" > "$state_file"
    cat "$stale_file"
fi
TOGGLE_EOF
    chmod +x "$toggle_script"
    
    # Set initial input file based on mode
    local initial_input_file
    if [[ "$all_mode" == true ]]; then
        initial_input_file="$all_file"
    else
        initial_input_file="$stale_file"
    fi
    
    local selection
    selection=$(
        cat "$initial_input_file" | fzf \
            --query="$filter" \
            -i \
            --reverse \
            --border \
            --header-lines=1 \
            --multi \
            --delimiter=$'\t' \
            --with-nth=1 \
            --bind=enter:accept \
            --bind="ctrl-a:reload(bash $toggle_script)+clear-query" \
            --preview='
                line={}
                if [[ "$line" == "✖ Abort" ]]; then
                    echo "Exit without action";
                else
                    # Extract full branch name (after tab)
                    branch=$(echo "$line" | cut -f2)
                    echo "Branch: origin/$branch";
                    echo "";
                    echo "Recent commits:";
                    git log --oneline --color=always -n 15 "origin/$branch" 2>/dev/null || echo "No commits found";
                fi
            ' \
            --preview-window=right:35% \
            < "$initial_input_file"
    ) </dev/tty || true

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
    # 7. Extract branch names and confirm deletion
    # -----------------------------
    local branches_to_delete=()
    while IFS= read -r line; do
        # Skip abort option
        if [[ "$line" == "✖ Abort" ]]; then
            continue
        fi
        # Extract full branch name (after tab)
        local branch_name
        branch_name=$(echo "$line" | cut -f2)
        if [[ -n "$branch_name" ]]; then
            branches_to_delete+=("$branch_name")
        fi
    done <<< "$selection"

    if [[ ${#branches_to_delete[@]} -eq 0 ]]; then
        echo "No branches selected."
        return 0
    fi

    echo ""
    echo "Selected branches to delete from remote:"
    for branch in "${branches_to_delete[@]}"; do
        echo "  - origin/$branch"
    done
    echo ""

    prompt_read "Delete these ${#branches_to_delete[@]} branch(es) from remote? (y/N): " confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            echo "Deleting branches..."
            for branch in "${branches_to_delete[@]}"; do
                echo "Deleting origin/$branch ..."
                if git push origin --delete "$branch" 2>/dev/null; then
                    echo "✓ Deleted origin/$branch"
                else
                    echo "✗ Failed to delete origin/$branch"
                fi
            done
            ;;
        *)
            echo "Deletion cancelled."
            ;;
    esac
}
