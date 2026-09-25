# gitbash

## 2.0.1

### Patch Changes

- ff7f2b9: stale/cleanup: show the commit author instead of the committer, so branches updated via GitHub's "Update branch" button no longer show "GitHub" as the owner

## 2.0.0

### Major Changes

- 30949c3: gitbash 2.0: security, safety and reliability release.

  **Upgrading from 1.x**

  - **Restart your shell** after upgrading, so `eval "$(gitbash --init)"` picks up the new wrapper functions.
  - Config files are **read, not executed**: only plain `GITBASH_*="value"` lines are used, other lines are ignored with a warning. `GITBASH_MERGE_COMMAND` is ignored in a committed `.gitbashrc`.
  - `status` no longer commits and pushes after staging. Use `Ctrl-O` to commit.
  - `stale` toggles all/stale branches with `Ctrl-T` (was `Ctrl-A`).
  - Protected branches (base branch and `GITBASH_PROTECTED_BRANCHES`) are never offered for deletion. `cleanup` and `switch` delete with `git branch -d` and ask again before force-deleting unmerged work.
  - When your branch and the remote diverged, `commit -p`, `pr -p` and `update -p` ask whether to rebase, merge or abort instead of rebasing silently.
  - fzf 0.36 or newer is required for the interactive menus.

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

## 1.9.1

### Patch Changes

- dc7dfd5: confirm branch deletions
- 66ed630: Switch backspace does not delete branch

## 1.9.0

### Minor Changes

- fc22578: Add delete option to switch

### Patch Changes

- 57ad8b9: Improve zero match in switch, fixes #51
- fef572f: only allow delete local branches fixes #45
- baffd8b: Don't confirm, the commit if there are changes, AND the -p was provided. So -p assumes commiting

## 1.8.2

### Patch Changes

- 82a8b7f: Fix a bug in `switch` for direct selection

## 1.8.1

### Patch Changes

- ce7bc07: fix double listing in stale

## 1.8.0

### Minor Changes

- 85ab3fe: Add local user settings override

## 1.7.0

### Minor Changes

- 2bf4222: Add local config overrides, fixes #33

### Patch Changes

- 55eebb4: Don't ask for push, if there was nothing commited in pr

## 1.6.7

### Patch Changes

- d74d704: improve wording in readme

## 1.6.6

### Patch Changes

- ff0a179: remove links from readme, to hopefully display readme in npm again

## 1.6.5

### Patch Changes

- b9d90e8: refactor docs

## 1.6.4

### Patch Changes

- 8001953: Add comparison table in documentation

## 1.6.3

### Patch Changes

- chore: cleanup repository

## 1.6.2

### Patch Changes

- 68aacec: Improve cleanup performance
- f778d26: fix internal tool calling

## 1.6.1

### Patch Changes

- 7b6b022: fix version output
- 9475dfd: fix script import dir

## 1.6.0

### Minor Changes

- 1f8edda: Add a full changelog of what happened in the past

### Patch Changes

- 1a2b4da: Fix bug when there was still an old file present to display everything twice, fixes #20
- e014088: chore: Better and easier one-line release command in package.json
- f094076: Fix bug in switch for no-match filtes #18
- e4f91c0: Fix stale --all --json
- 6d87faa: hide empty sections in preview when using status(), fixes #15
- d8184da: After successfully applying a stash, the default answer is Y to drop the stash
- 316a2f8: pr offers to commit and push if there are uncommited changes, fixes #26

## 1.5.0

### Minor Changes

- cba8b0c: Add changeset to respository
- de5072b: Improve automated release command
- f094076: Fix switch bug when filter has no matches
- ab627b0: Ensure cleanup of temp files on program exit in stale command
- d56830d: Fix stale --all --json to respect --all flag
- 4e38ef7: Hide empty sections in preview when using status command

### Patch Changes

- d8184da: After successfully applying a stash, the default answer is Y to drop the stash

## 1.4.0

### Minor Changes

- b39100d: Add -a/--all option to stale command to start in all branches mode
- 6742d94: Remove unnecessary confirmation when all changes are staged in status command
- 5931765: Only show branch prefix tip when non-empty prefix configured
- 37257c3: Allow users to clear the branch prefix in config
- 8083adf: Introduce general branch prefix configuration, not only for feature branches
- 76334a2: Reverse logic in question for disabling Jira parsing
- 60cb4d4: Implement configurable Jira issue parsing with GITBASH_CREATE_NO_ISSUE_PARSING and GITBASH_CREATE_ISSUE_PARSING_FALLBACK

## 1.3.7

### Patch Changes

- 0a28ea8: Switch directly if only one branch matches the filter

## 1.3.6

### Patch Changes

- 6e8693d: Fix readme

## 1.3.5

### Patch Changes

- b4391dc: Ask to update after branch switching when not updated
- 83f208d: Update readme

## 1.3.4

### Patch Changes

- 0b3c107: Remove blank lines
- 790aa9d: Fix broken command args parsing
- b9d904b: Mute log during fetching

## 1.3.3

### Patch Changes

- c0c21a4: Read config correctly

## 1.3.2

### Patch Changes

- 53c84f0: Fix positional arguments

## 1.3.1

### Patch Changes

- 901bd03: Don't fail when no Jira link present

## 1.3.0

### Minor Changes

- 7c8a734: Refactor and bugfix of unclosed parenthesis

## 1.2.0

### Minor Changes

- 178ab99: Refactor and add more options to commit, create and stale commands
- ef53dee: Update license
- 499fb4c: Refactoring

## 1.1.0

### Minor Changes

- fb9a6c6: Initial feature release

## 1.0.0

### Major Changes

- 0b8aa17: Bug fixes for stable release
- 118cc25: Add dependencies install
- 425dc1f: Add config to installation
- 4ef7813: Use light theme for diffs
- 5e758fb: Use delta if available for better diff viewing

## 0.2.7

### Patch Changes

- ed7f95e: Remove excessive output
- f194f58: Shell integration check

## 0.2.6

### Patch Changes

- 5b6c0b4: Add zsh compatibility

## 0.2.5

### Patch Changes

- 1c4c280: Add configuration system
- 40bdbff: Add --config option

## 0.2.4

### Patch Changes

- f65d8c2: Fix cleanup

## 0.2.3

### Patch Changes

- 3b4b549: Fix bash migration bugs

## 0.2.2

### Patch Changes

- 7a9356f: Update readme
- f7ac5b2: Fix bash migration bugs

## 0.2.1

### Patch Changes

- 2088a00: Fix version reading

## 0.2.0

### Minor Changes

- d6458ad: Add version option to all commands

## 0.1.0

### Minor Changes

- 67b431a: Initial release
- 394fee3: Improve chore commands
- ae5251e: Initial commit
