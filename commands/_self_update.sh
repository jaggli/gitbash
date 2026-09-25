#!/usr/bin/env bash
# Self-update for gitbash: 'gitbash --update' and the background update check.
# Sourced by bin/gitbash; needs SCRIPT_DIR, GITBASH_BIN and VERSION.

GB_REPO="jaggli/gitbash"
GB_UPDATE_CHECK_INTERVAL=86400   # look for a new version at most once a day
GB_UPDATE_PROMPT_INTERVAL=172800 # ask about it at most every other day

# GITBASH_NO_UPDATE_CHECKS from the environment wins over the config files
_GB_ENV_NO_UPDATE_CHECKS="${GITBASH_NO_UPDATE_CHECKS:-}"

# =============================================================================
# Install method
# =============================================================================

# Directory of a global package manager install of gitbash, symlinks resolved
_gb_global_package_dir() {
    local root
    root=$("$1" root -g 2>/dev/null) || return 1
    [[ -n "$root" ]] || return 1
    (cd -P "$root/gitbash" 2>/dev/null && pwd)
}

# How this copy of gitbash was installed: npm, pnpm, npx, package, script, git or unknown
gb_install_method() {
    case "$SCRIPT_DIR" in
        */_npx/*)
            echo "npx"
            return 0
            ;;
        */node_modules/gitbash)
            local pm
            for pm in npm pnpm; do
                if command -v "$pm" >/dev/null 2>&1 &&
                   [[ "$(_gb_global_package_dir "$pm")" == "$SCRIPT_DIR" ]]; then
                    echo "$pm"
                    return 0
                fi
            done
            # A dependency of some project, or a package manager we don't know
            echo "package"
            return 0
            ;;
    esac
    if [[ -f "$SCRIPT_DIR/.gitbash-install" ]]; then
        echo "script"
    elif [[ -e "$SCRIPT_DIR/.git" ]]; then
        echo "git"
    elif [[ -f "$SCRIPT_DIR/package.json" && ! -e "$SCRIPT_DIR/README.md" ]]; then
        # Installed by an install.sh that did not leave a marker yet
        echo "script"
    else
        echo "unknown"
    fi
}

# =============================================================================
# State (~/.local/state/gitbash/update-check)
# =============================================================================

_gb_update_state_file() {
    echo "${XDG_STATE_HOME:-$HOME/.local/state}/gitbash/update-check"
}

# Read the state into _GB_UC_CHECKED, _GB_UC_LATEST, _GB_UC_PROMPTED and _GB_UC_SKIPPED
_gb_update_state_load() {
    local file key value
    file=$(_gb_update_state_file)
    _GB_UC_CHECKED=0 _GB_UC_LATEST="" _GB_UC_PROMPTED=0 _GB_UC_SKIPPED=""
    [[ -f "$file" ]] || return 0
    while IFS='=' read -r key value; do
        case "$key" in
            checked) [[ "$value" =~ ^[0-9]+$ ]] && _GB_UC_CHECKED="$value" ;;
            latest) _GB_UC_LATEST="$value" ;;
            prompted) [[ "$value" =~ ^[0-9]+$ ]] && _GB_UC_PROMPTED="$value" ;;
            skipped) _GB_UC_SKIPPED="$value" ;;
        esac
    done < "$file"
}

# Set one value, keeping the others (re-read first: a background check may have written)
# Usage: _gb_update_state_set checked|latest|prompted|skipped <value>
_gb_update_state_set() {
    local file dir tmp
    file=$(_gb_update_state_file)
    dir=$(dirname "$file")
    _gb_update_state_load
    case "$1" in
        checked) _GB_UC_CHECKED="$2" ;;
        latest) _GB_UC_LATEST="$2" ;;
        prompted) _GB_UC_PROMPTED="$2" ;;
        skipped) _GB_UC_SKIPPED="$2" ;;
    esac
    mkdir -p "$dir" 2>/dev/null || return 1
    tmp=$(mktemp "$dir/.update-check.XXXXXX" 2>/dev/null) || return 1
    if ! printf 'checked=%s\nlatest=%s\nprompted=%s\nskipped=%s\n' \
            "$_GB_UC_CHECKED" "$_GB_UC_LATEST" "$_GB_UC_PROMPTED" "$_GB_UC_SKIPPED" > "$tmp" ||
       ! mv -f "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
}

