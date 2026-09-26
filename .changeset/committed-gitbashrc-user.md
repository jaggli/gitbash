---
"gitbash": patch
---

Security: a repository that commits a `.gitbashrc-user` file could set `GITBASH_MERGE_COMMAND`, and `update` ran that program when a merge had conflicts. A `.gitbashrc-user` that is tracked by git is now treated like the committed `.gitbashrc`: it cannot choose a program to run.
