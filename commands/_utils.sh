#!/usr/bin/env bash
# Common utilities for gitbash commands.
# Commands always run in a bash subprocess (bash 3.2+), started by bin/gitbash.

# Only load once, even if several command files source this file.
if [[ -n "${_GB_UTILS_LOADED:-}" ]]; then
    # shellcheck disable=SC2317  # exit only runs when executed instead of sourced
    return 0 2>/dev/null || exit 0
fi
_GB_UTILS_LOADED=1

GB_FZF_MIN_VERSION="0.36.0"

# =============================================================================
# Output
# =============================================================================

# Colors only when writing to a terminal and NO_COLOR is not set
_gb_color_ok() {
    [[ -z "${NO_COLOR:-}" && -t "$1" ]]
}

# NO_COLOR (https://no-color.org): a non-empty value turns off all colors.
# GB_COLOR is the --color value for git and bat in fzf previews; it is
# exported because previews run in a separate bash started by fzf.
if [[ -n "${NO_COLOR:-}" ]]; then
    GB_COLOR="never"
    # Also for git's own output (added to any GIT_CONFIG_* entries already set)
    _gb_n="${GIT_CONFIG_COUNT:-0}"
    export "GIT_CONFIG_KEY_$_gb_n=color.ui" "GIT_CONFIG_VALUE_$_gb_n=never"
    export GIT_CONFIG_COUNT=$((_gb_n + 1))
    unset _gb_n
else
    GB_COLOR="always"
fi
export GB_COLOR

_gb_print() {
    local fd="$1" color="$2" symbol="$3"
    shift 3
    if _gb_color_ok "$fd"; then
        printf '\033[%sm%s\033[0m %s\n' "$color" "$symbol" "$*" >&"$fd"
    else
        printf '%s %s\n' "$symbol" "$*" >&"$fd"
    fi
}

print_success() { _gb_print 1 "0;32" "✓" "$@"; }
print_info()    { _gb_print 1 "0;34" "ℹ" "$@"; }
print_warning() { _gb_print 2 "0;33" "⚠" "$@"; }
print_error()   { _gb_print 2 "0;31" "✗" "$@"; }

# Print help text from stdin, coloring the section headings
# ("Options:", "See also:", ...) and the "Usage:" label.
gb_help() {
    if ! _gb_color_ok 1; then
        cat
        return 0
    fi
    local h=$'\033[1;38;5;209m' r=$'\033[0m' line
    local heading='^[A-Z][A-Za-z ()]*:$'
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $heading ]]; then
            printf '%s%s%s\n' "$h" "$line" "$r"
        elif [[ "$line" == "Usage: "* ]]; then
            printf '%sUsage:%s%s\n' "$h" "$r" "${line#Usage:}"
        else
            printf '%s\n' "$line"
        fi
    done
}

# =============================================================================
# Prompts
# =============================================================================

# Read a line into a variable. Returns non-zero on EOF.
# Usage: prompt_read "prompt text" variable_name
prompt_read() {
    local __prompt="$1" __var="$2" __value=""
    printf '%s' "$__prompt" >&2
    if IFS= read -r __value; then
        printf -v "$__var" '%s' "$__value"
        return 0
    fi
    printf -v "$__var" '%s' "$__value"
    echo >&2
    return 1
}

# Yes/no question. Returns 0 for yes, 1 for no. EOF or Enter picks the default.
# GITBASH_ASSUME_YES=1 (set by --yes flags) answers yes, unless --strict is given.
# Usage: gb_confirm [--strict] "Question?" y|n
gb_confirm() {
    local strict=false
    if [[ "$1" == "--strict" ]]; then
        strict=true
        shift
    fi
    local question="$1" default="${2:-n}" hint answer
    if [[ "$strict" == false && "${GITBASH_ASSUME_YES:-}" == "1" ]]; then
        return 0
    fi
    if [[ "$default" == "y" ]]; then hint="Y/n"; else hint="y/N"; fi
    while true; do
        prompt_read "$question ($hint): " answer || answer=""
        case "$answer" in
            "") [[ "$default" == "y" ]]; return ;;
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) echo "Please answer y or n." >&2 ;;
        esac
    done
}

