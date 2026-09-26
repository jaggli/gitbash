---
"gitbash": patch
---

Security: a repository's committed `.gitbashrc` can no longer turn off gitbash's update checks (`GITBASH_NO_UPDATE_CHECKS`), so users working in it still hear about security releases. Set it in `~/.gitbashrc` or an uncommitted `.gitbashrc-user` instead.
