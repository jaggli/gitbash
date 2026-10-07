---
"gitbash": patch
---

`reset-repo`, `cleanup` and `stale` no longer fail to fetch when two deleted branches have names that differ only in case (`feature/Raven/x` and `feature/raven/x`). On macOS and Windows git can't prune both at once and reported a lock error; gitbash now deletes them one by one.