# Single-letter choice. EOF or Enter picks the default letter.
# Usage: gb_choice var_name "Question [a]/[b]?" "ab" "a"
gb_choice() {
    local __var="$1" question="$2" letters="$3" default="$4" __ans
    while true; do
        prompt_read "$question " __ans || __ans=""
        __ans=$(printf '%s' "${__ans:0:1}" | tr '[:upper:]' '[:lower:]')
        [[ -z "$__ans" ]] && __ans="$default"
        if [[ -n "$__ans" && "$letters" == *"$__ans"* ]]; then
            printf -v "$__var" '%s' "$__ans"
            return 0
        fi
        echo "Please answer one of: $(printf '%s' "$letters" | sed 's/./& /g')" >&2
    done
}

# =============================================================================
# Configuration (parsed, never sourced)
# =============================================================================

GB_CONFIG_KEYS="GITBASH_CREATE_BRANCH_PREFIX GITBASH_FEATURE_BRANCH_PREFIX GITBASH_MERGE_COMMAND \
GITBASH_CREATE_NO_ISSUE_PARSING GITBASH_CREATE_ISSUE_PARSING_FALLBACK GITBASH_CREATE_AUTO_PUSH \
GITBASH_THEME GITBASH_STALE_MONTHS GITBASH_CLEANUP_DAYS GITBASH_PROTECTED_BRANCHES \
GITBASH_BASE_BRANCH GITBASH_REMOTE GITBASH_NO_UPDATE_CHECKS"

_gb_config_key_allowed() {
    [[ " $GB_CONFIG_KEYS " == *" $1 "* ]]
}

# Print the valid KEY=value entries of a config file, one per line.
# Nothing in the file is executed or expanded.
# Usage: _gb_config_entries <file> [warn]
_gb_config_entries() {
    local file="$1" warn="${2:-}" line key value n=0
    local re_assign='^[[:space:]]*(export[[:space:]]+)?(GITBASH_[A-Z_]+)=(.*)$'
    local re_dq='^"([^"$`\\]*)"[[:space:]]*(#.*)?$'
    local re_sq="^'([^']*)'[[:space:]]*(#.*)?\$"
    local re_bare='^([^[:space:]#"'"'"'$`\\]*)[[:space:]]*(#.*)?$'
    [[ -f "$file" && -r "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        line="${line%$'\r'}"
        # Skip blank lines and comments
        [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
        if ! [[ "$line" =~ $re_assign ]]; then
            [[ -n "$warn" ]] && print_warning "$file:$n: ignored (config files are no longer executed): $line"
            continue
        fi
        key="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]}"
        if [[ "$value" =~ $re_dq || "$value" =~ $re_sq || "$value" =~ $re_bare ]]; then
            value="${BASH_REMATCH[1]}"
        else
            [[ -n "$warn" ]] && print_warning "$file:$n: ignored $key (value must be a plain string without \$, \`, \\ or quotes)"
            continue
        fi
        if ! _gb_config_key_allowed "$key"; then
            [[ -n "$warn" ]] && print_warning "$file:$n: ignored unknown setting $key"
            continue
        fi
        printf '%s=%s\n' "$key" "$value"
    done < "$file"
}

gb_global_config_file() { echo "$HOME/.gitbashrc"; }

# Load ~/.gitbashrc, then <repo>/.gitbashrc, then <repo>/.gitbashrc-user.
gb_load_config() {
    local repo_root="" file scope key value
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root=""
    for scope in global local user; do
        case "$scope" in
            global) file=$(gb_global_config_file) ;;
            local) [[ -n "$repo_root" ]] || continue; file="$repo_root/.gitbashrc" ;;
            user) [[ -n "$repo_root" ]] || continue; file="$repo_root/.gitbashrc-user" ;;
        esac
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            if [[ "$key" == "GITBASH_MERGE_COMMAND" && "$scope" == "local" ]]; then
                print_warning "$file: ignored GITBASH_MERGE_COMMAND (a repository cannot choose which program runs; set it in ~/.gitbashrc or .gitbashrc-user)"
                continue
            fi
            printf -v "$key" '%s' "$value"
        done < <(_gb_config_entries "$file" warn)
    done
    _gb_normalize_config
}

