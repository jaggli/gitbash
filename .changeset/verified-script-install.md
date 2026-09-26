---
"gitbash": patch
---

The install script (and `gitbash --update` for script installs) now installs the package published on npm and verifies it against npm's sha512 checksum before installing anything, instead of downloading GitHub's tag archive unverified.
