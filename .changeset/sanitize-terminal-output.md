---
"gitbash": patch
---

Security: commit messages, file names, branch names and lines of a repository's `.gitbashrc` were printed with their terminal control characters, so a repository could write to the clipboard (OSC 52) or change what is shown before a confirmation. gitbash now removes control characters from them.
