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
    [[ "$output" == *$'merged: feature/alpha\tlocal\tfeature/alpha'* ]] || false
    [[ "$output" == *$'remote: origin/feature/remote-only\tremote\torigin/feature/remote-only'* ]] || false
    [[ "$output" != *"remote: origin/main"* ]]
}

@test "the Del key is bound to delete + reload" {
    run gb switch
    fzf_args | grep -q '^--bind=del:execute(.* switch --delete-branch {} < /dev/tty > /dev/tty 2>&1)+reload(.* switch --list-branches)$'
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
    [[ "$output" == *"not merged or pushed"* ]] || false
    git show-ref --verify --quiet refs/heads/feature/beta

    run gb_input 'y\ny\n' switch --delete-branch $'local: feature/beta\tlocal\tfeature/beta'
    ! git show-ref --verify --quiet refs/heads/feature/beta
}

@test "protected and current branches cannot be deleted" {
    git branch develop
    run gb_input 'y\n' switch --delete-branch $'local: develop\tlocal\tdevelop'
    [[ "$output" == *"protected"* ]] || false
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
    [[ "$output" == *"behind its upstream"* ]] || false
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/feature/remote-only)" ]
}

@test "an exact branch name switches directly even if other branches contain it" {
    git branch feature/alpha-2
    git branch alpha
    run gb switch alpha
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "alpha" ]
    [ ! -e "$FZF_STUB_LOG" ]
}

@test "an exact remote branch name switches directly" {
    remote_commit feature/remote-only-2 r2.txt "r2" "more remote work"
    git fetch --quiet origin
    run gb switch feature/remote-only
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/remote-only" ]
    [ ! -e "$FZF_STUB_LOG" ]
}

@test "tags named like branches don't change the branch list or what is checked out" {
    git switch --quiet -c feature/x
    commit_file x.txt "x" "x"
    git push --quiet -u origin feature/x 2>/dev/null
    git switch --quiet main
    git branch --quiet -D feature/x
    git tag origin/feature/x main
    git tag main HEAD
    run gb switch --list-branches
    [[ "$output" == *$'local: main\tlocal\tmain'* ]] || false
    [[ "$output" == *$'remote: origin/feature/x\tremote\torigin/feature/x'* ]] || false
    run gb switch feature/x
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse refs/remotes/origin/feature/x)" ]
    [ "$(git config branch.feature/x.merge)" = "refs/heads/feature/x" ]
}


@test "a branch pushed since the last fetch is fetched and switched to directly" {
    remote_commit feature/new-on-remote n.txt "n" "new remote work"
    [ -z "$(git for-each-ref refs/remotes/origin/feature/new-on-remote)" ]
    run gb switch feature/new-on-remote
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/new-on-remote" ]
    [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feature/new-on-remote" ]
    [ ! -e "$FZF_STUB_LOG" ]
}

@test "a branch pushed since the last fetch is found with the remote prefix too" {
    remote_commit feature/new-on-remote n.txt "n" "new remote work"
    run gb switch origin/feature/new-on-remote
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/new-on-remote" ]
}

@test "a new remote branch wins over a local branch that only contains the name" {
    git branch feature/new-on-remote-old
    remote_commit feature/new-on-remote n.txt "n" "new remote work"
    run gb switch feature/new-on-remote
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/new-on-remote" ]
}

@test "a name that is not on the remote still opens the picker" {
    run gb switch feature/does-not-exist
    [ "$status" -eq 0 ]
    [[ "$output" == *"No branch selected."* ]] || false
    [ -z "$(git for-each-ref refs/remotes/origin/feature/does-not-exist)" ]
}
