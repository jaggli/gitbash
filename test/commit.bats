#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
}

@test "commit -p on a branch that is not on the remote pushes it with tracking" {
    git switch --quiet -c feature/new
    echo "change" > file.txt
    run gb commit -p add file
    [ "$status" -eq 0 ]
    remote_has_branch feature/new
    [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feature/new" ]
}

@test "nothing to commit fails before asking for a message" {
    run gb commit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Nothing to commit"* ]]
    [[ "$output" != *"Commit message"* ]]
}

@test "an empty message cancels the commit" {
    echo "change" >> README.md
    run gb_input '\n' commit
    [ "$status" -eq 1 ]
    [[ "$output" == *"Empty commit message"* ]]
    [ "$(git rev-list --count HEAD)" -eq 1 ]
}

@test "with staged and unstaged changes, Enter commits only the staged ones" {
    echo "staged" > staged.txt
    git add staged.txt
    echo "unstaged" >> README.md
    run gb_input '\n' commit my message
    [ "$status" -eq 0 ]
    [ "$(git show --name-only --format= HEAD)" = "staged.txt" ]
    [ -n "$(git diff --name-only)" ]
}

@test "new files are listed before they are added" {
    echo "secret" > .env
    run gb_input 'n\n' commit add stuff
    [ "$status" -eq 1 ]
    [[ "$output" == *"+ .env"* ]]
    [ "$(git rev-list --count HEAD)" -eq 1 ]
}

@test "--yes adds new files without asking" {
    echo "new" > new.txt
    run gb commit --yes add new file
    [ "$status" -eq 0 ]
    [ "$(git show --name-only --format= HEAD)" = "new.txt" ]
}

@test "--amend without a message keeps the old message" {
    echo "change" >> README.md
    git commit --quiet -am "original message"
    echo "more" >> README.md
    run gb commit --amend
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "original message" ]
    [ "$(git rev-list --count HEAD)" -eq 2 ]
}

@test "-- lets the message start with a dash" {
    echo "change" >> README.md
    run gb commit -- -1 is not an index
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "-1 is not an index" ]
}

@test "--amend -p asks before force-pushing and never rebases silently" {
    git switch --quiet -c feature/amend
    commit_file a.txt "a" "first version"
    git push --quiet -u origin feature/amend 2>/dev/null
    local pushed
    pushed=$(git rev-parse HEAD)

    # Default answer (EOF) is no: nothing is pushed or rewritten
    run gb commit --amend -p "second version"
    [ "$status" -eq 1 ]
    [ "$(git ls-remote "$REMOTE" refs/heads/feature/amend | cut -f1)" = "$pushed" ]
    [ "$(git log -1 --format=%s)" = "second version" ]
    [ "$(git rev-list --count HEAD)" -eq 2 ]

    # Saying yes force-pushes with lease
    run gb_input 'y\n' commit --amend -p "third version"
    [ "$status" -eq 0 ]
    [ "$(git ls-remote "$REMOTE" refs/heads/feature/amend | cut -f1)" = "$(git rev-parse HEAD)" ]
}

@test "commit -p asks what to do when the remote diverged" {
    git switch --quiet -c feature/div
    git push --quiet -u origin feature/div 2>/dev/null
    remote_commit feature/div other.txt "theirs" "teammate change"
    echo "mine" > mine.txt

    # Default is abort: committed locally, nothing pushed
    run gb commit --yes -p mine
    [ "$status" -eq 1 ]
    [[ "$output" == *"diverged"* ]]
    [ "$(git log -1 --format=%s)" = "mine" ]
    [ "$(git ls-remote "$REMOTE" refs/heads/feature/div | cut -f1)" = "$(git rev-parse origin/feature/div)" ]

    # Rebase when asked: linear history on top of the teammate's commit
    echo "more" > more.txt
    run gb_input 'r\n' commit --yes -p more
    [ "$status" -eq 0 ]
    [ "$(git ls-remote "$REMOTE" refs/heads/feature/div | cut -f1)" = "$(git rev-parse HEAD)" ]
    [ "$(git rev-list --merges --count HEAD)" -eq 0 ]
    [ "$(git log -3 --format=%s | tr '\n' ',')" = "more,mine,teammate change," ]
}

@test "commit -p merges when asked after divergence" {
    git switch --quiet -c feature/merge
    git push --quiet -u origin feature/merge 2>/dev/null
    remote_commit feature/merge other.txt "theirs" "teammate change"
    echo "mine" > mine.txt
    run gb_input 'm\n' commit --yes -p mine
    [ "$status" -eq 0 ]
    [ "$(git ls-remote "$REMOTE" refs/heads/feature/merge | cut -f1)" = "$(git rev-parse HEAD)" ]
    git merge-base --is-ancestor origin/feature/merge HEAD
}

@test "commit -t prefixes the conventional commit type" {
    echo "change" >> README.md
    export FZF_STUB_STEP="fix "
    run gb commit -t broken tests
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "fix: broken tests" ]
}
