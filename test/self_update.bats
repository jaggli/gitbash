#!/usr/bin/env bats
# gitbash --update and the background update check (no network: curl and npm are stubbed)

load helpers/setup

setup() {
    setup_repo
    unset GITBASH_NO_UPDATE_CHECKS XDG_STATE_HOME CI CONTINUOUS_INTEGRATION BUILD_NUMBER \
        GITHUB_ACTIONS GITLAB_CI TF_BUILD JENKINS_URL BUILDKITE CIRCLECI TRAVIS \
        TEAMCITY_VERSION BITBUCKET_BUILD_NUMBER
    export PATH="$HELPERS_DIR/update-bin:$PATH"
    export CURL_LOG="$BATS_TEST_TMPDIR/curl-log"
    export NPM_LOG="$BATS_TEST_TMPDIR/npm-log"
    export NPM_STUB_ROOT="$BATS_TEST_TMPDIR/npm-global/node_modules"
    export CURL_STUB_TAG="v9.9.9"
    STATE="$HOME/.local/state/gitbash/update-check"
    CURRENT=$(grep -o '"version": *"[^"]*"' "$PROJECT_DIR/package.json" | head -1 | cut -d'"' -f4)
    # The checkout itself is a git clone (no update checks): run an npm-style copy
    install_copy "$NPM_STUB_ROOT/gitbash"
}

# Copy gitbash to a directory like a package install (with README) and use it
install_copy() {
    mkdir -p "$1"
    cp -R "$PROJECT_DIR/bin" "$PROJECT_DIR/commands" "$PROJECT_DIR/package.json" "$PROJECT_DIR/README.md" "$1/"
    GB="$1/bin/gitbash"
}

# Run gitbash in a pty, typing KEYS once WAIT_FOR is printed; prints what the terminal showed
in_pty() {
    local log="$BATS_TEST_TMPDIR/pty-log" status=0
    rm -f "$log"
    PTY_LOG="$log" TIMEOUT="${TIMEOUT:-20}" python3 "$HELPERS_DIR/pty_run.py" \
        "\"${GB_BASH:-bash}\" \"$GB\" $*" || status=$?
    cat "$log" 2>/dev/null
    return "$status"
}

write_state() {
    mkdir -p "$(dirname "$STATE")"
    printf 'checked=%s\nlatest=%s\nprompted=%s\nskipped=%s\n' "$@" > "$STATE"
}

state_value() {
    sed -n "s/^$1=//p" "$STATE"
}

fetches() {
    if [[ -f "$CURL_LOG" ]]; then grep -c 'releases/latest' "$CURL_LOG"; else echo 0; fi
}

# Wait up to 5 seconds for the background check to store a version
wait_for_latest() {
    local i
    for i in $(seq 50); do
        [[ -n "$(state_value latest 2>/dev/null)" ]] && return 0
        sleep 0.1
    done
    return 1
}

@test "--update installs the new version with npm for a global npm install" {
    run gb --update
    [ "$status" -eq 0 ]
    grep -qx 'npm install -g gitbash@9.9.9' "$NPM_LOG"
    [[ "$output" == *"Updated gitbash $CURRENT → 9.9.9"* ]]
    [ "$(state_value latest)" = "9.9.9" ]
}

@test "--update does nothing when gitbash is up to date" {
    export CURL_STUB_TAG="v$CURRENT"
    run gb --update
    [ "$status" -eq 0 ]
    [[ "$output" == *"gitbash $CURRENT is up to date"* ]]
    [ ! -e "$NPM_LOG" ]
}

@test "--update reports when the latest version cannot be fetched" {
    unset CURL_STUB_TAG
    run gb --update
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not check for updates"* ]]
}

@test "--update re-runs the install script for script installs, with the same locations" {
    local dir
    mkdir -p "$BATS_TEST_TMPDIR/share/gitbash"
    dir=$(cd -P "$BATS_TEST_TMPDIR/share/gitbash" && pwd)
    cp -R "$PROJECT_DIR/bin" "$PROJECT_DIR/commands" "$PROJECT_DIR/package.json" "$dir/"
    printf 'method=script\nbin_dir=%s\n' "$BATS_TEST_TMPDIR/my-bin" > "$dir/.gitbash-install"
    GB="$dir/bin/gitbash"
    export CURL_STUB_INSTALLER="$BATS_TEST_TMPDIR/install.sh"
    cat > "$CURL_STUB_INSTALLER" <<'EOF'
echo "$GITBASH_VERSION|$GITBASH_INSTALL_DIR|$GITBASH_BIN_DIR" > "$INSTALL_LOG"
pkg="$GITBASH_INSTALL_DIR/package.json"
sed "s/\"version\": *\"[^\"]*\"/\"version\": \"$GITBASH_VERSION\"/" "$pkg" > "$pkg.new" && mv "$pkg.new" "$pkg"
EOF
    export INSTALL_LOG="$BATS_TEST_TMPDIR/install-log"

    run gb --update
    [ "$status" -eq 0 ]
    [ "$(cat "$INSTALL_LOG")" = "9.9.9|$dir|$BATS_TEST_TMPDIR/my-bin" ]
    grep -q 'jaggli/gitbash/v9.9.9/install.sh' "$CURL_LOG"
    [[ "$output" == *"Updated gitbash $CURRENT → 9.9.9"* ]]
}

