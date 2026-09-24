# gitbash

Pure bash, zero-dependency git utilities. Reduce repetitive typing and supercharge git workflows with optional interactive previews and safe cleanup — see a [full comparison](./docs/workflows.md).

![screenshot-status.png](./docs/screenshot-status.png)

## Installation

### Via npm

```bash
npm i -g gitbash && gitbash --config
```

### Options

```bash
gitbash --help         # Show help
gitbash --version      # Show version
gitbash --init         # Print shell functions (see Shell integration)
gitbash --config       # Interactive configuration wizard
gitbash --config-local # Configure overrides for the current repository (committed)
gitbash --config-user  # Configure personal overrides for the current repository
```

### Dependencies

```bash
# Required
git >= 2.23, bash >= 3.2

# Optional (recommended)
brew install fzf        # Interactive menus and previews (fzf >= 0.36)
brew install git-delta  # Better diff highlighting
brew install bat        # File preview with syntax highlighting
```

### Shell integration

Add to your `.zshrc` or `.bashrc` to call the commands without the `gitbash` prefix:

```bash
eval "$(gitbash --init)"             # commit, switch, status, ...
eval "$(gitbash --init --prefix=gb-)" # gb-commit, gb-switch, ... (avoids shadowing e.g. /usr/bin/pr)
```

This defines small wrapper functions; every command still runs in its own bash process, so nothing else is added to your shell. Individual aliases work too, e.g. `alias commit="gitbash commit"`.

### Upgrading to 2.0

2.0 is a security and safety release. What changes for you:

- **Restart your shell** after upgrading, so `eval "$(gitbash --init)"` picks up the new wrapper functions.
- Config files are **read, not executed**: only plain `GITBASH_*="value"` lines are used, other lines are ignored with a warning. `GITBASH_MERGE_COMMAND` is ignored in a committed `.gitbashrc`.
- `status` no longer commits and pushes after staging. Use `Ctrl-O` to commit.
- `stale` toggles all/stale branches with `Ctrl-T` (was `Ctrl-A`).
- Protected branches (base branch and `GITBASH_PROTECTED_BRANCHES`) are never offered for deletion. `cleanup` and `switch` delete with `git branch -d` and ask again before force-deleting unmerged work.
- When your branch and the remote diverged, `commit -p`, `pr -p` and `update -p` ask whether to rebase, merge or abort instead of rebasing silently.
- fzf 0.36 or newer is required for the interactive menus.

## Commands

### branch

Interactive menu for branch operations (create/switch/update).

```bash
branch              # Interactive menu
branch -h           # Show help
branch --version    # Show version
```

### create

```bash
create [--feature|--bugfix|--hotfix|--release|-t] [--push|--no-push] [JIRA_LINK|ISSUE] [TITLE...]
```

Create a branch from the latest `origin/<base>` with optional Jira parsing, then push and track it (`GITBASH_CREATE_AUTO_PUSH`, `--no-push`).

**Branch Name Format:** `<type>/<custom-prefix>/<issue>-<title>` or `<type>/<custom-prefix>/<title>`

Issue keys like `PROJ-123`, `AB2-45` or `proj-7`, or a Jira URL. Titles are lower-cased, umlauts and accents transliterated (`Über` → `ueber`).

**Examples with custom prefix** (`GITBASH_CREATE_BRANCH_PREFIX="awesome-team"`):

With issue parsing enabled (default):

```bash
create PROJ-123 fix login bug           # → feature/awesome-team/PROJ-123-fix-login-bug
create fix bug                          # → feature/awesome-team/NOISSUE-fix-bug
create --hotfix PROJ-999 critical fix   # → hotfix/awesome-team/PROJ-999-critical-fix
create                                  # Interactive mode with Jira prompt
```

With issue parsing disabled (`GITBASH_CREATE_NO_ISSUE_PARSING="yes"`):

```bash
create fix login bug                    # → feature/awesome-team/fix-login-bug
create --hotfix enhance security        # → hotfix/awesome-team/enhance-security
create                                  # Interactive mode (no Jira prompt)
```

**Examples with empty prefix** (`GITBASH_CREATE_BRANCH_PREFIX=""`, default):

```bash
create PROJ-123 fix bug                 # → feature/PROJ-123-fix-bug
create fix bug                          # → feature/NOISSUE-fix-bug
create enhance login screen             # → feature/enhance-login-screen (parsing disabled)
```

### switch

```bash
switch [FILTER...]
```

Switch branches with fzf. Shows local branches (`merged:` = fully merged into the base branch), then remote branches without a local copy. Preview shows commit history. If exactly one branch name matches the filter, switches directly. After switching, offers to fast-forward a branch that is behind.

- `Del` deletes the selected local branch (asks first, default no; unmerged commits need a second confirmation)

```bash
switch              # Browse all branches
switch captcha      # Pre-filter for "captcha"
```

### commit

```bash
commit [-p] [-s] [-a] [-t] [-y] [--force-with-lease] [MESSAGE...] [-- MESSAGE...]
```

Commit with optional push.

- Only staged changes → commits them. Only unstaged/new files → stages everything (lists new files first).
- Both staged and unstaged → asks `[s]taged only` (default) or `[a]ll`.
- `-p` pushes; new branches get tracking. If the remote diverged, asks: rebase, merge or abort.
- `--amend` without a message keeps the old one; with `-p` it asks before `push --force-with-lease`.

