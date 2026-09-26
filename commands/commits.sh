#!/usr/bin/env bash

# Source common utilities
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_utils.sh
source "$SOURCE_DIR/_utils.sh"

# List the current branch's own commits and optionally revert selected ones
commits() {
    if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
        echo "gitbash ${FUNCNAME[0]} v$VERSION"
        return 0
    fi
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        gb_help << 'EOF'
Usage: commits [-a|--all] [-y|--yes] [COUNT]

List the commits made on the current branch with option to revert selected ones.

On a feature branch only the commits that are not in the base branch are
shown. On the base branch its own history is shown (--first-parent), so
merged branches appear as their merge commit.

Arguments:
  COUNT         Number of commits to show (default: 20)

Options:
  -a, --all     Show all recent commits reachable from HEAD
  -y, --yes     Revert the selected commits without asking again

Navigation:
  ↑/↓           Navigate through commits
  TAB           Select/deselect commit for revert
  Enter         Revert selected commit(s)
  ESC/Ctrl-C    Exit without action

Notes:
  - If the upstream has new commits, offers to fast-forward first
  - Preview shows the full commit diff
  - Selected commits are reverted newest first, whatever order you picked them in
  - Merge commits are reverted against their first parent (the branch they were merged into)
  - Each revert creates a new commit

Examples:
  $ commits
  $ commits 50
  $ commits --all

Requirements:
  - Must be in a git repository
  - fzf (fuzzy finder)

EOF
        return 0
    fi

    require_git_repo || return 1

    local all=false count=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all) all=true ;;
            -y|--yes) export GITBASH_ASSUME_YES=1 ;;
            -*) print_error "Unknown option '$1'. See 'commits --help'."; return 1 ;;
            *)
                if [[ -n "$count" ]]; then
                    print_error "Unexpected argument '$1'. See 'commits --help'."
                    return 1
                fi
                count="$1"
                ;;
        esac
        shift
    done
    count="${count:-20}"
    if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
        print_error "COUNT must be a positive number (got '$count')."
        return 1
    fi
    require_fzf || return 1

    # Offer to pull remote commits first, so they show up (and can be reverted)
    gb_offer_fast_forward || true

    local current_branch
    current_branch=$(gb_current_branch) || current_branch="(detached HEAD)"

    # -----------------------------
    # Which commits: the branch's own (not in the base branch) or, on the
    # base branch, its first-parent history
    # -----------------------------
    local log_args=() scope="last $count commits" empty_hint="" base_branch base_ref
    if [[ "$all" == false ]] && base_branch=$(gb_base_branch 2>/dev/null); then
        base_ref=$(gb_base_ref "$base_branch")
        if [[ "$current_branch" == "$base_branch" ]]; then
            log_args=(--first-parent)
            scope="last $count commits on '$base_branch' (merged branches as merge commits)"
        elif git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
            log_args=(--not "$base_ref")
            # Also exclude the local base branch when it is ahead of the remote one
            if [[ "$base_ref" != "$base_branch" ]] &&
               git show-ref --verify --quiet "refs/heads/$base_branch"; then
                log_args+=("$base_branch")
            fi
            scope="commits not in '$base_ref' (up to $count)"
            empty_hint="No commits on '$current_branch' that are not in '$base_ref'. Use 'commits --all' to show all recent commits."
        fi
    fi

    # -----------------------------
    # Build commit list (fields separated by \x1f, subject last)
    # -----------------------------
    local commit_list="" hash date author subject
    while IFS=$'\x1f' read -r hash date author subject; do
        [[ -z "$hash" ]] && continue
        if [[ ${#subject} -gt 60 ]]; then
            subject="${subject:0:57}..."
        fi
        commit_list+=$(printf "%-10s  %-60s  %-15s  %s" "$hash" "$subject" "$date" "$author")
        commit_list+=$'\t'"$hash"$'\n'
    done < <(git log -n "$count" --format='%h%x1f%cr%x1f%an%x1f%s' HEAD ${log_args[@]+"${log_args[@]}"} 2>/dev/null)

    if [[ -z "$commit_list" ]]; then
        echo "${empty_hint:-No commits found.}"
        return 0
    fi

    local pager preview
    pager=$(gb_diff_pager)
    preview='
        hash=$(printf "%s" {} | cut -f2)
        git show --stat --color=$GB_COLOR "$hash" 2>/dev/null
        echo
        echo "─────────────────────────────────────────────────────"
        echo
        git show --color=$GB_COLOR --format= "$hash" 2>/dev/null | head -300 | __PAGER__'
    preview="${preview//__PAGER__/$pager}"

    local selection
    selection=$(run_fzf \
        --prompt="Commits on '$current_branch' > " \
        -i \
        --reverse \
        --border \
        --header="[TAB] select for revert | [Enter] revert selected | [ESC] exit
Showing $scope" \
        --multi \
        --delimiter=$'\t' \
        --with-nth=1 \
        --preview="$preview" \
        --preview-window=right:50% \
        <<< "$commit_list"
    ) || true

    if [[ -z "$selection" ]]; then
        echo "Exited."
        return 0
    fi

    # -----------------------------
    # Order newest first (fzf returns them in the order they were picked)
    # -----------------------------
    local picked=() line
    while IFS= read -r line; do
        hash=$(printf '%s' "$line" | cut -f2)
        [[ -n "$hash" ]] && picked+=("$hash")
    done <<< "$selection"

    # Walk the history newest first and keep the picked commits in that order
    local to_revert=() full picked_full=" " short
    for short in "${picked[@]}"; do
        picked_full+="$(git rev-parse --verify --quiet "$short^{commit}") "
    done
    while IFS= read -r full; do
        [[ "$picked_full" == *" $full "* ]] && to_revert+=("$full")
        [[ ${#to_revert[@]} -eq ${#picked[@]} ]] && break
    done < <(git rev-list --topo-order HEAD 2>/dev/null)

    if [[ ${#to_revert[@]} -eq 0 ]]; then
        echo "No commits selected."
        return 0
    fi

    echo
    echo "Commits to revert (newest first):"
    for hash in "${to_revert[@]}"; do
        echo "  - $(git log -1 --format='%h %s' "$hash")"
    done
    echo

    if ! gb_confirm "Revert these ${#to_revert[@]} commit(s)?" n; then
        echo "Revert cancelled."
        return 0
    fi

    local parents revert_args
    for hash in "${to_revert[@]}"; do
        revert_args=(--no-edit)
        parents=$(git rev-list --parents -n 1 "$hash" | wc -w | tr -d ' ')
        if [[ "$parents" -gt 2 ]]; then
            print_info "$(git rev-parse --short "$hash") is a merge commit - reverting it against its first parent."
            revert_args+=(-m 1)
        fi
        if git revert "${revert_args[@]}" "$hash"; then
            print_success "Reverted $(git rev-parse --short "$hash")"
        else
            if git rev-parse --verify --quiet REVERT_HEAD >/dev/null; then
                print_error "Reverting $(git rev-parse --short "$hash") stopped with conflicts."
                echo "  Resolve them and run 'git revert --continue', or 'git revert --abort' to cancel this revert." >&2
            else
                print_error "Failed to revert $(git rev-parse --short "$hash")."
            fi
            return 1
        fi
    done
    echo
    print_success "All selected commits reverted."
}
