#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
    commit_file a.txt "1" "c1"
    commit_file a.txt "2" "c2"
    commit_file a.txt "3" "c3"
}

@test "selected commits are reverted newest first, whatever the pick order" {
    # Picked oldest first: reverting in that order would conflict
    fzf_plan "  c1  ;;  c3  ;;  c2  "
    run gb_input 'y\n' commits
    [ "$status" -eq 0 ]
    [ "$(git log -3 --format=%s | tr '\n' ',')" = 'Revert "c1",Revert "c2",Revert "c3",' ]
    [ "$(cat a.txt 2>/dev/null)" = "" ]
}

@test "reverting asks first (default no)" {
    fzf_plan "  c3  "
    run gb commits
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "c3" ]
}

@test "merge commits are reverted against their first parent" {
    git switch --quiet -c side
    commit_file b.txt "b" "side work"
    git switch --quiet main
    git merge --quiet --no-ff --no-edit side -m "merge side"
    fzf_plan "merge side"
    run gb_input 'y\n' commits
    [ "$status" -eq 0 ]
    [ ! -e b.txt ]
}

@test "COUNT must be a positive number" {
    run gb commits abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"COUNT must be a positive number"* ]]
}
