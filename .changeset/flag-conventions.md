---
"gitbash": major
---

**Breaking:** `stash`, `status`, `branch`, `stashes`, `unstash`, `cleanstash` and `switch` reject unknown options and extra arguments instead of treating them as names or ignoring them (`stash -- -name` for a stash name starting with `-`).

Consistent flags: `-y/--yes` is passed on to nested commands (`pr -y` no longer asks inside `commit`), and is now available on `create`, `commits`, `unstash` and `cleanstash`. New short forms `create -p` and `cleanup -n`; `--days` and `--age` also take a separate value.
