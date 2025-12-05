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