_gb_now() {
    if [[ -n "${EPOCHSECONDS:-}" ]]; then
        echo "$EPOCHSECONDS"
    else
        date +%s
    fi
}

# =============================================================================
# Versions
# =============================================================================

# Print the contents of a URL
_gb_fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 10 "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- -T 10 "$1"
    else
        return 1
    fi
}

# Print the version of the latest GitHub release, e.g. 2.1.0
gb_latest_version() {
    local json tag
    json=$(_gb_fetch "https://api.github.com/repos/$GB_REPO/releases/latest" 2>/dev/null) || return 1
    tag=$(printf '%s\n' "$json" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
    tag="${tag#v}"
    [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    echo "$tag"
}

# Returns 0 if version $1 is newer than the running one
_gb_is_newer() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! _gb_version_ge "$VERSION" "$1"
}

# =============================================================================
# Update
# =============================================================================

# Install version $1 the way this copy was installed
gb_self_update_to() {
    local latest="$1" method
    method=$(gb_install_method)
    case "$method" in
        npm|pnpm)
            local -a cmd=(npm install -g "gitbash@$latest")
            [[ "$method" == "pnpm" ]] && cmd=(pnpm add -g "gitbash@$latest")
            print_info "Running: ${cmd[*]}"
            if ! "${cmd[@]}"; then
                print_error "Update failed. Run '${cmd[*]}' yourself (it may need more permissions)."
                return 1
            fi
            ;;
        script)
            _gb_self_update_script "$latest" || return 1
            ;;
        npx)
            print_info "gitbash runs through npx: use 'npx gitbash@latest' to get the newest version."
            return 1
            ;;
        git)
            print_info "gitbash runs from a git checkout ($SCRIPT_DIR): update it with 'git pull'."
            return 1
            ;;
        package)
            print_info "gitbash is a dependency in $SCRIPT_DIR: update it with your package manager."
            return 1
            ;;
        *)
            print_error "Could not detect how gitbash was installed ($SCRIPT_DIR)."
            echo "Reinstall it with 'npm i -g gitbash' or the install script (see the README)." >&2
            return 1
            ;;
    esac

    local installed
    installed=$(grep -o '"version": *"[^"]*"' "$SCRIPT_DIR/package.json" 2>/dev/null | head -1 | cut -d'"' -f4)
    if [[ "$installed" != "$latest" ]]; then
        print_error "Update finished, but gitbash in $SCRIPT_DIR is still at ${installed:-an unknown version}."
        return 1
    fi
    print_success "Updated gitbash $VERSION → $latest"
}