# Apply defaults and validate values
_gb_normalize_config() {
    # Branch prefix, with backward compatibility for GITBASH_FEATURE_BRANCH_PREFIX
    if [[ -z "${GITBASH_CREATE_BRANCH_PREFIX:-}" && -n "${GITBASH_FEATURE_BRANCH_PREFIX:-}" ]]; then
        GITBASH_CREATE_BRANCH_PREFIX="${GITBASH_FEATURE_BRANCH_PREFIX#feature/}"
    fi
    GITBASH_CREATE_BRANCH_PREFIX="${GITBASH_CREATE_BRANCH_PREFIX:-}"
    GITBASH_CREATE_BRANCH_PREFIX="${GITBASH_CREATE_BRANCH_PREFIX%/}"

    GITBASH_MERGE_COMMAND="${GITBASH_MERGE_COMMAND:-fork}"
    GITBASH_CREATE_ISSUE_PARSING_FALLBACK="${GITBASH_CREATE_ISSUE_PARSING_FALLBACK:-NOISSUE}"
    GITBASH_PROTECTED_BRANCHES="${GITBASH_PROTECTED_BRANCHES:-main master develop release/*}"
    GITBASH_BASE_BRANCH="${GITBASH_BASE_BRANCH:-}"

    case "${GITBASH_CREATE_NO_ISSUE_PARSING:-no}" in
        yes|no) GITBASH_CREATE_NO_ISSUE_PARSING="${GITBASH_CREATE_NO_ISSUE_PARSING:-no}" ;;
        *) print_warning "Invalid GITBASH_CREATE_NO_ISSUE_PARSING '$GITBASH_CREATE_NO_ISSUE_PARSING', using 'no'."
           GITBASH_CREATE_NO_ISSUE_PARSING="no" ;;
    esac
    case "${GITBASH_CREATE_AUTO_PUSH:-yes}" in
        yes|no) GITBASH_CREATE_AUTO_PUSH="${GITBASH_CREATE_AUTO_PUSH:-yes}" ;;
        *) print_warning "Invalid GITBASH_CREATE_AUTO_PUSH '$GITBASH_CREATE_AUTO_PUSH', using 'yes'."
           GITBASH_CREATE_AUTO_PUSH="yes" ;;
    esac
    case "${GITBASH_THEME:-auto}" in
        auto|dark|light) GITBASH_THEME="${GITBASH_THEME:-auto}" ;;
        *) print_warning "Invalid GITBASH_THEME '$GITBASH_THEME', using 'auto'."
           GITBASH_THEME="auto" ;;
    esac
    case "${GITBASH_NO_UPDATE_CHECKS:-no}" in
        yes|1|true) GITBASH_NO_UPDATE_CHECKS="yes" ;;
        no|0|false) GITBASH_NO_UPDATE_CHECKS="no" ;;
        *) print_warning "Invalid GITBASH_NO_UPDATE_CHECKS '$GITBASH_NO_UPDATE_CHECKS', using 'no'."
           GITBASH_NO_UPDATE_CHECKS="no" ;;
    esac
    if ! [[ "${GITBASH_STALE_MONTHS:-3}" =~ ^[1-9][0-9]*$ ]]; then
        print_warning "Invalid GITBASH_STALE_MONTHS '$GITBASH_STALE_MONTHS', using 3."
        GITBASH_STALE_MONTHS=3
    fi
    GITBASH_STALE_MONTHS="${GITBASH_STALE_MONTHS:-3}"
    if ! [[ "${GITBASH_CLEANUP_DAYS:-7}" =~ ^[1-9][0-9]*$ ]]; then
        print_warning "Invalid GITBASH_CLEANUP_DAYS '$GITBASH_CLEANUP_DAYS', using 7."
        GITBASH_CLEANUP_DAYS=7
    fi
    GITBASH_CLEANUP_DAYS="${GITBASH_CLEANUP_DAYS:-7}"
    if ! [[ "${GITBASH_REMOTE:-origin}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        print_warning "Invalid GITBASH_REMOTE '$GITBASH_REMOTE', using 'origin'."
        GITBASH_REMOTE="origin"
    fi
    GITBASH_REMOTE="${GITBASH_REMOTE:-origin}"
}

# =============================================================================
# Requirements
# =============================================================================

require_git_repo() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi
    print_error "Not inside a git repository."
    return 1
}

