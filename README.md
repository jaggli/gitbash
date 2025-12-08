# gitbash

Interactive git utilities for bash with fzf-powered menus.

![screenshot-status.png](./docs/screenshot-status.png)

## Installation

### Via npm

```bash
npm i -g gitbash && gitbash --config
```

### Options

```bash
gitbash --help      # Show help
gitbash --version   # Show version
gitbash --init      # Print shell init code
gitbash --config    # Interactive configuration wizard
```

### Dependencies

```bash
# Required
brew install fzf

# Optional (recommended)
brew install git-delta  # Better diff highlighting
brew install bat        # File preview with syntax highlighting
```

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
create [JIRA_LINK|ISSUE] [TITLE...]
```

Create feature branch with optional Jira parsing. Updates main first, pushes and tracks.

**Branch Name Format:** `<type>/<custom-prefix>/<issue>-<title>` or `<type>/<custom-prefix>/<title>`

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

With parsing enabled:
```bash
create PROJ-123 fix bug                 # → feature/PROJ-123-fix-bug
create fix bug                          # → feature/NOISSUE-fix-bug
```

With parsing disabled:
```bash
create enhance login screen             # → feature/enhance-login-screen
```

### switch

```bash
switch [FILTER...]
```

Switch branches with fzf. Shows local first, then remotes (deduped). Preview shows commit history.

```bash
switch              # Browse all branches
switch captcha      # Pre-filter for "captcha"
```

### commit

```bash
commit [MESSAGE] [-p|--push] [-s|--staged]
```

Commit with optional push. Smart staging: prompts if both staged/unstaged exist.

```bash
commit fix bug           # Commit all
commit -s fix bug        # Commit staged only
commit -p add feature    # Commit and push
```

### status

Interactive staging with fzf. Toggle files with Enter, ESC to exit. Shows diffs in preview.

### pr

```bash
pr [-p|--push]
```

Open PR in browser. `-p` pushes first.

### update

```bash
update [-p|--push]
```

Merge latest main/master into current branch. Opens merge tool on conflicts.

### stale

```bash
stale [-a|--all] [--age=N] [--json] [FILTER...]
```

List remote branches >3 months old (oldest first). Multi-select with TAB to delete.

- By default, pre-filters by your git username (from `git config user.name`)
- `-a|--all` shows all branches without username filter
- `--age=N` sets stale threshold in months (default: 3, or `GITBASH_STALE_MONTHS`)
- `Ctrl-A` toggles showing all branches (including recent ones)
- `--json` outputs JSON for scripting (same format as cleanup)

### stashes

Interactive stash menu: create, apply, or delete stashes.

### stash

```bash
stash [NAME...]
```

Create named stash (includes untracked files).

### unstash

Apply stash with fzf picker. Optionally drop after applying.

### cleanstash

Delete stashes (multi-select with TAB).

### cleanup

```bash
cleanup [--json]
```

Find and delete leftover local branches. Shows all local branches categorized:

- **[MERGED]** - Remote was deleted (pre-selected)
- **[STALE]** - No commits in 7+ days (pre-selected)
- **[RECENT]** - Recent activity (not selected)

Switches to main/master first if current branch is selected for deletion.

`--json` outputs non-interactive JSON for scripting:

```json
[
  {
    "last_change_timestamp": 1733123456,
    "author_email": "dev@example.com",
    "author_name": "Dev",
    "name": "feature/old",
    "last_change_relative": "2 weeks ago"
  }
]
```

### commits

```bash
commits [COUNT]
```

List recent commits with option to revert. Multi-select with TAB to revert multiple.

```bash
commits        # Show last 20 commits
commits 50     # Show last 50 commits
```

### Configuration

gitbash reads configuration from `~/.gitbashrc` if it exists. You can set the following variables:

```bash
# Branch prefix inserted between type and issue number (default: "")
# No trailing slash needed - it's added automatically
# Format: <type>/<prefix>/<issue>-<title> or <type>/<prefix>/<title>
# Examples: "awesome-team" or "" for no prefix
GITBASH_CREATE_BRANCH_PREFIX=""

# Merge tool command invoked by 'update' when conflicts occur (default: "fork")
GITBASH_MERGE_COMMAND="fork"

# Disable Jira issue number parsing in branch names: yes or no (default: "no")
GITBASH_CREATE_NO_ISSUE_PARSING="no"

# Fallback prefix when no issue number is provided (default: "NOISSUE")
# Only used when GITBASH_CREATE_NO_ISSUE_PARSING="no"
GITBASH_CREATE_ISSUE_PARSING_FALLBACK="NOISSUE"

# Theme for delta/bat diff highlighting: auto, dark, or light (default: "light")
GITBASH_THEME="light"

# Stale branch threshold in months for 'stale' command (default: 3)
GITBASH_STALE_MONTHS=3

# Cleanup threshold in days - branches merged more than this many days ago (default: 7)
GITBASH_CLEANUP_DAYS=7
```

You can create this file manually or use `gitbash --config` to configure interactively.

### Individual aliases

Instead of adding every command via `eval "$(gitbash --init)"` in `.zshrc` or `.bashrc`
direct usage with `gitbash [command]` is also possible. Or if desired, individual aliases
can be made.

```bash
alias branch="gitbash branch"
alias cleanstash="gitbash cleanstash"
alias cleanup="gitbash cleanup"
alias commit="gitbash commit"
alias commits="gitbash commits"
alias create="gitbash create"
alias pr="gitbash pr"
alias stale="gitbash stale"
alias stash="gitbash stash"
alias stashes="gitbash stashes"
alias status="gitbash status"
alias switch="gitbash switch"
alias unstash="gitbash unstash"
alias update="gitbash update"
```

## License

See [LICENSE](LICENSE) file for details.
