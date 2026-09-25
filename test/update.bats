#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
    git switch --quiet -c feature/work
    commit_file work.txt "work" "my work"
    remote_commit main main.txt "new on main" "main moved"
}

@test "update merges the latest remote base branch" {
    run gb update
    [ "$status" -eq 0 ]
    git merge-base --is-ancestor origin/main HEAD
    [ -f main.txt ]
}

@test "update fast-forwards the local base branch too" {
    run gb update
    [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]
}

@test "update with local changes can stash them and restores them afterwards" {
    echo "wip" >> work.txt
    run gb_input 's\n' update
    [ "$status" -eq 0 ]
    [ -f main.txt ]
    grep -q wip work.txt
    [ -z "$(git stash list)" ]
}

@test "update with local changes can commit them (commit is available in binary mode)" {
    echo "wip" >> work.txt
    run gb_input 'c\nwip commit\n' update
    [ "$status" -eq 0 ]
    git log --format=%s | grep -qx "wip commit"
    [ -z "$(git status --porcelain)" ]
    [ -f main.txt ]
}

@test "answering 'no' aborts the update" {
    echo "wip" >> work.txt
    run gb_input 'no\n' update
    [ "$status" -eq 1 ]
    [ ! -f main.txt ]
    grep -q wip work.txt
}

@test "update reports conflicts and returns an error" {
    commit_file main.txt "my conflicting content" "conflict"
    run gb update
    [ "$status" -eq 1 ]
    [[ "$output" == *"Merge conflicts in"* ]]
    [[ "$output" == *"main.txt"* ]]
    # The default merge tool (stubbed) is opened on the repository
    [ "$(cat "$MERGE_TOOL_LOG")" = "." ]
}

@test "update on the base branch fast-forwards it" {
    git switch --quiet main
    run gb update
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
}

@test "update -p pushes the merged branch" {
    run gb update -p
    [ "$status" -eq 0 ]
    [ "$(git ls-remote "$REMOTE" refs/heads/feature/work | cut -f1)" = "$(git rev-parse HEAD)" ]
}