# Returns 0 if version $1 >= version $2 (dotted numbers)
_gb_version_ge() {
    local IFS=.
    local -a a b
    read -r -a a <<< "$1"
    read -r -a b <<< "$2"
    local i x y
    for i in 0 1 2; do
        x="${a[$i]:-0}"; y="${b[$i]:-0}"
        x="${x%%[!0-9]*}"; y="${y%%[!0-9]*}"
        x="${x:-0}"; y="${y:-0}"
        if (( 10#$x > 10#$y )); then return 0; fi
        if (( 10#$x < 10#$y )); then return 1; fi
    done
    return 0
}

# Check that fzf is installed and recent enough
require_fzf() {
    if ! command -v fzf >/dev/null 2>&1; then
        print_error "fzf is not installed. Install it with 'brew install fzf' (macOS) or 'sudo apt install fzf' (Debian/Ubuntu)."
        return 1
    fi
    local version
    version=$(fzf --version 2>/dev/null | awk '{print $1}')
    if ! _gb_version_ge "$version" "$GB_FZF_MIN_VERSION"; then
        print_error "fzf $version is too old; gitbash needs fzf $GB_FZF_MIN_VERSION or newer."
        return 1
    fi
    return 0
}

# Run fzf isolated from the user's fzf defaults (which can change the output
# format), with previews and reloads executed by bash.
run_fzf() {
    local bash_path
    bash_path=$(command -v bash)
    FZF_DEFAULT_OPTS="" FZF_DEFAULT_OPTS_FILE="" SHELL="$bash_path" fzf "$@"
}

# =============================================================================
# Git helpers
# =============================================================================

gb_remote() {
    echo "${GITBASH_REMOTE:-origin}"
}

# Current branch name; fails on detached HEAD
gb_current_branch() {
    git symbolic-ref --quiet --short HEAD 2>/dev/null
}

# Detect the base branch: GITBASH_BASE_BRANCH, <remote>/HEAD, main, master
gb_base_branch() {
    local remote branch
    remote=$(gb_remote)
    if [[ -n "${GITBASH_BASE_BRANCH:-}" ]]; then
        echo "$GITBASH_BASE_BRANCH"
        return 0
    fi
    if branch=$(git symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null); then
        echo "${branch#"$remote"/}"
        return 0
    fi
    for branch in main master; do
        if git show-ref --verify --quiet "refs/heads/$branch" ||
           git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
            echo "$branch"
            return 0
        fi
    done
    return 1
}

# The ref to compare against: <remote>/<base> if it exists, else the local base
gb_base_ref() {
    local base="$1" remote
    remote=$(gb_remote)
    if git show-ref --verify --quiet "refs/remotes/$remote/$base"; then
        echo "$remote/$base"
    else
        echo "$base"
    fi
}

# Returns 0 if the branch is protected (base branch or GITBASH_PROTECTED_BRANCHES).
# Set GB_BASE beforehand to avoid detecting the base branch on every call.
gb_is_protected() {
    local branch="$1" base="${GB_BASE:-}" pattern
    [[ -z "$base" ]] && base=$(gb_base_branch 2>/dev/null)
    [[ -n "$base" && "$branch" == "$base" ]] && return 0
    local -a patterns
    IFS=' ,' read -r -a patterns <<< "${GITBASH_PROTECTED_BRANCHES:-main master develop release/*}"
    for pattern in ${patterns[@]+"${patterns[@]}"}; do
        # shellcheck disable=SC2053  # pattern is a glob on purpose
        [[ "$branch" == $pattern ]] && return 0
    done
    return 1
}

# Run another gitbash command (same installation)
gb_run() {
    "${GITBASH_BIN:-gitbash}" "$@"
}

# Fetch the current branch, sync with its remote counterpart and push.
# Never rebases or overwrites without asking.
# Usage: gb_sync_and_push [--amend] [--force-with-lease]
gb_sync_and_push() {
    local amend=false force=false arg
    for arg in "$@"; do
        case "$arg" in
            --amend) amend=true ;;
            --force-with-lease) force=true ;;
        esac
    done

    local remote branch
    remote=$(gb_remote)
    if ! branch=$(gb_current_branch); then
        print_error "Detached HEAD: check out a branch before pushing."
        return 1
    fi
    if ! git remote get-url "$remote" >/dev/null 2>&1; then
        print_error "No remote '$remote' configured."
        return 1
    fi

    local out
    if ! out=$(git ls-remote --heads "$remote" "refs/heads/$branch" 2>&1); then
        print_error "Could not reach '$remote':"
        printf '%s\n' "$out" >&2
        return 1
    fi

    # New branch: first push sets up tracking
    if [[ -z "$out" ]]; then
        print_info "Pushing new branch '$branch' to '$remote'..."
        if git push -u "$remote" "$branch"; then
            print_success "Pushed '$branch' to '$remote'."
            return 0
        fi
        print_error "Failed to push '$branch' to '$remote'."
        return 1
    fi

    if ! git fetch --quiet "$remote" "+refs/heads/$branch:refs/remotes/$remote/$branch"; then
        print_error "Failed to fetch '$remote/$branch'."
        return 1
    fi

    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD)
    remote_commit=$(git rev-parse "refs/remotes/$remote/$branch")

    if [[ "$local_commit" == "$remote_commit" ]]; then
        print_info "'$remote/$branch' is already up to date."
        return 0
    fi

    local push_args=()
    if [[ -z "$(git config "branch.$branch.remote" 2>/dev/null)" ]]; then
        push_args+=("-u")
    fi

    if git merge-base --is-ancestor "$remote_commit" "$local_commit"; then
        : # Ahead of the remote: plain push
    elif git merge-base --is-ancestor "$local_commit" "$remote_commit"; then
        print_info "'$remote/$branch' has new commits. Fast-forwarding..."
        if git merge --ff-only --quiet "refs/remotes/$remote/$branch"; then
            print_success "Up to date with '$remote/$branch'. Nothing to push."
            return 0
        fi
        print_error "Fast-forward failed."
        return 1
    else
        local ahead behind
        ahead=$(git rev-list --count "$remote_commit..$local_commit")
        behind=$(git rev-list --count "$local_commit..$remote_commit")
        if [[ "$amend" == true || "$force" == true ]]; then
            print_warning "'$remote/$branch' differs from your rewritten branch ($ahead local vs $behind remote commit(s))."
            if gb_confirm --strict "Overwrite '$remote/$branch' with your version (push --force-with-lease)?" n; then
                if git push "${push_args[@]+"${push_args[@]}"}" --force-with-lease="refs/heads/$branch:$remote_commit" "$remote" "$branch"; then
                    print_success "Force-pushed '$branch' to '$remote'."
                    return 0
                fi
                print_error "Force push failed (someone else may have pushed in the meantime)."
                return 1
            fi
            print_info "Not pushed."
            return 1
        fi

        print_warning "Your branch and '$remote/$branch' have diverged ($ahead local, $behind remote commit(s))."
        local choice
        gb_choice choice "[r]ebase onto '$remote/$branch', [m]erge it, or [a]bort? (r/m/A):" "rma" "a"
        case "$choice" in
            r)
                if ! git rebase --rebase-merges "refs/remotes/$remote/$branch"; then
                    print_error "Rebase stopped. Resolve the conflicts and run 'git rebase --continue', or 'git rebase --abort'."
                    return 1
                fi
                ;;
            m)
                if ! git merge --no-edit "refs/remotes/$remote/$branch"; then
                    print_error "Merge stopped. Resolve the conflicts and commit, or run 'git merge --abort'."
                    return 1
                fi
                ;;
            *)
                print_info "Not pushed."
                return 1
                ;;
        esac
    fi

    print_info "Pushing '$branch' to '$remote'..."
    if git push "${push_args[@]+"${push_args[@]}"}" "$remote" "$branch"; then
        print_success "Pushed '$branch' to '$remote'."
        return 0
    fi
    print_error "Failed to push '$branch' to '$remote'."
    return 1
}

