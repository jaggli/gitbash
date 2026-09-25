#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# Unix timestamp of N months ago
_stale_months_ago() {
    local months="$1" ts
    ts=$(date -v-"${months}m" +%s 2>/dev/null) ||
        ts=$(date -d "${months} months ago" +%s 2>/dev/null) ||
        ts=$(( $(date +%s) - months * 30 * 86400 ))
    echo "$ts"
}

stale() {
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
                gb_help << 'EOF'
Usage: stale [OPTIONS] [FILTER...]

Show remote branches ordered by last commit date (oldest first) and delete
the ones that are no longer needed.

Arguments:
  FILTER...     Optional search filter words to pre-fill fzf (joined with spaces)

Options:
  -h, --help      Show this help message
  -a, --all       Start in 'all branches' mode (default is stale mode)
  -m, --my        Pre-fill filter with your git username (from git config user.name)
  --json          Output branch data as JSON (non-interactive)
  --age=N         Override stale threshold in months (default: 3, configurable via GITBASH_STALE_MONTHS)

Protected branches (the base branch and GITBASH_PROTECTED_BRANCHES, default
"main master develop release/*") are never listed and cannot be deleted.

Navigation:
  ↑/↓           Navigate through branches
  TAB           Select/deselect branch (multi-select)
  Ctrl-T        Toggle between stale and all branches
  Enter         Delete selected branch(es) from the remote (asks first)
  ESC/Ctrl-C    Exit without action

Examples:
  $ stale
  $ stale --age=6
  $ stale --all
  $ stale --my
  $ stale Product refactoring
  $ stale --json

Output format:
  <branch-name>   <relative-date>   <last author>

Requirements:
  - Must be in a git repository
  - fzf (not required for --json)

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
                if ! [[ "$stale_months" =~ ^[1-9][0-9]*$ ]]; then
                    print_error "Invalid age value: $stale_months"
                    return 1
                fi
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                return 1
                ;;
            *)
                filter_args+=("$1")
                shift
                ;;
        esac
    done

    # -----------------------------
    # 1. Prerequisites
    # -----------------------------
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if [[ "$json_mode" == true ]]; then echo "[]"; else print_error "Not inside a git repository."; fi
        return 1
    fi
    if [[ "$json_mode" == false ]]; then
        require_fzf || return 1
    fi

    local filter=""
    if [[ "$my_mode" == true ]]; then
        filter=$(git config user.name)
        if [[ -z "$filter" && "$json_mode" == false ]]; then
            print_warning "git config user.name is not set."
        fi
    elif [[ ${#filter_args[@]} -gt 0 ]]; then
        filter="${filter_args[*]}"
    fi

    local remote
    remote=$(gb_remote)
    [[ "$json_mode" == false ]] && echo "Fetching latest from '$remote'..."
    if ! git fetch --prune --quiet "$remote" 2>/dev/null; then
        [[ "$json_mode" == false ]] && print_warning "Fetch failed; continuing with local data."
    fi
    GB_BASE=$(gb_base_branch 2>/dev/null) || GB_BASE=""

    # -----------------------------
    # 2. Build branch lists (oldest first)
    # -----------------------------
    local threshold_ago
    threshold_ago=$(_stale_months_ago "$stale_months")

    local max_len=65
    local all_list="" stale_list="" json="[" first=true
    local sep=$'\x1f' ref ts rel email name branch display row
    while IFS="$sep" read -r ref ts rel email name; do
        [[ -z "$ref" || "$ref" == "$remote" || "$ref" == "$remote/HEAD" ]] && continue
        branch="${ref#"$remote"/}"
        gb_is_protected "$branch" && continue

        if [[ "$json_mode" == true ]]; then
            if [[ "$all_mode" == true || "$ts" -lt "$threshold_ago" ]]; then
                email="${email#<}"
                email="${email%>}"
                [[ "$first" == true ]] && first=false || json+=","
                json+="{\"last_change_timestamp\":$ts,\"author_email\":\"$(gb_json_escape "$email")\",\"author_name\":\"$(gb_json_escape "$name")\",\"name\":\"$(gb_json_escape "$branch")\",\"last_change_relative\":\"$(gb_json_escape "$rel")\"}"
            fi
            continue
        fi

        display="$branch"
        if [[ ${#display} -gt $max_len ]]; then
            display="${display:0:$((max_len - 3))}..."
        fi
        row=$(printf "%-${max_len}s  %-20s %s" "$display" "$rel" "$name")
        row+=$'\t'"$branch"$'\n'
        all_list+="$row"
        if [[ "$ts" -lt "$threshold_ago" ]]; then
            stale_list+="$row"
        fi
    done < <(git for-each-ref --sort=committerdate \
        --format="%(refname:short)%1f%(committerdate:unix)%1f%(committerdate:relative)%1f%(authoremail)%1f%(authorname)" \
        "refs/remotes/$remote" 2>/dev/null)

    if [[ "$json_mode" == true ]]; then
        echo "$json]"
        return 0
    fi

    if [[ -z "$all_list" ]]; then
        echo "No deletable remote branches found."
        return 0
    fi

    # -----------------------------
    # 3. fzf with a stale/all toggle (Ctrl-T)
    # -----------------------------
    local abort_label="✖ Abort"
    local keys="[TAB] select | [Ctrl-T] toggle all/stale | [Enter] delete | [ESC] exit"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    {
        echo "══ Stale branches (>${stale_months}mo, oldest first) ══ $keys"
        printf '%s' "$stale_list"
        echo "$abort_label"
    } > "$tmp_dir/stale"
    {
        echo "══ All branches (oldest first) ══ $keys"
        printf '%s' "$all_list"
        echo "$abort_label"
    } > "$tmp_dir/all"
    if [[ "$all_mode" == true ]]; then echo "all" > "$tmp_dir/state"; else echo "stale" > "$tmp_dir/state"; fi
    cat > "$tmp_dir/toggle" << 'TOGGLE_EOF'
dir="$1"
if [[ "$(cat "$dir/state")" == "stale" ]]; then
    echo "all" > "$dir/state"
else
    echo "stale" > "$dir/state"
fi
cat "$dir/$(cat "$dir/state")"
TOGGLE_EOF

    local tmp_q remote_q
    printf -v tmp_q '%q' "$tmp_dir"
    printf -v remote_q '%q' "$remote"

    local selection
    selection=$(run_fzf \
            --query="$filter" \
            -i \
            --reverse \
            --border \
            --header-lines=1 \
            --multi \
            --delimiter=$'\t' \
            --with-nth=1 \
            --bind="ctrl-t:reload(bash $tmp_q/toggle $tmp_q)+clear-query" \
            --preview="
                branch=\$(printf '%s' {} | cut -f2)
                if [[ -z \"\$branch\" ]]; then echo 'Exit without action'; exit 0; fi
                echo \"Branch: $remote_q/\$branch\"
                echo
                echo 'Recent commits:'
                git log --oneline --color=\$GB_COLOR -n 15 \"refs/remotes/$remote_q/\$branch\" 2>/dev/null || echo 'No commits found'
            " \
            --preview-window=right:35% \
            < "$tmp_dir/$(cat "$tmp_dir/state")"
    ) || true
    rm -rf "$tmp_dir"

    if [[ -z "$selection" ]]; then
        echo "Exited."
        return 0
    fi

    # -----------------------------
    # 4. Confirm and delete
    # -----------------------------
    local branches_to_delete=() line
    while IFS= read -r line; do
        branch=$(printf '%s' "$line" | cut -f2)
        [[ -z "$branch" ]] && continue
        # Never delete protected branches, even if they got into the list somehow
        if gb_is_protected "$branch"; then
            print_warning "Skipping protected branch '$branch'."
            continue
        fi
        branches_to_delete+=("$branch")
    done <<< "$selection"

    if [[ ${#branches_to_delete[@]} -eq 0 ]]; then
        echo "Aborted."
        return 0
    fi

    echo
    echo "Selected branches to delete from '$remote':"
    printf '  - %s\n' "${branches_to_delete[@]}"
    echo

    if ! gb_confirm --strict "Delete these ${#branches_to_delete[@]} branch(es) from '$remote'? This cannot be undone from here." n; then
        echo "Deletion cancelled."
        return 0
    fi

    local failed=0 out
    for branch in "${branches_to_delete[@]}"; do
        if out=$(git push "$remote" --delete "$branch" 2>&1); then
            print_success "Deleted $remote/$branch"
        else
            print_error "Failed to delete $remote/$branch:"
            printf '%s\n' "$out" | sed 's/^/    /' >&2
            failed=$((failed + 1))
        fi
    done
    [[ $failed -eq 0 ]]
}
