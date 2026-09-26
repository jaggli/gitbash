---
"gitbash": patch
---

Security: a committed `.gitbashrc` could set `GITBASH_BASE_BRANCH` to a git option such as `--output=<file>` and make `switch` or `cleanup` overwrite that file. Base branch names (from any config file or the remote's HEAD) and `GITBASH_REMOTE` can no longer start with `-`, and `stale` deletes remote branches through an explicit refspec.
