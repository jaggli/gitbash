---
"gitbash": major
---

**Breaking:** pushing (`commit -p`, `pr -p`, `update -p`, `status`) now goes to the branch's upstream, e.g. a fork remote or a remote branch with a different name, instead of always to `origin/<branch>`. A branch started from `origin/main` is still pushed under its own name, never to `main`.