```bash
commit fix bug           # Commit
commit -s fix bug        # Commit staged only
commit -p add feature    # Commit and push
commit -t add endpoint   # Conventional commit type menu (feat, fix, ...)
commit --amend           # Amend, keep message
```

### status

Interactive staging with fzf and diff previews.

- `Enter` stages the selected files (unstages fully staged ones)
- `Ctrl-R` discards changes (asks first)
- `Ctrl-O` commits the staged changes, then asks whether to push
- `ESC` exits

### pr

```bash
pr [-p|--push] [--print]
```

Open the pull request in the browser: the existing PR via the GitHub CLI when available, otherwise the create page (GitHub, GitHub Enterprise, GitLab, Bitbucket, Azure DevOps). Offers to commit local changes and to push a branch that is not on the remote yet. `-p` pushes first, `--print` prints the URL.

### update

```bash
update [-p|--push]
```

Merge the latest `origin/<base>` into the current branch. With local changes, asks to commit, stash (restored afterwards) or abort. Lists conflicts and opens the merge tool (`GITBASH_MERGE_COMMAND`). On the base branch itself, fast-forwards it.

### stale

```bash
stale [-a|--all] [-m|--my] [--age=N] [--json] [FILTER...]
```

List remote branches older than 3 months (oldest first). Multi-select with TAB, Enter deletes them from the remote after confirmation. Protected branches are never listed.

- `-a|--all` starts with all branches (not only stale ones); `Ctrl-T` toggles
- `-m|--my` pre-fills the filter with your git username
- `--age=N` sets the threshold in months (default: 3, or `GITBASH_STALE_MONTHS`)
- `--json` outputs JSON for scripting

### stashes

Interactive stash menu: create, apply, or delete stashes.

### stash

```bash
stash [NAME...]
```

Create named stash (includes untracked files).

### unstash

Apply stash with fzf picker. Drops it afterwards unless you say no.

### cleanstash

Delete stashes (multi-select with TAB).

### cleanup

```bash
cleanup [--dry-run] [--days=N] [-y|--yes] [--json]
```

Find and delete leftover local branches:

- **[MERGED]** - Changes are in the base branch (also squash merges). Pre-selected if the remote branch is gone or it is older than N days.
- **[STALE]** - No commits in 7+ days. Pre-selected only if everything is pushed.
- **[GONE]** - Remote branch deleted but changes not merged (not selected)
- **[RECENT]** - Recent activity (not selected)

Unpushed commits are shown per branch. Deletes with `git branch -d`; force-deleting unmerged work needs a second confirmation. Switches to the base branch first if the current branch is deleted. `--dry-run` lists and `--yes` deletes the pre-selected branches without the picker.

`--json` outputs non-interactive JSON for scripting:

```json
[
  {
    "last_change_timestamp": 1733123456,
    "author_email": "dev@example.com",
    "author_name": "Dev",
    "name": "feature/old",
    "last_change_relative": "2 weeks ago",
    "category": "merged",
    "preselected": true,
    "unpushed_commits": 0
  }
]
```

### commits

```bash
commits [COUNT]
```

List recent commits with option to revert. Multi-select with TAB; selected commits are reverted newest first.

```bash
commits        # Show last 20 commits
commits 50     # Show last 50 commits
```

## Configuration

gitbash reads `~/.gitbashrc`. Run `gitbash --config` to set it up interactively, or write it by hand:

```bash
# Branch prefix inserted between type and issue number (default: "")
GITBASH_CREATE_BRANCH_PREFIX=""

# Disable Jira issue number parsing in branch names: yes or no (default: "no")
GITBASH_CREATE_NO_ISSUE_PARSING="no"

# Fallback prefix when no issue number is provided (default: "NOISSUE")
GITBASH_CREATE_ISSUE_PARSING_FALLBACK="NOISSUE"

# Push new branches right after 'create': yes or no (default: "yes")
GITBASH_CREATE_AUTO_PUSH="yes"

# Merge tool invoked by 'update' on conflicts (default: "fork")
GITBASH_MERGE_COMMAND="fork"

# Theme for delta/bat: auto, dark or light (default: "auto")
GITBASH_THEME="auto"

# Stale thresholds: 'stale' in months, 'cleanup' in days (defaults: 3, 7)
GITBASH_STALE_MONTHS="3"
GITBASH_CLEANUP_DAYS="7"

# Branches never offered for deletion, space-separated globs
GITBASH_PROTECTED_BRANCHES="main master develop release/*"

# Base branch (default: detected from origin/HEAD, then main, then master)
GITBASH_BASE_BRANCH=""

# Remote name (default: "origin")
GITBASH_REMOTE="origin"
```

Config files are **read, never executed**. Only `GITBASH_*="value"` lines are used (double, single or no quotes, optional `export`, `# comments`). Values cannot contain `$`, backticks, backslashes or quotes; anything else is ignored with a warning.

#### Local Configuration

Run `gitbash --config-local` inside a repository to create a committed `.gitbashrc` with overrides for everyone working on it (e.g. a team branch prefix or different thresholds). For security, a committed `.gitbashrc` cannot set `GITBASH_MERGE_COMMAND`.

#### User Configuration

Run `gitbash --config-user` to create `.gitbashrc-user` for personal overrides in one repository. It is excluded from git via `.git/info/exclude`.

**Configuration priority (highest to lowest):**

1. `.gitbashrc-user` - Personal settings for this repository (not committed)
2. `.gitbashrc` - Repository settings (committed)
3. `~/.gitbashrc` - Global settings

## License

See [LICENSE](LICENSE) file for details.
