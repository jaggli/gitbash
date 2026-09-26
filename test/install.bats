#!/usr/bin/env bats
# install.sh: installs the npm package after checking npm's sha512 integrity

load helpers/setup

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export NPM_STUB_DIR="$BATS_TEST_TMPDIR/npm"
    mkdir -p "$NPM_STUB_DIR"
    export PATH="$HELPERS_DIR/install-bin:$PATH"
    export GITBASH_INSTALL_DIR="$BATS_TEST_TMPDIR/share/gitbash"
    export GITBASH_BIN_DIR="$BATS_TEST_TMPDIR/bin"
    unset GITBASH_VERSION
    publish 9.1.0
    echo '{"latest":"9.1.0"}' > "$NPM_STUB_DIR/dist-tags.json"
}

# Put a package for version $1 on the fake registry (like npm pack: a package/ folder)
publish() {
    local version="$1" pkg="$BATS_TEST_TMPDIR/pkg-$1" integrity
    mkdir -p "$pkg/package"
    cp -R "$PROJECT_DIR/bin" "$PROJECT_DIR/commands" "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/install.sh" "$pkg/package/"
    sed "s/\"version\": *\"[^\"]*\"/\"version\": \"$version\"/" "$PROJECT_DIR/package.json" > "$pkg/package/package.json"
    tar -czf "$NPM_STUB_DIR/gitbash-$version.tgz" -C "$pkg" package
    integrity="sha512-$(openssl dgst -sha512 -binary "$NPM_STUB_DIR/gitbash-$version.tgz" | openssl base64 -A)"
    # Like npm's document: the package's scripts come first and have a "version" key too
    printf '{"name":"gitbash","scripts":{"version":"changeset version"},"version":"%s","dist":{"shasum":"x","tarball":"https://registry.npmjs.org/gitbash/-/gitbash-%s.tgz","integrity":"%s"}}' \
        "$version" "$version" "$integrity" > "$NPM_STUB_DIR/$version.json"
}

@test "install.sh installs the latest version from npm after verifying it" {
    run sh "$PROJECT_DIR/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verified sha512 checksum."* ]]
    [ "$("$GITBASH_BIN_DIR/gitbash" --version)" = "gitbash 9.1.0" ]
    grep -qx 'method=script' "$GITBASH_INSTALL_DIR/.gitbash-install"
}

@test "install.sh keeps the verified install script for 'gitbash --update'" {
    run sh "$PROJECT_DIR/install.sh"
    [ "$status" -eq 0 ]
    cmp "$PROJECT_DIR/install.sh" "$GITBASH_INSTALL_DIR/install.sh"
}

@test "install.sh installs a chosen version" {
    publish 9.0.0
    GITBASH_VERSION=v9.0.0 run sh "$PROJECT_DIR/install.sh"
    [ "$status" -eq 0 ]
    [ "$("$GITBASH_BIN_DIR/gitbash" --version)" = "gitbash 9.0.0" ]
}

@test "install.sh installs nothing when the checksum does not match" {
    echo "tampered" >> "$NPM_STUB_DIR/gitbash-9.1.0.tgz"
    run sh "$PROJECT_DIR/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"checksum mismatch"* ]]
    [ ! -e "$GITBASH_INSTALL_DIR" ]
    [ ! -e "$GITBASH_BIN_DIR/gitbash" ]
}

@test "install.sh only downloads the package from npm" {
    sed -i.bak 's#https://registry.npmjs.org/gitbash/-/#https://evil.example/#' "$NPM_STUB_DIR/9.1.0.json"
    run sh "$PROJECT_DIR/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unexpected package location"* ]]
    [ ! -e "$GITBASH_INSTALL_DIR" ]
}

@test "install.sh rejects invalid versions and unknown ones" {
    GITBASH_VERSION='1;rm -rf' run sh "$PROJECT_DIR/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid GITBASH_VERSION"* ]]
    GITBASH_VERSION=8.8.8 run sh "$PROJECT_DIR/install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not find gitbash 8.8.8 on npm"* ]]
}
