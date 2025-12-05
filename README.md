# gitbash

Interactive git utilities for bash with fzf-powered menus.

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

### Shell Aliases

Add these aliases to your `.zshrc` or `.bashrc` for individual command access:

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

Or use the built-in shell integration, for all commands:

```bash
eval "$(gitbash --init)"
```

### Dependencies

```bash
# Required
brew install fzf

# Optional (recommended)
brew install git-delta  # Better diff highlighting
brew install bat        # File preview with syntax highlighting
```

### Configuration

gitbash reads configuration from `~/.gitbashrc` if it exists. You can set the following variables:

```bash
# Prefix for feature branches (default: "feature/")
GITBASH_FEATURE_BRANCH_PREFIX="feature/"

# Command for merging (default: "merge")
GITBASH_MERGE_COMMAND="merge"
```

You can create this file manually or use `gitbash --config` to configure interactively.

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

Create feature branch with Jira parsing. Updates main first, pushes and tracks.

```bash
create PROJ-123 fix login bug  # → feature/PROJ-123-fix-login-bug
create                          # Interactive mode
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
stale [-m|--my] [--json] [FILTER...]
```

List remote branches >3 months old (oldest first). Multi-select with TAB to delete.

- `Ctrl-A` toggles showing all branches
- `--my` filters by your git username
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

## License

See [LICENSE](LICENSE) file for details.
