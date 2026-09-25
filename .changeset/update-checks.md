---
"gitbash": minor
---

Add `gitbash --update`, which installs the latest release with npm or the install script, depending on how gitbash was installed. gitbash now also checks for new releases in the background (at most once a day) and offers the update on the next command at a terminal (at most every other day), with an option to skip a version. Turn the checks off with `GITBASH_NO_UPDATE_CHECKS` or in `gitbash --config` / `--config-user`; they are always off in CI
