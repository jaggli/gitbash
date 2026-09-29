---
"gitbash": patch
---

`switch <branch>` now also finds a branch that was pushed to the remote since the last fetch: a branch name that is not known locally is fetched from the remote first, and a local tracking branch is created (#82).
