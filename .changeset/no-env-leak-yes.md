---
"gitbash": patch
---

`-y` (`GITBASH_ASSUME_YES`) and gitbash's internal `GITBASH_NESTED` and `GB_COLOR` are no longer exported to git hooks, editors and merge tools; only gitbash commands run by gitbash (and fzf previews) get them. Before, a gitbash started from a hook during `commit -y` answered yes to every question.
