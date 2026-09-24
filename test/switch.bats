#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
    git branch feature/alpha
    git branch feature/beta
    remote_commit feature/remote-only r.txt "r" "remote work"
    git fetch --quiet origin
}

@test "a filter with exactly one matching branch switches directly" {
    run gb switch alpha
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/alpha" ]
    [ ! -e "$FZF_STUB_LOG" ]
}

@test "the single-match check looks at branch names only" {
    # "local" appears in every line label but in no branch name
    run gb switch local
    [ "$(git branch --show-current)" = "main" ]
}

@test "selecting a remote branch creates a tracking branch" {
    export FZF_STUB_STEP="remote-only"
    run gb switch
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/remote-only" ]
    [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feature/remote-only" ]
}

@test "the list hides remote branches that exist locally and marks merged ones" {
    run gb switch --list-branches
    [[ "$output" == *$'merged: feature/alpha\tlocal\tfeature/alpha'* ]]
    [[ "$output" == *$'remote: origin/feature/remote-only\tremote\torigin/feature/remote-only'* ]]
    [[ "$output" != *"remote: origin/main"* ]]
}

@test "the Del key is bound to delete + reload" {
    run gb switch
    fzf_args | grep -q '^--bind=del:execute(.* switch --delete-branch {})+reload(.* switch --list-branches)$'
}

@test "deleting asks first and defaults to no" {
    run gb switch --delete-branch $'merged: feature/alpha\tlocal\tfeature/alpha'
    git show-ref --verify --quiet refs/heads/feature/alpha

    run gb_input 'y\n' switch --delete-branch $'merged: feature/alpha\tlocal\tfeature/alpha'
    ! git show-ref --verify --quiet refs/heads/feature/alpha
}

@test "unmerged branches need a second confirmation to force-delete" {
    git switch --quiet feature/beta
    commit_file b.txt "b" "unmerged"
    git switch --quiet main
    run gb_input 'y\n' switch --delete-branch $'local: feature/beta\tlocal\tfeature/beta'
    [[ "$output" == *"not merged or pushed"* ]]
    git show-ref --verify --quiet refs/heads/feature/beta

    run gb_input 'y\ny\n' switch --delete-branch $'local: feature/beta\tlocal\tfeature/beta'
    ! git show-ref --verify --quiet refs/heads/feature/beta
}

@test "protected and current branches cannot be deleted" {
    git branch develop
    run gb_input 'y\n' switch --delete-branch $'local: develop\tlocal\tdevelop'
    [[ "$output" == *"protected"* ]]
    git show-ref --verify --quiet refs/heads/develop

    run gb_input 'y\n' switch --delete-branch $'local: main\tlocal\tmain'
    git show-ref --verify --quiet refs/heads/main
}

@test "after switching, offers to fast-forward a branch that is behind" {
    git switch --quiet -c feature/behind --track origin/feature/remote-only
    git reset --quiet --hard main
    git switch --quiet main
    run gb switch behind
    [ "$status" -eq 0 ]
    [[ "$output" == *"behind its upstream"* ]]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/feature/remote-only)" ]
}
