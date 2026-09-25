#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
    # The remote looks like GitHub but actually points to the local bare repo
    git config --global url."$REMOTE".insteadOf "https://github.com/acme/repo.git"
    git remote set-url origin "https://github.com/acme/repo.git"
}

web_base() {
    bash -c 'source "$1"; gb_web_url "$2"' _ "$PROJECT_DIR/commands/_utils.sh" "$1"
}

create_url() {
    bash -c 'source "$1"; _pr_create_url "$2" "$3"' _ "$PROJECT_DIR/commands/pr.sh" "$1" "$2"
}

@test "remote URLs are converted to web URLs without credentials" {
    [ "$(web_base git@github.com:acme/repo.git)" = "https://github.com/acme/repo" ]
    [ "$(web_base https://github.com/acme/repo.git)" = "https://github.com/acme/repo" ]
    [ "$(web_base https://user:ghp_secret@github.com/acme/repo.git)" = "https://github.com/acme/repo" ]
    [ "$(web_base ssh://git@github.example.com:2222/acme/repo.git)" = "https://github.example.com/acme/repo" ]
    [ "$(web_base git@gitlab.com:group/sub/repo.git)" = "https://gitlab.com/group/sub/repo" ]
    [ "$(web_base git@ssh.dev.azure.com:v3/org/proj/repo)" = "https://dev.azure.com/org/proj/_git/repo" ]
    run web_base /some/local/path
    [ "$status" -eq 1 ]
}

@test "pull request URLs match the hosting service and encode the branch" {
    [ "$(create_url https://github.com/acme/repo 'feature/a#b')" = "https://github.com/acme/repo/compare/feature/a%23b?expand=1" ]
    [ "$(create_url https://github.com/acme/repo 'feature/über')" = "https://github.com/acme/repo/compare/feature/%C3%BCber?expand=1" ]
    [ "$(create_url https://gitlab.com/g/r feature/x)" = "https://gitlab.com/g/r/-/merge_requests/new?merge_request%5Bsource_branch%5D=feature/x" ]
    [ "$(create_url https://bitbucket.org/t/r feature/x)" = "https://bitbucket.org/t/r/pull-requests/new?source=feature/x" ]
}

@test "pr -p on an unpushed branch pushes it and opens the compare page" {
    git switch --quiet -c feature/pr
    commit_file f.txt "x" "work"
    run gb pr -p
    [ "$status" -eq 0 ]
    remote_has_branch feature/pr
    [ "$(cat "$OPEN_LOG")" = "https://github.com/acme/repo/compare/feature/pr?expand=1" ]
}

@test "pr offers to push a branch that is not on the remote (default yes)" {
    git switch --quiet -c feature/offer
    commit_file f.txt "x" "work"
    run gb pr
    [ "$status" -eq 0 ]
    remote_has_branch feature/offer
}

@test "pr --print prints the URL instead of opening it" {
    git switch --quiet -c feature/print
    git push --quiet -u origin feature/print 2>/dev/null
    run gb pr --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"https://github.com/acme/repo/compare/feature/print?expand=1"* ]]
    [ ! -e "$OPEN_LOG" ]
}
