#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
}

@test "a malicious repository .gitbashrc is never executed" {
    local marker="$BATS_TEST_TMPDIR/pwned"
    cat > .gitbashrc <<EOF
touch "$marker-plain"
GITBASH_THEME="\$(touch $marker-subst)"
GITBASH_REMOTE=\`touch $marker-backtick\`
GITBASH_CREATE_BRANCH_PREFIX="team"; touch "$marker-chained"
EOF
    run gb stash --version
    [ "$status" -eq 0 ]
    [ ! -e "$marker-plain" ]
    [ ! -e "$marker-subst" ]
    [ ! -e "$marker-backtick" ]
    [ ! -e "$marker-chained" ]
    [[ "$output" == *"ignored"* ]]
}

@test "the global and user config files are not executed either" {
    local marker="$BATS_TEST_TMPDIR/pwned"
    echo "touch $marker-global" > "$HOME/.gitbashrc"
    echo "touch $marker-user" > .gitbashrc-user
    run gb stash --version
    [ ! -e "$marker-global" ]
    [ ! -e "$marker-user" ]
}

@test "plain settings are read from global, local and user config (user wins)" {
    echo 'GITBASH_CREATE_BRANCH_PREFIX="global"' > "$HOME/.gitbashrc"
    echo "GITBASH_CREATE_BRANCH_PREFIX='local'" > .gitbashrc
    run gb create --no-push PROJ-1 some work
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/local/PROJ-1-some-work" ]

    git switch --quiet main
    echo 'GITBASH_CREATE_BRANCH_PREFIX=user  # comment' > .gitbashrc-user
    run gb create --no-push PROJ-2 more
    [ "$(git branch --show-current)" = "feature/user/PROJ-2-more" ]
}

@test "the committed .gitbashrc cannot choose the merge tool" {
    echo 'GITBASH_MERGE_COMMAND="evil-tool"' > .gitbashrc
    run gb stash --version
    [[ "$output" == *"ignored GITBASH_MERGE_COMMAND"* ]]
}

@test "invalid values fall back to defaults with a warning" {
    echo 'GITBASH_STALE_MONTHS="abc"' > "$HOME/.gitbashrc"
    run gb stale --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"Invalid GITBASH_STALE_MONTHS"* ]]
}

@test "legacy GITBASH_FEATURE_BRANCH_PREFIX still works" {
    echo 'GITBASH_FEATURE_BRANCH_PREFIX="feature/oldteam/"' > "$HOME/.gitbashrc"
    run gb create --no-push PROJ-3 legacy
    [ "$(git branch --show-current)" = "feature/oldteam/PROJ-3-legacy" ]
}

@test "--config-user writes plain values and excludes the file without touching .gitignore" {
    # Keep all settings (Enter) except the prefix
    run gb_input 'mine\n\n\n\n\n\n\n\n\n\n\n' --config-user
    [ "$status" -eq 0 ]
    grep -qx 'GITBASH_CREATE_BRANCH_PREFIX="mine"' .gitbashrc-user
    [ ! -e .gitignore ]
    grep -qx '.gitbashrc-user' .git/info/exclude
}

@test "the wizard rejects values that would be code in older versions" {
    run gb_input '$(touch x)\nok\n\n\n\n\n\n\n\n\n\n\n' --config-local
    [ "$status" -eq 0 ]
    [[ "$output" == *"Values cannot contain"* ]]
    grep -qx 'GITBASH_CREATE_BRANCH_PREFIX="ok"' .gitbashrc
    ! grep -q 'MERGE_COMMAND' .gitbashrc
}

@test "the wizard stops without saving on EOF" {
    run gb --config-local
    [ "$status" -eq 1 ]
    [ ! -e .gitbashrc ]
}
