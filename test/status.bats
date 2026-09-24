#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
}

status_list() {
    bash -c 'source "$1"; cd "$2" && _status_list' _ "$PROJECT_DIR/commands/status.sh" "$REPO"
}

@test "file names with spaces and renames are listed exactly" {
    echo "x" > "my file.txt"
    git mv README.md "READ ME.md"
    run status_list
    [[ "$output" == *$'??\tmy file.txt\t'* ]]
    [[ "$output" == *$'R \tREAD ME.md\tREADME.md'* ]]
    [[ "$output" == *"[STAGED]"*"README.md -> READ ME.md"* ]]
}

@test "partially staged files are labeled PARTIAL" {
    echo "one" >> README.md
    git add README.md
    echo "two" >> README.md
    run status_list
    [[ "$output" == *"[PARTIAL]"* ]]
}

@test "Enter stages a file with spaces in its name" {
    echo "x" > "my file.txt"
    fzf_plan "::my file.txt" esc
    run gb status
    [ "$status" -eq 0 ]
    [ "$(git diff --cached --name-only)" = "my file.txt" ]
}

@test "Enter on a partially staged file stages the rest" {
    echo "one" >> README.md
    git add README.md
    echo "two" >> README.md
    fzf_plan "::README.md" esc
    run gb status
    [ -z "$(git diff --name-only)" ]
    [ "$(git diff --cached --name-only)" = "README.md" ]
}

@test "Enter on a fully staged file unstages it" {
    echo "one" >> README.md
    git add README.md
    fzf_plan "::README.md" esc
    run gb status
    [ -z "$(git diff --cached --name-only)" ]
}

@test "staging does not commit or push on its own" {
    echo "one" >> README.md
    fzf_plan "::README.md" esc
    run gb status
    [ "$(git rev-list --count HEAD)" -eq 1 ]
}

@test "Ctrl-O commits the staged files" {
    echo "one" >> README.md
    git add README.md
    fzf_plan "ctrl-o::README.md"
    run gb_input 'from status\n' status
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "from status" ]
    [ "$(git ls-remote "$REMOTE" refs/heads/main | cut -f1)" != "$(git rev-parse HEAD)" ]
}

@test "Ctrl-R deletes an untracked file with spaces only after confirmation" {
    echo "x" > "my file.txt"
    echo "keep" > file.txt
    fzf_plan "ctrl-r::my file.txt" "ctrl-r::my file.txt" esc
    run gb_input '\ny\n' status
    [ ! -e "my file.txt" ]
    [ -e file.txt ]
}

@test "Ctrl-R restores a modified tracked file" {
    echo "changed" >> README.md
    git add README.md
    fzf_plan "ctrl-r::README.md" esc
    run gb_input 'y\n' status
    [ -z "$(git status --porcelain)" ]
}

@test "Ctrl-R on a newly added file unstages it and keeps it by default" {
    echo "new" > new.txt
    git add new.txt
    fzf_plan "ctrl-r::new.txt" esc
    run gb_input 'y\n\n' status
    [ -e new.txt ]
    [ -z "$(git diff --cached --name-only)" ]
}

@test "previews use the configured theme instead of a hard-coded one" {
    echo "one" >> README.md
    echo 'GITBASH_THEME="dark"' > "$HOME/.gitbashrc"
    run gb status
    if command -v delta >/dev/null; then
        fzf_args | grep -q 'delta --dark'
    fi
    ! fzf_args | grep -q 'delta --light'
}
