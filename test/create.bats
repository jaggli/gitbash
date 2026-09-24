#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
}

@test "create while on main starts from the latest origin/main" {
    remote_commit main main.txt "new" "main moved"
    run gb create PROJ-1 fresh start
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/PROJ-1-fresh-start" ]
    git merge-base --is-ancestor origin/main HEAD
    [ -f main.txt ]
    # Tracks its own remote branch, not origin/main
    [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feature/PROJ-1-fresh-start" ]
}

@test "issue keys: plain, with digits, lowercase and Jira URLs" {
    run gb create --no-push AB2-45 one
    [ "$(git branch --show-current)" = "feature/AB2-45-one" ]
    git switch --quiet main
    run gb create --no-push proj-7 two
    [ "$(git branch --show-current)" = "feature/PROJ-7-two" ]
    git switch --quiet main
    run gb create --no-push "https://jira.example.com/browse/XY-9" three
    [ "$(git branch --show-current)" = "feature/XY-9-three" ]
}

@test "text without an issue key uses the fallback and keeps the words" {
    run gb create --no-push fix login bug
    [ "$(git branch --show-current)" = "feature/NOISSUE-fix-login-bug" ]
}

@test "accents and umlauts are transliterated" {
    run gb create --no-push PROJ-2 "Über Änderung für Café"
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/PROJ-2-ueber-aenderung-fuer-cafe" ]
}

@test "--hotfix and --no-push" {
    run gb create --hotfix --no-push PROJ-3 urgent
    [ "$(git branch --show-current)" = "hotfix/PROJ-3-urgent" ]
    ! remote_has_branch hotfix/PROJ-3-urgent
}

@test "GITBASH_CREATE_AUTO_PUSH=no disables the push" {
    echo 'GITBASH_CREATE_AUTO_PUSH="no"' > "$HOME/.gitbashrc"
    run gb create PROJ-4 local only
    [ "$status" -eq 0 ]
    ! remote_has_branch feature/PROJ-4-local-only
}

@test "a branch that already exists on the remote is refused" {
    remote_commit feature/PROJ-5-taken x.txt "x" "someone else"
    run gb create PROJ-5 taken
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists on 'origin'"* ]]
}

@test "an invalid prefix is reported instead of failing later" {
    echo 'GITBASH_CREATE_BRANCH_PREFIX="my team"' > "$HOME/.gitbashrc"
    run gb create --no-push PROJ-6 x
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a valid branch name"* ]]
}

@test "interactive create asks for issue and title" {
    run gb_input 'PROJ-8\nasked title\n' create --no-push
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/PROJ-8-asked-title" ]
}
