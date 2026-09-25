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

@test "help shows the banner with the version, also without arguments" {
    run gb --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'\__, |_|\__|_.__/'* ]]
    [[ "$output" =~ v[0-9]+\.[0-9]+\.[0-9]+\ -\ Interactive ]]
    [[ "$output" == *"Commands:"* ]]

    local help="$output"
    run gb
    [ "$status" -eq 0 ]
    [ "$output" == "$help" ]
}

@test "help has no color codes when not writing to a terminal" {
    run gb --help
    [[ "$output" != *$'\033'* ]]

    local cmd
    for cmd in $(ls "$PROJECT_DIR/commands" | grep -v '^_' | sed 's/\.sh$//'); do
        run gb "$cmd" --help
        [ "$status" -eq 0 ]
        [[ "$output" == "Usage: $cmd"* ]]
        [[ "$output" != *$'\033'* ]]
    done
}

@test "help headings are colored in a terminal" {
    command -v python3 >/dev/null || skip "python3 not installed"
    export PTY_LOG="$BATS_TEST_TMPDIR/pty-help"
    run python3 "$HELPERS_DIR/pty_run.py" "\"${GB_BASH:-bash}\" \"$GB\" --help"
    [ "$status" -eq 0 ]
    [[ "$(cat "$PTY_LOG")" == *$'\033[1;38;5;209mCommands:\033[0m'* ]]

    export PTY_LOG="$BATS_TEST_TMPDIR/pty-commit"
    run python3 "$HELPERS_DIR/pty_run.py" "\"${GB_BASH:-bash}\" \"$GB\" commit --help"
    [ "$status" -eq 0 ]
    local log
    log=$(cat "$PTY_LOG")
    [[ "$log" == *$'\033[1;38;5;209mUsage:\033[0m commit'* ]]
    [[ "$log" == *$'\033[1;38;5;209mWhat gets committed:\033[0m'* ]]
    [[ "$log" != *$'\033[1;38;5;209m  '* ]]
}
