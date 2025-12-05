#!/usr/bin/env bash
# shellcheck disable=SC2155
# Common utilities for gitbash commands - compatible with bash and zsh

# Color codes for consistent output
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# Print success message (green checkmark)
print_success() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $*"
}

# Print error message (red X)
print_error() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $*" >&2
}

# Print warning message (yellow warning)
print_warning() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $*"
}

# Print info message (blue)
print_info() {
    echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} $*"
}

# Portable read with prompt that works in both bash and zsh
# Usage: prompt_read "prompt text" variable_name
# The result is stored in the variable name provided
prompt_read() {
    local prompt="$1"
    local varname="$2"
    
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        # zsh: use read with ?prompt syntax
        read -r "${varname}?${prompt}"
    else
        # bash: use read -p
        read -rp "$prompt" "$varname"
    fi
}

# Portable read with readline editing (for defaults)
# Usage: prompt_read_edit "prompt text" variable_name
prompt_read_edit() {
    local prompt="$1"
    local varname="$2"
    
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        # zsh: use vared or read with ?prompt
        read -r "${varname}?${prompt}"
    else
        # bash: use read -e -p
        read -e -rp "$prompt" "$varname"
    fi
}

# Check if fzf is installed, offer to install if not
# Returns 0 if fzf is available, 1 if not
require_fzf() {
    if command -v fzf >/dev/null 2>&1; then
        return 0
    fi

    print_error "fzf is not installed."
    
    local ans
    prompt_read "Install fzf with Homebrew? (y/N): " ans
    case "$ans" in
        [yY][eE][sS]|[yY])
            echo "Installing fzf with brew..."
            if ! command -v brew >/dev/null 2>&1; then
                print_error "Homebrew is not installed. Aborting."
                return 1
            fi
            if brew install fzf; then
                # Optional: install shell integrations automatically
                if [[ -f "$(brew --prefix)/opt/fzf/install" ]]; then
                    echo "Running fzf install script..."
                    yes | "$(brew --prefix)/opt/fzf/install"
                fi
                print_success "fzf installed successfully."
                return 0
            else
                print_error "fzf install failed. Aborting."
                return 1
            fi
            ;;
        *)
            echo "Aborted (skipped fzf installation)."
            return 1
            ;;
    esac
}

# Check if inside a git repository
# Returns 0 if in a git repo, 1 if not
require_git_repo() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi
    print_error "Not inside a git repository."
    return 1
}

# Get delta arguments based on theme setting
# Uses GITBASH_THEME: auto (default), dark, or light
_get_delta_args() {
    local theme="${GITBASH_THEME:-auto}"
    case "$theme" in
        light)
            echo "--light"
            ;;
        dark)
            echo "--dark"
            ;;
        *)
            # auto - let delta detect (no args needed, but we can add --light for lighter terminals)
            echo ""
            ;;
    esac
}

# Get bat arguments based on theme setting
_get_bat_args() {
    local theme="${GITBASH_THEME:-auto}"
    case "$theme" in
        light)
            echo "--theme=GitHub"
            ;;
        dark)
            echo "--theme=Dracula"
            ;;
        *)
            # auto - let bat detect
            echo ""
            ;;
    esac
}

# Get the diff command to use (delta if installed, otherwise git diff)
# Usage: get_diff_cmd
# Returns the command name to use for diffs
get_diff_cmd() {
    if command -v delta >/dev/null 2>&1; then
        local delta_args
        delta_args=$(_get_delta_args)
        if [[ -n "$delta_args" ]]; then
            echo "delta $delta_args"
        else
            echo "delta"
        fi
    else
        echo "git diff"
    fi
}

# Show a diff using delta if available, otherwise git diff
# Usage: show_diff [git diff args...]
# Example: show_diff --cached
# Example: show_diff HEAD~1
show_diff() {
    if command -v delta >/dev/null 2>&1; then
        local delta_args
        delta_args=$(_get_delta_args)
        # shellcheck disable=SC2086
        git diff "$@" | delta $delta_args
    else
        git diff "$@"
    fi
}
