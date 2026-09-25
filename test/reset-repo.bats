#!/usr/bin/env bats

load helpers/setup

setup() {
    setup_repo
    printf 'node_modules/\n*.log\n' > .gitignore
    git add .gitignore
    git commit --quiet -m "ignore"
    git push --quiet origin main 2>/dev/null
}

# A working tree with every kind of local change
make_mess() {
    echo "changed" > README.md
    echo "staged" > staged.txt
    git add staged.txt
    echo "untracked" > untracked.txt
    mkdir -p node_modules/pkg build
    echo "dep" > node_modules/pkg/index.js
    echo "out" > build/out.js
    echo "log" > debug.log
}

@test "reset-repo discards changes and deletes untracked and ignored files" {
    make_mess
    run gb reset-repo --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"is now like a fresh clone of 'origin/main'"* ]]
    [ "$(cat README.md)" = "hello" ]
    [ -z "$(git status --porcelain --ignored)" ]
    [ ! -e node_modules ]
    [ ! -e build ]
}

@test "reset-repo removes unpushed commits and pulls in new remote commits" {
    commit_file local.txt "l" "unpushed work"
    remote_commit main remote.txt "r" "teammate work"
    run gb reset-repo --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 unpushed commit(s) will be removed"* ]]
    [[ "$output" == *"unpushed work"* ]]
    [[ "$output" == *"git reflog"* ]]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
    [ -f remote.txt ]
    [ ! -e local.txt ]
}

@test "reset-repo asks first and changes nothing when declined" {
    make_mess
    run gb reset-repo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Untracked and ignored files to delete:"* ]]
    [[ "$output" == *"node_modules/"* ]]
    [[ "$output" == *"Aborted - nothing was changed."* ]]
    [ -f untracked.txt ]
    [ -f node_modules/pkg/index.js ]
    [ "$(cat README.md)" = "changed" ]

    run gb_input 'y\n' reset-repo
    [ "$status" -eq 0 ]
    [ ! -e untracked.txt ]
}

@test "reset-repo --dry-run only lists what would happen" {
    make_mess
    run gb reset-repo --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Local changes to discard:"* ]]
    [[ "$output" == *"README.md"* ]]
    [[ "$output" == *"untracked.txt"* ]]
    [[ "$output" == *"Dry run - nothing was changed."* ]]
    [ -f untracked.txt ]
    [ -f debug.log ]
}

@test "reset-repo keeps files matching GITBASH_RESET_KEEP from the config chain" {
    echo 'GITBASH_RESET_KEEP=".env *.log"' > "$HOME/.gitbashrc"
    make_mess
    echo "SECRET=1" > .env
    mkdir -p sub
    echo "x" > sub/.env
    echo "mine" > .gitbashrc-user
    run gb reset-repo --yes
    [ "$status" -eq 0 ]
    [ -f .env ]
    [ -f sub/.env ]
    [ -f debug.log ]
    [ -f .gitbashrc-user ]
    [ ! -e untracked.txt ]
    [ ! -e node_modules ]

    # A repository override replaces the global list
    echo 'GITBASH_RESET_KEEP="node_modules/"' > .gitbashrc-user
    mkdir -p node_modules && echo "dep" > node_modules/x.js
    run gb reset-repo --yes
    [ "$status" -eq 0 ]
    [ -f node_modules/x.js ]
    [ -f .gitbashrc-user ]
    [ ! -e .env ]
    [ ! -e debug.log ]
}

@test "reset-repo works from a subdirectory" {
    mkdir -p sub
    echo "x" > sub/a.txt
    echo "y" > top.txt
    cd sub
    run gb reset-repo --yes
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/top.txt" ]
    [ ! -e "$REPO/sub" ]
}

@test "reset-repo keeps the commits of a branch that is not on the remote" {
    git switch --quiet -c local-only
    commit_file l.txt "l" "local commit"
    echo "untracked" > untracked.txt
    run gb reset-repo --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"'local-only' is not on 'origin'"* ]]
    [ -f l.txt ]
    [ ! -e untracked.txt ]
    [ "$(git log -1 --format=%s)" = "local commit" ]
}

@test "reset-repo aborts an unfinished merge" {
    git switch --quiet -c other
    commit_file README.md "other" "other change"
    git switch --quiet main
    commit_file README.md "main" "main change"
    git merge other >/dev/null 2>&1 || true
    [ -f .git/MERGE_HEAD ]
    run gb reset-repo --yes
    [ "$status" -eq 0 ]
    [ ! -f .git/MERGE_HEAD ]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
    [ -z "$(git status --porcelain)" ]
}

@test "reset-repo aborts an unfinished rebase and resets the rebased branch" {
    git switch --quiet -c feature
    commit_file README.md "feature" "feature change"
    git push --quiet -u origin feature 2>/dev/null
    commit_file README.md "feature 2" "unpushed change"
    git switch --quiet main
    commit_file README.md "main" "main change"
    git switch --quiet feature
    git rebase main >/dev/null 2>&1 || true
    [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]
    run gb reset-repo --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resetting 'feature' to 'origin/feature'"* ]]
    [[ "$output" == *"unpushed change"* ]]
    [ "$(git branch --show-current)" = "feature" ]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/feature)" ]
    [ ! -d .git/rebase-merge ]
    [ ! -d .git/rebase-apply ]
}

@test "reset-repo reports when there is nothing to do" {
    run gb reset-repo
    [ "$status" -eq 0 ]
    [[ "$output" == *"already like a fresh clone"* ]]
}

@test "reset-repo fails on a detached HEAD and without the remote" {
    git switch --quiet --detach
    run gb reset-repo --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"Detached HEAD"* ]]

    git switch --quiet main
    git remote remove origin
    run gb reset-repo --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"No remote 'origin' configured."* ]]
}

@test "reset-repo rejects unknown arguments" {
    run gb reset-repo --nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown argument: --nope"* ]]
}
