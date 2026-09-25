#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
    git remote set-url origin "git@github.com:acme/repo.git"
}

# Replace the gh stub with one that succeeds and records its arguments
gh_success() {
    mkdir -p "$BATS_TEST_TMPDIR/gh-bin"
    cat > "$BATS_TEST_TMPDIR/gh-bin/gh" << 'STUB'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "${GH_LOG:?}"
STUB
    chmod +x "$BATS_TEST_TMPDIR/gh-bin/gh"
    export GH_LOG="$BATS_TEST_TMPDIR/gh-log"
    export PATH="$BATS_TEST_TMPDIR/gh-bin:$PATH"
}

@test "repo opens the web URL of the remote" {
    run gb repo
    [ "$status" -eq 0 ]
    [ "$(cat "$OPEN_LOG")" = "https://github.com/acme/repo" ]
}

@test "repo uses gh when it can open the repository" {
    gh_success
    run gb repo
    [ "$status" -eq 0 ]
    [ "$(cat "$GH_LOG")" = "repo view https://github.com/acme/repo --web" ]
    [ ! -e "$OPEN_LOG" ]
}

@test "repo does not use gh for GitLab" {
    gh_success
    git remote set-url origin "https://user:secret@gitlab.com/group/sub/repo.git"
    run gb repo
    [ "$status" -eq 0 ]
    [ ! -e "$GH_LOG" ]
    [ "$(cat "$OPEN_LOG")" = "https://gitlab.com/group/sub/repo" ]
}

@test "repo --print prints the URL instead of opening it" {
    gh_success
    run gb repo --print
    [ "$status" -eq 0 ]
    [ "$output" = "https://github.com/acme/repo" ]
    [ ! -e "$OPEN_LOG" ]
    [ ! -e "$GH_LOG" ]
}

@test "repo uses the configured remote" {
    git remote add upstream "https://bitbucket.org/team/repo.git"
    GITBASH_REMOTE=upstream run gb repo --print
    [ "$status" -eq 0 ]
    [ "$output" = "https://bitbucket.org/team/repo" ]
}

@test "repo fails without a remote or with an unknown remote URL" {
    git remote remove origin
    run gb repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"No remote 'origin' found."* ]]

    git remote add origin /some/local/path
    run gb repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Don't know how to open"* ]]
}

@test "repo rejects unknown arguments" {
    run gb repo --nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown argument: --nope"* ]]
}

@test "URLs open with rundll32 in Git Bash on Windows, & and all" {
    run bash -c 'source "$1/commands/_utils.sh"; OSTYPE=msys; gb_open_url "https://example.test/a?b=1&c=^2"' _ "$PROJECT_DIR"
    [ "$status" -eq 0 ]
    [ "$(cat "$OPEN_LOG")" = "https://example.test/a?b=1&c=^2" ]
}

@test "URLs open with wslview in WSL" {
    run bash -c 'source "$1/commands/_utils.sh"; OSTYPE=linux-gnu; WSL_DISTRO_NAME=Ubuntu; gb_open_url "https://example.test/"' _ "$PROJECT_DIR"
    [ "$status" -eq 0 ]
    [ "$(cat "$OPEN_LOG")" = "https://example.test/" ]
}

@test "fzf needs 0.54 on Windows" {
    run bash -c 'OSTYPE=msys; source "$1/commands/_utils.sh"; echo "$GB_FZF_MIN_VERSION"' _ "$PROJECT_DIR"
    [ "$output" = "0.54.0" ]
}
