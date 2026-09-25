#!/usr/bin/env bats
# NO_COLOR support (https://no-color.org)

load helpers/setup

setup() {
    setup_repo
}

# Run a snippet with _utils.sh loaded
utils() {
    "${GB_BASH:-bash}" -c 'source "$1/commands/_utils.sh"; eval "$2"' _ "$PROJECT_DIR" "$1"
}

@test "colors are on by default" {
    run utils 'echo "$GB_COLOR"; git config color.ui || echo unset'
    [ "$status" -eq 0 ]
    [ "$output" = $'always\nunset' ]
}

@test "an empty NO_COLOR keeps colors on" {
    NO_COLOR= run utils 'echo "$GB_COLOR"'
    [ "$output" = "always" ]
}

@test "NO_COLOR turns off colors in previews and git output" {
    NO_COLOR=1 run utils 'echo "$GB_COLOR"; git config color.ui; gb_diff_pager; bash -c "echo \$GB_COLOR"'
    [ "$status" -eq 0 ]
    [ "$output" = $'never\nnever\ncat\nnever' ]
}

@test "NO_COLOR keeps git config entries from the environment" {
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=gitbash.test GIT_CONFIG_VALUE_0=kept NO_COLOR=1 \
        run utils 'git config gitbash.test; git config color.ui'
    [ "$output" = $'kept\nnever' ]
}

@test "NO_COLOR is passed to bat" {
    mkdir -p "$BATS_TEST_TMPDIR/bat-bin"
    printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/bat-bin/bat"
    chmod +x "$BATS_TEST_TMPDIR/bat-bin/bat"
    PATH="$BATS_TEST_TMPDIR/bat-bin:$PATH" NO_COLOR=1 run utils 'gb_bat_cmd'
    [[ "$output" == "bat --color=never "* ]]
}

@test "previews never force colors" {
    run grep -rn -- '--color=always' "$PROJECT_DIR/commands" "$PROJECT_DIR/bin"
    [ "$status" -eq 1 ]
}

@test "NO_COLOR removes the colors from the help" {
    command -v python3 >/dev/null || skip "python3 not installed"
    export PTY_LOG="$BATS_TEST_TMPDIR/pty-help"
    NO_COLOR=1 run python3 "$HELPERS_DIR/pty_run.py" "\"${GB_BASH:-bash}\" \"$GB\" --help"
    [ "$status" -eq 0 ]
    [[ "$(cat "$PTY_LOG")" == *"Commands:"* ]]
    [[ "$(cat "$PTY_LOG")" != *$'\033'* ]]
}
