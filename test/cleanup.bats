#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
}

# Category and pre-selection of a branch in the JSON output
json_field() {
    local branch="$1" field="$2"
    gb cleanup --json | tr '{' '\n' | grep "\"name\":\"$branch\"" | sed -E "s/.*\"$field\":(\"[^\"]*\"|[a-z0-9]+).*/\\1/"
}

@test "cleanup works with local branches that have no upstream" {
    git switch --quiet -c local-only
    commit_file l.txt "l" "local work"
    git switch --quiet main
    run gb cleanup --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"name":"local-only"'* ]]
}

@test "a branch tracking origin/main under another name is not treated as merged" {
    git switch --quiet -c wip origin/main
    commit_file w.txt "w" "unpushed work"
    git switch --quiet main
    [ "$(json_field wip category)" = '"recent"' ]
    [ "$(json_field wip preselected)" = "false" ]
    [ "$(json_field wip unpushed_commits)" = "1" ]
}

@test "merged branches whose remote is gone are pre-selected" {
    git switch --quiet -c feature/done
    commit_file d.txt "d" "done"
    git push --quiet -u origin feature/done 2>/dev/null
    git switch --quiet main
    git merge --quiet --no-edit feature/done
    git push --quiet origin main 2>/dev/null
    git push --quiet origin --delete feature/done 2>/dev/null
    [ "$(json_field feature/done category)" = '"merged"' ]
    [ "$(json_field feature/done preselected)" = "true" ]
}

@test "squash-merged branches are detected as merged" {
    git switch --quiet -c feature/squash
    commit_file s1.txt "1" "part 1"
    commit_file s2.txt "2" "part 2"
    git push --quiet -u origin feature/squash 2>/dev/null
    git switch --quiet main
    git merge --quiet --squash feature/squash
    git commit --quiet -m "squashed"
    git push --quiet origin main 2>/dev/null
    git push --quiet origin --delete feature/squash 2>/dev/null
    [ "$(json_field feature/squash category)" = '"merged"' ]
}

@test "a gone branch with unmerged work is labeled GONE and not pre-selected" {
    git switch --quiet -c feature/gone
    commit_file g.txt "g" "never merged"
    git push --quiet -u origin feature/gone 2>/dev/null
    git push --quiet origin --delete feature/gone 2>/dev/null
    git switch --quiet main
    [ "$(json_field feature/gone category)" = '"gone"' ]
    [ "$(json_field feature/gone preselected)" = "false" ]
}

@test "stale branches are pre-selected only when everything is pushed" {
    git switch --quiet -c old-pushed
    commit_file o.txt "o" "old" "2020-01-01T00:00:00"
    git push --quiet -u origin old-pushed 2>/dev/null
    git switch --quiet -c old-local main
    commit_file p.txt "p" "old local" "2020-01-01T00:00:00"
    git switch --quiet main
    [ "$(json_field old-pushed category)" = '"stale"' ]
    [ "$(json_field old-pushed preselected)" = "true" ]
    [ "$(json_field old-local category)" = '"stale"' ]
    [ "$(json_field old-local preselected)" = "false" ]
}

@test "protected branches are never listed" {
    git branch develop
    git branch release/1.0
    run gb cleanup --json
    [[ "$output" != *'"name":"develop"'* ]]
    [[ "$output" != *'"name":"release/1.0"'* ]]
    [[ "$output" != *'"name":"main"'* ]]
}

@test "--dry-run lists pre-selected branches without fzf and deletes nothing" {
    git switch --quiet -c old-pushed
    commit_file o.txt "o" "old" "2020-01-01T00:00:00"
    git push --quiet -u origin old-pushed 2>/dev/null
    git switch --quiet main
    run gb cleanup --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would delete 1 branch(es)"* ]]
    git show-ref --verify --quiet refs/heads/old-pushed
    [ ! -e "$FZF_STUB_LOG" ]
}

@test "--yes deletes only pre-selected branches" {
    git switch --quiet -c old-pushed
    commit_file o.txt "o" "old" "2020-01-01T00:00:00"
    git push --quiet -u origin old-pushed 2>/dev/null
    git switch --quiet -c recent main
    commit_file r.txt "r" "recent"
    git switch --quiet main
    run gb cleanup --yes
    [ "$status" -eq 0 ]
    ! git show-ref --verify --quiet refs/heads/old-pushed
    git show-ref --verify --quiet refs/heads/recent
}

@test "interactive delete of unmerged work needs a second confirmation" {
    git switch --quiet -c wip origin/main
    commit_file w.txt "w" "unpushed work"
    git switch --quiet main
    export FZF_STUB_STEP="wip"
    # "y" to delete, then EOF on the force-delete question (default no)
    run gb_input 'y\n' cleanup
    [ "$status" -eq 0 ]
    [[ "$output" == *"not merged"* ]]
    git show-ref --verify --quiet refs/heads/wip

    # "y" twice force-deletes
    run gb_input 'y\ny\n' cleanup
    ! git show-ref --verify --quiet refs/heads/wip
}

@test "the picker gets pre-selection bindings and a clean fzf environment" {
    git switch --quiet -c old-pushed
    commit_file o.txt "o" "old" "2020-01-01T00:00:00"
    git push --quiet -u origin old-pushed 2>/dev/null
    git switch --quiet main
    export FZF_DEFAULT_OPTS="--print-query"
    run gb cleanup
    fzf_args | grep -qx "load:first+toggle+down+first"
    fzf_env | grep -qx "FZF_DEFAULT_OPTS="
    fzf_env | grep -q "^SHELL=.*bash$"
}
