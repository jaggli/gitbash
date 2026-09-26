---
"gitbash": minor
---

Security: for installs made with `install.sh`, `gitbash --update` downloaded the install script from the newest GitHub release's git tag and ran it, so anyone able to create a release (for example with a leaked GitHub token) could run code on updating machines without npm's 2FA approval. The npm package now includes `install.sh`, the install script keeps its verified copy, and `--update` runs that copy (it still downloads the new version from npm and checks its sha512). Installations made before this version show a one-time command to update; npm and pnpm installs are not affected.
