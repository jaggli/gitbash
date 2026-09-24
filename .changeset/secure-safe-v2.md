---
"gitbash": major
---

gitbash 2.0: security, safety and reliability release.

**Security**

- Config files (`~/.gitbashrc`, `.gitbashrc`, `.gitbashrc-user`) are now parsed instead of executed. Before, a cloned repository could run arbitrary code through its `.gitbashrc`.
- A committed `.gitbashrc` can no longer choose the merge tool that `update` runs.
- `pr` no longer passes credentials from an `https://user:token@` remote to the browser.

**Fixes**

- `commit -p`, `pr -p` and `update -p` no longer exit silently on branches that are not on the remote yet; new branches are pushed with tracking.
- `cleanup` no longer exits silently when a local branch has no upstream.
- `update` works with local changes again (the commit step failed when not using shell integration) and can stash them instead.
- `cleanup` no longer labels unrelated branches (e.g. a branch tracking `origin/main` under another name) as merged, and never force-deletes unmerged work without a second confirmation.
- `create` run on `main` now branches from the latest `origin/main` instead of a stale local `main`.
- `status` handles file names with spaces, renames and partially staged files.
- `commits` reverts selected commits newest first and supports merge commits.
- `--amend -p` asks before force-pushing instead of rebasing onto the old commit.
- User `FZF_DEFAULT_OPTS` and non-bash login shells no longer break menus and previews.
- The release script now tags the release commit (tags pointed to the commit before).

**Breaking changes**

- Config files: only plain `GITBASH_*="value"` lines are read; anything else is ignored with a warning.
- `gitbash --init` prints wrapper functions instead of sourcing the scripts. Restart your shell after upgrading. `--init --prefix=gb-` creates prefixed commands.
- `status` no longer commits and pushes after staging; use `Ctrl-O` to commit.
- `stale` toggles all/stale branches with `Ctrl-T` (was `Ctrl-A`). Its JSON `author_name` is now the last committer.
- Protected branches (base branch and `GITBASH_PROTECTED_BRANCHES`, default `main master develop release/*`) are never listed by `stale`, `cleanup` or deletable in `switch`.
- `cleanup` and `switch` delete with `git branch -d`; branch deletion in `switch` defaults to no.
- Pushing after the remote diverged asks to rebase, merge or abort instead of rebasing silently.
- Requires fzf 0.36+ for interactive menus and git 2.23+.

**New**

- Settings `GITBASH_PROTECTED_BRANCHES`, `GITBASH_BASE_BRANCH`, `GITBASH_REMOTE`, `GITBASH_CREATE_AUTO_PUSH`.
- `commit --yes`, `commit --force-with-lease`, `commit -- <message>`; `cleanup --yes` and a non-interactive `--dry-run`; `create --push/--no-push`; `pr --print`.
- `pr` opens existing pull requests via the GitHub CLI and supports GitLab, Bitbucket, Azure DevOps and GitHub Enterprise.
- `cleanup` detects squash-merged branches and shows unpushed commits; new `[GONE]` label.
- `create` transliterates umlauts and accents and accepts more issue key formats.
- Colors respect `NO_COLOR`; errors go to stderr.
- Test suite (bats) and CI on Ubuntu and macOS.
