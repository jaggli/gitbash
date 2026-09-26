---
"gitbash": patch
---

`gitbash --update` and the update check now take the latest version from npm, like the install script, instead of from GitHub releases. npm's `latest` tag only moves when a maintainer approves a release with 2FA.