# Re-run the install script of the new release for the same locations
_gb_self_update_script() {
    local latest="$1" bin_dir="" key value tmp
    if [[ -f "$SCRIPT_DIR/.gitbash-install" ]]; then
        while IFS='=' read -r key value; do
            [[ "$key" == "bin_dir" ]] && bin_dir="$value"
        done < "$SCRIPT_DIR/.gitbash-install"
    fi
    bin_dir="${bin_dir:-$HOME/.local/bin}"

    local -a vars=(GITBASH_VERSION="$latest" GITBASH_INSTALL_DIR="$SCRIPT_DIR" GITBASH_BIN_DIR="$bin_dir")
    local hint="curl -fsSL https://raw.githubusercontent.com/$GB_REPO/main/install.sh | sudo ${vars[*]} sh"
    if [[ ! -w "$(dirname "$SCRIPT_DIR")" ]]; then
        print_error "No permission to write to $(dirname "$SCRIPT_DIR"). Update with:"
        echo "  $hint" >&2
        return 1
    fi

    tmp=$(mktemp 2>/dev/null || mktemp -t gitbash) || return 1
    if ! _gb_fetch "https://raw.githubusercontent.com/$GB_REPO/v$latest/install.sh" > "$tmp" 2>/dev/null ||
       [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        print_error "Could not download the install script of gitbash $latest."
        return 1
    fi
    print_info "Running the install script of gitbash $latest"
    if ! env "${vars[@]}" sh "$tmp"; then
        rm -f "$tmp"
        print_error "Update failed."
        return 1
    fi
    rm -f "$tmp"
}

# gitbash --update
gb_self_update() {
    local latest
    print_info "Checking for updates..."
    if ! latest=$(gb_latest_version); then
        print_error "Could not check for updates (no network, or GitHub is not reachable)."
        return 1
    fi
    _gb_update_state_set checked "$(_gb_now)"
    _gb_update_state_set latest "$latest"
    if ! _gb_is_newer "$latest"; then
        print_success "gitbash $VERSION is up to date."
        return 0
    fi
    gb_self_update_to "$latest"
}

# =============================================================================
# Background check
# =============================================================================

# Returns 0 if update checks are on: not turned off, not in CI, not a git checkout
gb_update_checks_enabled() {
    case "$_GB_ENV_NO_UPDATE_CHECKS" in
        ""|no|0|false) ;;
        *) return 1 ;;
    esac
    [[ "${GITBASH_NO_UPDATE_CHECKS:-no}" == "yes" ]] && return 1
    local var
    for var in CI CONTINUOUS_INTEGRATION BUILD_NUMBER GITHUB_ACTIONS GITLAB_CI TF_BUILD \
               JENKINS_URL BUILDKITE CIRCLECI TRAVIS TEAMCITY_VERSION BITBUCKET_BUILD_NUMBER; do
        case "${!var:-}" in
            ""|false|0) ;;
            *) return 1 ;;
        esac
    done
    [[ ! -e "$SCRIPT_DIR/.git" ]]
}

# Run before a command: start a background check when one is due, and offer a
# known new version (at most every other day, never again for a skipped one).
# On a successful update, runs the command with the new version instead.
# Usage: gb_update_check <command> [args...]
gb_update_check() {
    gb_update_checks_enabled || return 0

    local now
    now=$(_gb_now)
    _gb_update_state_load
    if (( now - _GB_UC_CHECKED >= GB_UPDATE_CHECK_INTERVAL || _GB_UC_CHECKED > now )); then
        _gb_update_state_set checked "$now"
        (
            local latest
            latest=$(gb_latest_version) && _gb_update_state_set latest "$latest"
        ) < /dev/null > /dev/null 2>&1 &
    fi

    local latest="$_GB_UC_LATEST"
    _gb_is_newer "$latest" || return 0
    [[ "$latest" != "$_GB_UC_SKIPPED" ]] || return 0
    (( now - _GB_UC_PROMPTED >= GB_UPDATE_PROMPT_INTERVAL || _GB_UC_PROMPTED > now )) || return 0
    # Only ask people at a terminal, never scripts
    [[ -t 0 && -t 1 && -t 2 && "${GITBASH_ASSUME_YES:-}" != "1" ]] || return 0
    local arg
    for arg in "${@:2}"; do
        [[ "$arg" == "-y" || "$arg" == "--yes" ]] && return 0
    done

    _gb_update_state_set prompted "$now"
    print_info "gitbash $latest is available (you have $VERSION)."
    local choice
    gb_choice choice "Update now? [y]es, [n]ot now, [s]kip this version (y/N/s):" "yns" "n"
    case "$choice" in
        y)
            if gb_self_update_to "$latest"; then
                echo
                exec "$GITBASH_BIN" "$@"
            fi
            echo
            ;;
        s)
            _gb_update_state_set skipped "$latest"
            print_info "You won't be asked about $latest again. Run 'gitbash --update' to update any time."
            echo
            ;;
        *)
            print_info "Run 'gitbash --update' to update any time."
            echo
            ;;
    esac
    return 0
}
