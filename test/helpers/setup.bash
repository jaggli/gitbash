# Shared test setup: an isolated HOME, a bare "remote" and a clone to work in.
#
# GB_BASH selects the bash used to run gitbash (e.g. /bin/bash for bash 3.2).

HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$HELPERS_DIR/../.." && pwd)"
GB="$PROJECT_DIR/bin/gitbash"

setup_repo() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    git config --global user.name "Test User"
    git config --global user.email "test@example.com"
    git config --global init.defaultBranch main
    git config --global advice.detachedHead false

    # Stubs (fzf, open, xdg-open, gh, fork) and, if requested, a specific bash first on PATH
    local path_prefix="$HELPERS_DIR/bin"
    if [[ -n "${GB_BASH:-}" ]]; then
        mkdir -p "$BATS_TEST_TMPDIR/bash-bin"
        ln -sf "$GB_BASH" "$BATS_TEST_TMPDIR/bash-bin/bash"
        path_prefix="$BATS_TEST_TMPDIR/bash-bin:$path_prefix"
    fi
    export PATH="$path_prefix:$PATH"
    export FZF_STUB_LOG="$BATS_TEST_TMPDIR/fzf-log"
    export OPEN_LOG="$BATS_TEST_TMPDIR/opened"
    export MERGE_TOOL_LOG="$BATS_TEST_TMPDIR/merge-tool"
    unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZF_STUB_PLAN FZF_STUB_STEP NO_COLOR
    unset GITBASH_ASSUME_YES GITBASH_MERGE_COMMAND

    REMOTE="$BATS_TEST_TMPDIR/remote.git"
    REPO="$BATS_TEST_TMPDIR/repo"
    git init --quiet --bare "$REMOTE"
    git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
    git clone --quiet "$REMOTE" "$REPO" 2>/dev/null
    cd "$REPO" || return 1
    echo "hello" > README.md
    git add README.md
    git commit --quiet -m "init"
    git push --quiet origin main 2>/dev/null
    git remote set-head origin main >/dev/null
}

# Run gitbash with no input (prompts read EOF and use their default)
gb() {
    "${GB_BASH:-bash}" "$GB" "$@" < /dev/null
}

# Run gitbash with input for prompts, e.g.: run gb_input 'y\nmessage\n' commit
gb_input() {
    local input="$1"
    shift
    printf '%b' "$input" | "${GB_BASH:-bash}" "$GB" "$@"
}

# Write an fzf plan (one step per line) and activate it
fzf_plan() {
    export FZF_STUB_PLAN="$BATS_TEST_TMPDIR/fzf-plan"
    printf '%s\n' "$@" > "$FZF_STUB_PLAN"
}

# Arguments / input of the n-th fzf call (0-based)
fzf_args() { cat "$FZF_STUB_LOG/${1:-0}.args"; }
fzf_input() { cat "$FZF_STUB_LOG/${1:-0}.in"; }
fzf_env() { cat "$FZF_STUB_LOG/${1:-0}.env"; }

# Commit a file with content; optional date makes the commit old
commit_file() {
    local file="$1" content="$2" message="$3" date="${4:-}"
    printf '%s\n' "$content" > "$file"
    git add -- "$file"
    if [[ -n "$date" ]]; then
        GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git commit --quiet -m "$message"
    else
        git commit --quiet -m "$message"
    fi
}

# Push a new commit to origin/<branch> from a second clone ("a teammate")
remote_commit() {
    local branch="$1" file="$2" content="$3" message="$4"
    local other="$BATS_TEST_TMPDIR/other-$RANDOM"
    git clone --quiet "$REMOTE" "$other" 2>/dev/null
    (
        cd "$other" || exit 1
        git checkout --quiet "$branch" 2>/dev/null || git checkout --quiet -b "$branch"
        printf '%s\n' "$content" > "$file"
        git add -- "$file"
        git commit --quiet -m "$message"
        git push --quiet origin "$branch" 2>/dev/null
    )
}

remote_has_branch() {
    [[ -n "$(git ls-remote --heads "$REMOTE" "refs/heads/$1")" ]]
}