@test "--update in a git checkout points to git pull" {
    GB="$PROJECT_DIR/bin/gitbash"
    run gb --update
    [ "$status" -eq 1 ]
    [[ "$output" == *"git pull"* ]]
    [ ! -e "$NPM_LOG" ]
}

@test "--update is listed in the help" {
    run gb --help
    [[ "$output" == *"--update"* ]]
}

@test "a command starts a background check once a day" {
    run gb stash --version
    [ "$status" -eq 0 ]
    wait_for_latest
    [ "$(state_value latest)" = "9.9.9" ]
    [ "$(fetches)" -eq 1 ]

    run gb stash --version
    sleep 0.3
    [ "$(fetches)" -eq 1 ]

    # A day later it checks again
    write_state "$(( $(date +%s) - 90000 ))" "9.9.9" 0 ""
    run gb stash --version
    sleep 0.5
    [ "$(fetches)" -eq 2 ]
}

@test "no update checks with GITBASH_NO_UPDATE_CHECKS in the environment" {
    GITBASH_NO_UPDATE_CHECKS=1 run gb stash --version
    [ "$status" -eq 0 ]
    sleep 0.3
    [ ! -e "$STATE" ]
    [ "$(fetches)" -eq 0 ]
}

@test "no update checks with GITBASH_NO_UPDATE_CHECKS in ~/.gitbashrc or .gitbashrc-user" {
    echo 'GITBASH_NO_UPDATE_CHECKS="yes"' > "$HOME/.gitbashrc"
    run gb stash --version
    sleep 0.3
    [ ! -e "$STATE" ]

    rm "$HOME/.gitbashrc"
    echo 'GITBASH_NO_UPDATE_CHECKS=yes' > .gitbashrc-user
    run gb stash --version
    sleep 0.3
    [ ! -e "$STATE" ]
    [ "$(fetches)" -eq 0 ]
}

@test "no update checks in CI" {
    CI=true run gb stash --version
    sleep 0.3
    [ ! -e "$STATE" ]
    [ "$(fetches)" -eq 0 ]
}

@test "never asks without a terminal" {
    write_state "$(date +%s)" "9.9.9" 0 ""
    run gb stash --version
    [ "$status" -eq 0 ]
    [[ "$output" != *"is available"* ]]
    [ "$(state_value prompted)" = "0" ]
}

@test "asks at a terminal and 'skip' never asks about that version again" {
    command -v python3 >/dev/null || skip "python3 not installed"
    write_state "$(date +%s)" "9.9.9" 0 ""
    WAIT_FOR="(y/N/s):" KEYS='s\r' run in_pty stash --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"gitbash 9.9.9 is available (you have $CURRENT)"* ]]
    [[ "$output" == *"gitbash stash v$CURRENT"* ]]
    [ "$(state_value skipped)" = "9.9.9" ]

    # Not asked again, even when asking would be due
    write_state "$(date +%s)" "9.9.9" 0 "9.9.9"
    run in_pty stash --version
    [[ "$output" != *"is available"* ]]

    # But a newer version is offered
    write_state "$(date +%s)" "9.9.10" 0 "9.9.9"
    WAIT_FOR="(y/N/s):" KEYS='n\r' run in_pty stash --version
    [[ "$output" == *"gitbash 9.9.10 is available"* ]]
}

@test "'not now' asks again only after two days" {
    command -v python3 >/dev/null || skip "python3 not installed"
    write_state "$(date +%s)" "9.9.9" 0 ""
    WAIT_FOR="(y/N/s):" KEYS='n\r' run in_pty stash --version
    [[ "$output" == *"is available"* ]]
    [ "$(state_value prompted)" -gt 0 ]

    run in_pty stash --version
    [[ "$output" != *"is available"* ]]

    # One day later: still quiet; two days later: asked again
    write_state "$(date +%s)" "9.9.9" "$(( $(date +%s) - 90000 ))" ""
    run in_pty stash --version
    [[ "$output" != *"is available"* ]]
    write_state "$(date +%s)" "9.9.9" "$(( $(date +%s) - 180000 ))" ""
    WAIT_FOR="(y/N/s):" KEYS='n\r' run in_pty stash --version
    [[ "$output" == *"is available"* ]]
}

@test "'yes' updates and runs the command with the new version" {
    command -v python3 >/dev/null || skip "python3 not installed"
    write_state "$(date +%s)" "9.9.9" 0 ""
    WAIT_FOR="(y/N/s):" KEYS='y\r' run in_pty stash --version
    [ "$status" -eq 0 ]
    grep -qx 'npm install -g gitbash@9.9.9' "$NPM_LOG"
    [[ "$output" == *"gitbash stash v9.9.9"* ]]
}

@test "--config-user can turn update checks off" {
    # Keep every setting (Enter) except the last one: update checks
    run gb_input '\n\n\n\n\n\n\n\n\n\n\n\nno\n' --config-user
    [ "$status" -eq 0 ]
    grep -qx 'GITBASH_NO_UPDATE_CHECKS="yes"' .gitbashrc-user
    run gb stash --version
    sleep 0.3
    [ ! -e "$STATE" ]
}

@test "--config-local does not ask about update checks" {
    run gb_input '\n\n\n\n\n\n\n\n\n\n\n\n' --config-local
    [ "$status" -eq 0 ]
    [[ "$output" != *"Check for gitbash updates"* ]]
}
