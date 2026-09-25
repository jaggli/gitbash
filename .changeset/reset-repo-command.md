---
"gitbash": minor
---

New `reset-repo` command: resets the current branch like a fresh clone (fetch, `reset --hard <remote>/<branch>`, delete untracked and ignored files) after listing what is lost and asking. Files matching the new `GITBASH_RESET_KEEP` setting (e.g. `.env`) and `.gitbashrc-user` are kept; `--dry-run` only lists, `--yes` skips the question
