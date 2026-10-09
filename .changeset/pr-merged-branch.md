---
"gitbash": patch
---

`pr` on a branch whose pull request was already merged now opens that pull request instead of offering to push the branch again (needs the GitHub CLI). New commits after the merge still go through the usual push and create flow.
