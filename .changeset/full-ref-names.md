---
"gitbash": patch
---

Security: gitbash passed short names like `origin/main` to git, which resolves them to a **tag** of the same name first. Anyone who can push a tag (for example to a repository where `main` is protected) could make `update` merge an unreviewed commit, `create` start new branches from it, and `reset-repo` reset your branch to it; a tag named like a branch also broke the base branch detection and the branch lists. gitbash now uses full ref names (`refs/remotes/origin/main`, `refs/heads/…`) everywhere.
