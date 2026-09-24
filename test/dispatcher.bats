#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
}

@test "--version prints the package version" {
    run gb --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^gitbash\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "unknown commands are rejected" {
    run gb nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command 'nope'"* ]]
}

@test "internal files and paths are not runnable as commands" {
    run gb _utils
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]

    run gb ../commands/commit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "--init prints wrapper functions, not source lines" {
    run gb --init
    [ "$status" -eq 0 ]
    [[ "$output" == *"commit() { "*"/bin/gitbash commit \"\$@\"; }"* ]]
    [[ "$output" == *"switch() {"* ]]
    [[ "$output" != *"source "* ]]
}

@test "--init --prefix prefixes every function" {
    run gb --init --prefix=gb-
    [ "$status" -eq 0 ]
    [[ "$output" == *"gb-commit() {"* ]]
    [[ "$output" == *"gb-pr() {"* ]]
    [[ "$output" != *$'\n'"pr() {"* ]]
}

@test "--init rejects unsafe prefixes" {
    run gb --init '--prefix=a;b'
    [ "$status" -eq 1 ]
}

@test "wrappers from --init work in bash and keep the shell clean" {
    run bash -c 'eval "$("$0" "$1" --init)"; stash --version; declare -F prompt_read >/dev/null && echo LEAK || echo CLEAN' \
        "${GB_BASH:-bash}" "$GB"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gitbash stash v"* ]]
    [[ "$output" == *"CLEAN"* ]]
}

@test "wrappers from --init work in zsh" {
    command -v zsh >/dev/null || skip "zsh not installed"
    run zsh -c 'eval "$("$0" "$1" --init)"; stash --version' "${GB_BASH:-bash}" "$GB"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gitbash stash v"* ]]
}
