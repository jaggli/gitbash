# gitbash

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
