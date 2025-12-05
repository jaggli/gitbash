#!/usr/bin/env bash
# shellcheck disable=SC2155
# Common utilities for gitbash commands - compatible with bash and zsh

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

# Get the diff command to use (delta if installed, otherwise git diff)
# Usage: get_diff_cmd
# Returns the command name to use for diffs
get_diff_cmd() {
    if command -v delta >/dev/null 2>&1; then
        echo "delta --light"
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
        git diff "$@" | delta --light
    else
        git diff "$@"
    fi
}
