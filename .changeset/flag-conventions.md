---
"gitbash": patch
---

Consistent flags: `-y/--yes` is passed on to nested commands (`pr -y` no longer asks inside `commit`), and is now available on `create`, `commits`, `unstash` and `cleanstash`. New short forms `create -p` and `cleanup -n`; `--days` and `--age` also take a separate value. `stash`, `status`, `branch`, `stashes`, `unstash`, `cleanstash` and `switch` reject unknown options instead of treating them as names or ignoring them (`stash -- -name` for a name starting with `-`).
