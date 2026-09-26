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
    run gb_input 'mine\n\n\n\n\n\n\n\n\n\n\n\n\n' --config-user
    [ "$status" -eq 0 ]
    grep -qx 'GITBASH_CREATE_BRANCH_PREFIX="mine"' .gitbashrc-user
    [ ! -e .gitignore ]
    grep -qx '.gitbashrc-user' .git/info/exclude
}

@test "the wizard rejects values that would be code in older versions" {
    run gb_input '$(touch x)\nok\n\n\n\n\n\n\n\n\n\n\n\n' --config-local
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

# Stub powershell.exe and pwsh.exe: each has its profile in $PWSH_STUB_DIR/<exe>.ps1
# and the execution policy $PWSH_STUB_POLICY; commands are logged to $PWSH_STUB_DIR/log
pwsh_stubs() {
    export PWSH_STUB_DIR="$BATS_TEST_TMPDIR/pwsh"
    export PWSH_STUB_POLICY="$1"
    mkdir -p "$PWSH_STUB_DIR/bin"
    cat > "$PWSH_STUB_DIR/bin/powershell.exe" <<'STUB'
#!/usr/bin/env bash
cmd="${*: -1}"
profile="$PWSH_STUB_DIR/$(basename "$0").ps1"
printf '%s: %s\n' "$(basename "$0")" "$cmd" >> "$PWSH_STUB_DIR/log"
case "$cmd" in
    *Get-ExecutionPolicy*)
        has=False
        grep -qF 'gitbash --init' "$profile" 2>/dev/null && has=True
        printf '%s|%s|%s\r\n' "$profile" "$has" "$PWSH_STUB_POLICY"
        ;;
    *Add-Content*)
        [[ "$cmd" =~ \'([^\']*)\'$ ]] && printf '%s\n' "${BASH_REMATCH[1]}" >> "$profile"
        ;;
esac
STUB
    chmod +x "$PWSH_STUB_DIR/bin/powershell.exe"
    cp "$PWSH_STUB_DIR/bin/powershell.exe" "$PWSH_STUB_DIR/bin/pwsh.exe"
    # delta and bat "installed": no offer to install dependencies
    printf '#!/bin/sh\n' > "$PWSH_STUB_DIR/bin/delta"
    printf '#!/bin/sh\n' > "$PWSH_STUB_DIR/bin/bat"
    chmod +x "$PWSH_STUB_DIR/bin/delta" "$PWSH_STUB_DIR/bin/bat"
    export PATH="$PWSH_STUB_DIR/bin:$PATH"
}

@test "--config on Windows loads the functions in the PowerShell profiles and allows scripts" {
    gb_is_windows_host || skip "not on Windows"
    pwsh_stubs Restricted
    run gb_input '\n\n\n\n\n\n\n\n\n\n\n\n\ny\ny\ny\ny\n' --config
    [ "$status" -eq 0 ]
    for exe in powershell.exe pwsh.exe; do
        [ "$(cat "$PWSH_STUB_DIR/$exe.ps1")" = 'gitbash --init --shell=pwsh | Out-String | Invoke-Expression' ]
        grep -q "^$exe: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force" "$PWSH_STUB_DIR/log"
    done

    # Once is enough
    run gb_input '\n\n\n\n\n\n\n\n\n\n\n\n\n' --config
    [ "$status" -eq 0 ]
    [[ "$output" == *"PowerShell integration already configured"* ]]
    [ "$(wc -l < "$PWSH_STUB_DIR/pwsh.exe.ps1")" -eq 1 ]
}

@test "--config on Windows leaves a RemoteSigned execution policy alone" {
    gb_is_windows_host || skip "not on Windows"
    pwsh_stubs RemoteSigned
    run gb_input '\n\n\n\n\n\n\n\n\n\n\n\n\ny\ny\n' --config
    [ "$status" -eq 0 ]
    [ -s "$PWSH_STUB_DIR/pwsh.exe.ps1" ]
    ! grep -q "Set-ExecutionPolicy" "$PWSH_STUB_DIR/log"
}

@test "the PowerShell commands of --config work in real PowerShell" {
    command -v pwsh >/dev/null || skip "pwsh not installed"
    # On Windows this would change the real profile; elsewhere $PROFILE is under $HOME
    gb_is_windows_host && skip "on Windows"
    pwsh_stubs Restricted
    printf '#!/bin/sh\nexec pwsh "$@"\n' > "$PWSH_STUB_DIR/bin/pwsh.exe"
    rm "$PWSH_STUB_DIR/bin/powershell.exe"
    local profile
    profile=$(pwsh -NoProfile -NonInteractive -Command 'Write-Output $PROFILE')
    # Run gitbash as if on Windows
    run bash -c 'printf "\n\n\n\n\n\n\n\n\n\n\n\n\ny\n" | "${GB_BASH:-bash}" -c "OSTYPE=msys; source \"\$1\" --config" _ "$1"' _ "$GB"
    [ "$status" -eq 0 ]
    [ "$(cat "$profile")" = 'gitbash --init --shell=pwsh | Out-String | Invoke-Expression' ]

    run bash -c 'printf "\n\n\n\n\n\n\n\n\n\n\n\n\n" | "${GB_BASH:-bash}" -c "OSTYPE=msys; source \"\$1\" --config" _ "$1"' _ "$GB"
    [[ "$output" == *"PowerShell integration already configured in $profile"* ]]
}

@test "a committed GITBASH_BASE_BRANCH cannot inject git options" {
    local victim="$BATS_TEST_TMPDIR/victim"
    echo "important" > "$victim"
    printf 'GITBASH_BASE_BRANCH="--output=%s"\n' "$victim" > .gitbashrc
    git switch --quiet -c unmerged
    commit_file u.txt "u" "unmerged work"
    git switch --quiet main
    # Deleting an unmerged branch counts its commits against the base branch
    run gb_input 'y\nn\n' switch --delete-branch $'local: unmerged\tlocal\tunmerged'
    [[ "$output" == *"Invalid GITBASH_BASE_BRANCH"* ]]
    [ "$(cat "$victim")" = "important" ]
}

@test "a base branch name from the remote's HEAD cannot inject git options" {
    git push --quiet origin "main:refs/heads/--output=victim"
    git fetch --quiet origin
    git symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/--output=victim"
    # Dangling (e.g. pruned): the base ref falls back to the bare name
    git update-ref -d "refs/remotes/origin/--output=victim"
    git switch --quiet -c unmerged
    commit_file u.txt "u" "unmerged work"
    git switch --quiet main
    run gb_input 'y\nn\n' switch --delete-branch $'local: unmerged\tlocal\tunmerged'
    [ ! -e victim ]
}

@test "a remote name that looks like an option is rejected" {
    echo 'GITBASH_REMOTE="--all"' > .gitbashrc
    run gb repo --print
    [[ "$output" == *"Invalid GITBASH_REMOTE"* ]]
}
