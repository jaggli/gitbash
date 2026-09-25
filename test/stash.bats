#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
}

@test "stash creates a named stash including untracked files" {
    echo "new" > new.txt
    run gb stash my work
    [ "$status" -eq 0 ]
    [[ "$(git stash list)" == *"my work"* ]]
    [ ! -e new.txt ]
}

@test "stash with no changes fails" {
    run gb stash name
    [ "$status" -eq 1 ]
    [[ "$output" == *"No changes to stash"* ]]
}

@test "unstash and cleanstash say so when there are no stashes" {
    run gb unstash
    [ "$status" -eq 0 ]
    [[ "$output" == *"No stashes."* ]]
    run gb cleanstash
    [ "$status" -eq 0 ]
    [[ "$output" == *"No stashes."* ]]
    [ ! -e "$FZF_STUB_LOG" ]
}

@test "unstash applies the stash and drops it by default" {
    echo "change" >> README.md
    git stash push --quiet -m "first"
    export FZF_STUB_STEP="first"
    run gb unstash
    [ "$status" -eq 0 ]
    grep -q change README.md
    [ -z "$(git stash list)" ]
}

@test "unstash lists the restored files in green" {
    echo "change" >> README.md
    echo "new" > new.txt
    git stash push --quiet --include-untracked -m "first"
    export FZF_STUB_STEP="first"
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=color.status GIT_CONFIG_VALUE_0=always \
        run gb unstash
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033[32mmodified:   README.md'* ]]
    [[ "$output" == *$'\033[32mnew.txt'* ]]
    [[ "$output" != *$'\033[31m'* ]]
}

@test "cleanstash deletes the selected stashes (highest index first)" {
    local i
    for i in 1 2 3; do
        echo "$i" >> README.md
        git stash push --quiet -m "s$i"
    done
    fzf_plan "On main: s3;;On main: s1"
    run gb_input 'y\n' cleanstash
    [ "$status" -eq 0 ]
    [ "$(git stash list | sed 's/.*: //')" = "s2" ]
}

@test "menus return 0 when cancelled" {
    run gb stashes
    [ "$status" -eq 0 ]
    run gb branch
    [ "$status" -eq 0 ]
}
