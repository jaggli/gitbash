---
"gitbash": patch
---

Security: `reset-repo` ran `git submodule update --init`, which cloned every URL in the repository's `.gitmodules`, also submodules you never initialized (a fresh clone doesn't). It now only resets submodules that are already initialized; run `git submodule update --init` yourself to clone the others.
