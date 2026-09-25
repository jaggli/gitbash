#!/bin/sh
# gitbash installer - installs gitbash from a GitHub release, no npm or node needed.
#
#   curl -fsSL https://raw.githubusercontent.com/jaggli/gitbash/main/install.sh | sh
#   wget -qO- https://raw.githubusercontent.com/jaggli/gitbash/main/install.sh | sh
#
# Environment:
#   GITBASH_VERSION      version to install, e.g. 2.0.1 or v2.0.1 (default: latest release)
#   GITBASH_INSTALL_DIR  where the files go (default: ${XDG_DATA_HOME:-~/.local/share}/gitbash)
#   GITBASH_BIN_DIR      where the gitbash symlink goes (default: ~/.local/bin)
#
# Run it again to upgrade.
set -eu

REPO="jaggli/gitbash"
INSTALL_DIR="${GITBASH_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/gitbash}"
BIN_DIR="${GITBASH_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }
die() { printf 'gitbash install: %s\n' "$*" >&2; exit 1; }

if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL "$1"; }
    fetch_to() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -qO- "$1"; }
    fetch_to() { wget -qO "$2" "$1"; }
else
    die "curl or wget is required"
fi
command -v tar >/dev/null 2>&1 || die "tar is required"
command -v bash >/dev/null 2>&1 || die "bash is required to run gitbash"
command -v git >/dev/null 2>&1 || say "Warning: git is not installed; gitbash needs git >= 2.23."

# Resolve the version
version="${GITBASH_VERSION:-}"
if [ -z "$version" ]; then
    version="$(fetch "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)" || true
    [ -n "$version" ] || die "could not determine the latest release (set GITBASH_VERSION to pick one)"
fi
version="v${version#v}"

# Refuse to replace a directory that is not a gitbash install
if [ -e "$INSTALL_DIR" ] && [ ! -f "$INSTALL_DIR/bin/gitbash" ]; then
    die "$INSTALL_DIR exists and is not a gitbash install; set GITBASH_INSTALL_DIR to another location"
fi

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t gitbash)"
trap 'rm -rf "$tmp"' EXIT INT TERM

say "Downloading gitbash $version..."
fetch_to "https://github.com/$REPO/archive/refs/tags/$version.tar.gz" "$tmp/gitbash.tar.gz" \
    || die "download failed; does release $version exist?"
mkdir "$tmp/src"
tar -xzf "$tmp/gitbash.tar.gz" -C "$tmp/src"
src="$(find "$tmp/src" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$src" ] && [ -f "$src/bin/gitbash" ] || die "unexpected archive layout"

# Copy only what gitbash needs at runtime
mkdir "$tmp/install"
cp -R "$src/bin" "$src/commands" "$src/package.json" "$tmp/install/"
[ -f "$src/LICENSE" ] && cp "$src/LICENSE" "$tmp/install/"
chmod +x "$tmp/install/bin/gitbash"

mkdir -p "$(dirname "$INSTALL_DIR")" "$BIN_DIR"
rm -rf "$INSTALL_DIR"
mv "$tmp/install" "$INSTALL_DIR"
ln -sf "$INSTALL_DIR/bin/gitbash" "$BIN_DIR/gitbash"

say "Installed gitbash $version to $INSTALL_DIR"
say "Linked $BIN_DIR/gitbash"

case ":$PATH:" in
    *":$BIN_DIR:"*)
        found="$(command -v gitbash 2>/dev/null || true)"
        if [ -n "$found" ] && [ "$found" != "$BIN_DIR/gitbash" ]; then
            say ""
            say "Note: 'gitbash' currently resolves to $found, which comes before $BIN_DIR in PATH."
        fi
        ;;
    *)
        say ""
        say "$BIN_DIR is not in your PATH. Add this to your .zshrc or .bashrc:"
        say "  export PATH=\"$BIN_DIR:\$PATH\""
        ;;
esac

say ""
say "Next: run 'gitbash --config', and see the README for shell integration."
