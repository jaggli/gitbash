#!/usr/bin/env bats
# Tests against the real fzf binary (skipped when fzf or python3 is missing).

load helpers/setup

setup() {
    setup_repo
    REAL_FZF=""
    local candidate
    while IFS= read -r candidate; do
        [[ "$candidate" == "$HELPERS_DIR/bin/fzf" ]] && continue
        REAL_FZF="$candidate"
        break
    done < <(type -ap fzf)
    [[ -n "$REAL_FZF" ]] || skip "real fzf not installed"
    command -v python3 >/dev/null || skip "python3 not installed"
    # Put the real fzf ahead of the stub
    mkdir -p "$BATS_TEST_TMPDIR/real-bin"
    ln -sf "$REAL_FZF" "$BATS_TEST_TMPDIR/real-bin/fzf"
    export PATH="$BATS_TEST_TMPDIR/real-bin:$PATH"
}

# Run a command in a pty, typing KEYS
in_pty() {
    python3 "$HELPERS_DIR/pty_run.py" "$1"
}

@test "installed fzf meets the minimum version" {
    run bash -c 'source "$1/commands/_utils.sh"; require_fzf' _ "$PROJECT_DIR"
    [ "$status" -eq 0 ]
}

@test "previews run in bash even when SHELL is not a POSIX shell" {
    local out="$BATS_TEST_TMPDIR/preview-out"
    # 'become' runs like a preview: through SHELL, with {} substituted
    run in_pty "SHELL=/usr/bin/false bash -c 'source \"$PROJECT_DIR/commands/_utils.sh\"; printf \"a b\\n\" | run_fzf --bind \"load:become:[[ {} == \\\"a b\\\" ]] && echo \\\$BASH_VERSION > $out\"'"
    [ -s "$out" ]
}

@test "FZF_DEFAULT_OPTS=--print-query does not change what run_fzf prints" {
    local out="$BATS_TEST_TMPDIR/selected"
    FZF_DEFAULT_OPTS="--print-query --multi" run in_pty "bash -c 'source \"$PROJECT_DIR/commands/_utils.sh\"; printf \"one\\ntwo\\n\" | run_fzf --bind load:accept > $out'"
    [ "$(cat "$out")" = "one" ]
}

@test "switch: Enter switches to the selected branch" {
    git branch feature/pick
    KEYS='pick\r' run in_pty "\"${GB_BASH:-bash}\" \"$GB\" switch"
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/pick" ]
}

@test "status: Enter stages the selected file" {
    echo "x" > "my file.txt"
    # Enter stages, then Esc exits
    KEYS='\r<pause>\x1b' run in_pty "\"${GB_BASH:-bash}\" \"$GB\" status"
    [ "$status" -eq 0 ]
    [ "$(git diff --cached --name-only)" = "my file.txt" ]
}

@test "switch: Del asks, deletes the branch and reloads the list" {
    git branch feature/delete-me
    KEYS='delete-me<pause>\x1b[3~<pause>y\r<pause>\x1b' run in_pty "\"${GB_BASH:-bash}\" \"$GB\" switch"
    [ "$status" -eq 0 ]
    ! git show-ref --verify --quiet refs/heads/feature/delete-me
    [ "$(git branch --show-current)" = "main" ]
}
