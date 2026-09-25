#!/usr/bin/env bats
# bin/gitbash.js: the npm entry point (runs bin/gitbash with bash, Git's bash on Windows)

load helpers/setup

setup() {
    setup_repo
    command -v node >/dev/null || skip "node not installed"
    LAUNCHER="$PROJECT_DIR/bin/gitbash.js"
}

@test "npm runs the node launcher" {
    grep -q '"gitbash": "bin/gitbash.js"' "$PROJECT_DIR/package.json"
}

@test "the launcher runs gitbash" {
    run node "$LAUNCHER" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^gitbash\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "the launcher passes arguments unchanged and returns the exit code" {
    run node "$LAUNCHER" --init '--prefix=a b'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid prefix 'a b'"* ]]
}

@test "the launcher passes input through" {
    echo "change" >> README.md
    run bash -c 'printf "via launcher\n" | node "$1" commit' _ "$LAUNCHER"
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "via launcher" ]
}

@test "gitbash works when started with a Windows path (C:\\...\\bin\\gitbash)" {
    command -v cygpath >/dev/null || skip "not on Windows"
    run "${GB_BASH:-bash}" "$(cygpath -w "$GB")" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^gitbash\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}