# =============================================================================
# Previews
# =============================================================================

# Command that colors a diff read from stdin (delta if installed and colors are on)
gb_diff_pager() {
    if [[ "$GB_COLOR" == "always" ]] && command -v delta >/dev/null 2>&1; then
        case "${GITBASH_THEME:-auto}" in
            dark) echo "delta --dark" ;;
            light) echo "delta --light" ;;
            *) echo "delta" ;;
        esac
    else
        echo "cat"
    fi
}

# Command that shows a file with syntax highlighting (bat if installed)
gb_bat_cmd() {
    local bat=""
    if command -v bat >/dev/null 2>&1; then
        bat="bat"
    elif command -v batcat >/dev/null 2>&1; then
        bat="batcat"
    fi
    if [[ -z "$bat" ]]; then
        echo "cat"
        return 0
    fi
    case "${GITBASH_THEME:-auto}" in
        dark) echo "$bat --color=$GB_COLOR --style=numbers --theme=Dracula" ;;
        light) echo "$bat --color=$GB_COLOR --style=numbers --theme=GitHub" ;;
        *) echo "$bat --color=$GB_COLOR --style=numbers" ;;
    esac
}

# =============================================================================
# Misc
# =============================================================================

gb_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

gb_urlencode() {
    local LC_ALL=C
    local str="$1" out="" char code hex i
    for ((i = 0; i < ${#str}; i++)); do
        char="${str:i:1}"
        case "$char" in
            [a-zA-Z0-9._~/-]) out+="$char" ;;
            *)
                # bash 3.2 reads bytes >= 0x80 as negative numbers: keep the low 8 bits
                printf -v code '%d' "'$char"
                printf -v hex '%%%02X' "$((code & 255))"
                out+="$hex"
                ;;
        esac
    done
    printf '%s' "$out"
}

# Convert a remote URL to the repository's web URL (credentials and .git removed).
# Handles https://[user[:token]@]host/path, ssh://[user@]host[:port]/path and user@host:path.
gb_web_url() {
    local url="$1" scheme="https" rest host path
    case "$url" in
        http://*|https://*)
            scheme="${url%%://*}"
            rest="${url#*://}"
            host="${rest%%/*}"
            host="${host##*@}"
            path="${rest#*/}"
            ;;
        ssh://*)
            rest="${url#ssh://}"
            host="${rest%%/*}"
            host="${host##*@}"
            host="${host%%:*}"
            path="${rest#*/}"
            ;;
        *@*:*)
            host="${url%%:*}"
            host="${host##*@}"
            path="${url#*:}"
            ;;
        *)
            return 1
            ;;
    esac
    path="${path%/}"
    path="${path%.git}"
    if [[ -z "$host" || -z "$path" || ( -n "$rest" && "$path" == "$rest" ) ]]; then
        return 1
    fi

    # Azure DevOps SSH: ssh.dev.azure.com:v3/org/project/repo
    if [[ "$host" == "ssh.dev.azure.com" && "$path" == v3/*/*/* ]]; then
        local org project repo
        path="${path#v3/}"
        org="${path%%/*}"; path="${path#*/}"
        project="${path%%/*}"; repo="${path#*/}"
        echo "https://dev.azure.com/$org/$project/_git/$repo"
        return 0
    fi
    echo "$scheme://$host/$path"
}

# Open a URL in the browser, or print it if no opener is available
gb_open_url() {
    local url="$1"
    if command -v open >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then
        open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1
    else
        echo "$url"
    fi
}
