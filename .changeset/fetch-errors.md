---
"gitbash": patch
---

`cleanup` and `stale` now say why a fetch failed instead of only "Fetch failed" (#83). git fails the whole fetch when a single branch can't be updated: on macOS and Windows that happens on every fetch when the remote has branches whose names differ only in case (`Feature/x` and `feature/x`). The warning now names the branches that weren't updated, says that all others were, and explains the case conflict; other errors (network, access) show git's message.
