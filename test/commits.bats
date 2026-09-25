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

@test "on a feature branch only its own commits are listed" {
    git push --quiet origin main 2>/dev/null
    git switch --quiet -c feature/x
    commit_file b.txt "b" "feature work"
    run gb commits
    [ "$status" -eq 0 ]
    [[ "$(fzf_input)" == *"feature work"* ]]
    [[ "$(fzf_input)" != *"c3"* ]]
    [[ "$(fzf_args)" == *"not in 'origin/main'"* ]]
}

@test "commits in the local base branch are not listed either" {
    git switch --quiet -c feature/x
    commit_file b.txt "b" "feature work"
    # c1..c3 are only in the local main, not pushed
    run gb commits
    [[ "$(fzf_input)" == *"feature work"* ]]
    [[ "$(fzf_input)" != *"c3"* ]]
}

@test "a feature branch without own commits says so" {
    git switch --quiet -c feature/empty
    run gb commits
    [ "$status" -eq 0 ]
    [[ "$output" == *"No commits on 'feature/empty'"*"--all"* ]]
    [ ! -e "$FZF_STUB_LOG" ]
}

@test "--all lists all recent commits" {
    git switch --quiet -c feature/x
    commit_file b.txt "b" "feature work"
    run gb commits --all 5
    [ "$status" -eq 0 ]
    [[ "$(fzf_input)" == *"feature work"* ]]
    [[ "$(fzf_input)" == *"c3"* ]]
}

@test "on the base branch merged branches show as their merge commit" {
    git switch --quiet -c side
    commit_file b.txt "b" "side work"
    git switch --quiet main
    git merge --quiet --no-ff --no-edit side -m "merge side"
    run gb commits
    [[ "$(fzf_input)" == *"merge side"* ]]
    [[ "$(fzf_input)" != *"side work"* ]]
}

@test "offers to pull new upstream commits first" {
    git push --quiet origin main 2>/dev/null
    git reset --quiet --hard HEAD~1
    run gb_input 'y\n' commits
    [ "$status" -eq 0 ]
    [[ "$output" == *"behind its upstream"* ]]
    [ "$(git log -1 --format=%s)" = "c3" ]
    [[ "$(fzf_input)" == *"c3"* ]]
}

@test "declining the pull still lists the local commits" {
    git push --quiet origin main 2>/dev/null
    git reset --quiet --hard HEAD~1
    run gb_input 'n\n' commits
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "c2" ]
    [[ "$(fzf_input)" == *"c2"* ]]
}

@test "unknown options are rejected" {
    run gb commits --nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
