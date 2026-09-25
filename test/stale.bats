#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
    # An old feature branch and old protected branches on the remote
    local b
    for b in feature/old develop release/1.0; do
        git switch --quiet -c "$b" main
        commit_file "$(echo "$b" | tr '/' '-').txt" "x" "old $b" "2020-01-01T00:00:00"
        git push --quiet -u origin "$b" 2>/dev/null
    done
    git switch --quiet -c feature/new main
    commit_file new.txt "n" "new work"
    git push --quiet -u origin feature/new 2>/dev/null
    git switch --quiet main
}

@test "stale --json lists old branches but never protected ones" {
    run gb stale --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name":"feature/old"'* ]]
    [[ "$output" != *'"name":"feature/new"'* ]]
    [[ "$output" != *'"name":"develop"'* ]]
    [[ "$output" != *'"name":"release/1.0"'* ]]
    [[ "$output" != *'"name":"main"'* ]]
}

@test "stale --json --all includes recent branches but still no protected ones" {
    run gb stale --json --all
    [[ "$output" == *'"name":"feature/new"'* ]]
    [[ "$output" != *'"name":"main"'* ]]
    [[ "$output" != *'"name":"develop"'* ]]
}

@test "shows the author, not the committer (GitHub 'Update branch' merges)" {
    git switch --quiet -c feature/web-merged main
    printf 'w\n' > w.txt
    git add w.txt
    GIT_AUTHOR_NAME="Jane Doe" GIT_AUTHOR_EMAIL="jane@example.com" \
        GIT_COMMITTER_NAME="GitHub" GIT_COMMITTER_EMAIL="noreply@github.com" \
        GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
        git commit --quiet -m "Merge branch 'main' into feature/web-merged"
    git push --quiet -u origin feature/web-merged 2>/dev/null
    git switch --quiet main
    run gb stale --json
    [[ "$output" == *'"author_email":"jane@example.com","author_name":"Jane Doe","name":"feature/web-merged"'* ]]
    [[ "$output" != *'GitHub'* ]]
}

@test "the picker never offers protected branches, even in 'all' mode" {
    run gb stale --all
    ! fzf_input | cut -f2 | grep -qx main
    ! fzf_input | cut -f2 | grep -qx develop
    fzf_input | cut -f2 | grep -qx feature/new
    fzf_args | grep -q "^--bind=ctrl-t:reload"
}

@test "deleting asks first (default no) and then deletes from the remote" {
    export FZF_STUB_STEP="feature/old"
    run gb stale
    [ "$status" -eq 0 ]
    remote_has_branch feature/old

    run gb_input 'y\n' stale
    [ "$status" -eq 0 ]
    ! remote_has_branch feature/old
}

@test "temp files are cleaned up after the picker" {
    local before after
    before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -newer "$REMOTE" 2>/dev/null | wc -l)
    run gb stale
    [ "$status" -eq 0 ]
    local dir
    dir=$(fzf_args | sed -n 's/^--bind=ctrl-t:reload(bash \(.*\)\/toggle .*/\1/p')
    [ -n "$dir" ]
    [ ! -e "$dir" ]
}
