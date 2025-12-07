# Contributing to gitbash

Thank you for your interest in contributing to gitbash! This document outlines the process and guidelines for contributing to this project.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature or bugfix branch (see Branch Naming below)
4. Make your changes
5. Add a changeset (see Changesets below)
6. Push your branch and create a Pull Request

## Branch Naming

All contributions **must** be made through feature or bugfix branches. Direct commits to `main` won't be merged.

### Branch naming convention:
- **Feature branches**: `feature/<issue-number>-<description>` or `feature/NOISSUE-<description>`
- **Bugfix branches**: `bugfix/<issue-number>-<description>` or `bugfix/NOISSUE-<description>`

Examples:
```bash
feature/42-add-rebase-command
feature/NOISSUE-improve-error-messages
bugfix/15-fix-stale-branch-filtering
bugfix/NOISSUE-fix-typo-in-help
```

You can use the built-in `gitbash create` command to create properly formatted branches:
```bash
./bin/gitbash create
```

## Pull Requests

All contributions must be submitted via Pull Request (PR):

1. **One feature/fix per PR** - Keep PRs focused and atomic
2. **Descriptive title** - Clearly describe what the PR does
3. **Description** - Explain the motivation and implementation details
4. **Reference issues** - Link to related issues if applicable
5. **Include a changeset** - See below for details

### PR Requirements:
- [ ] Branch follows naming convention (`feature/*` or `bugfix/*`)
- [ ] Changeset has been added
- [ ] Code works as intended
- [ ] No breaking changes (unless discussed and approved)

## Changesets

We use [Changesets](https://github.com/changesets/changesets) to manage versions and changelogs. **Every PR must include a changeset.**.

### How to add a changeset:

1. After making your changes, run:
   ```bash
   npm run changeset
   ```

2. You'll be prompted to select the change type:
   - **patch** - Bug fixes, small improvements (1.0.0 → 1.0.1)
   - **minor** - New features, non-breaking changes (1.0.0 → 1.1.0)
   - **major** - Breaking changes (1.0.0 → 2.0.0)

3. Write a clear, user-facing description of the change:
   ```
   Added --all option to stale command to show all branches by default
   ```

4. A changeset file will be created in `.changeset/` - commit this with your PR:
   ```bash
   ./bin/gitbash commit "feat: Add changeset for stale command enhancement"
   ```

### Example changeset workflow:

```bash
# 1. Create your feature branch
./bin/gitbash create
# Select "feature", enter "NOISSUE" or issue number, add description

# 2. Make your changes
vim commands/stale.sh

# 3. Add a changeset
npm run changeset
# Select "minor" (new feature)
# Enter: "Added --all option to stale command to start in all branches mode"

# 4. Commit everything
./bin/gitbash commit "feat: add --all option to stale command"

# 5. Push and create PR
./bin/gitbash pr -p
```

### What happens to changesets:

When your PR is merged:
1. The changeset file is included in the main branch
2. When ready for release, maintainers run `npm run version`
3. Changesets are consumed and version is bumped
4. CHANGELOG.md is automatically updated
5. Changes are published with `npm run release`

## Development Guidelines

### Testing your changes:
```bash
# Test the gitbash command directly
./bin/gitbash <command>

# Example: test the stale command
./bin/gitbash stale --all
```

### Code style:
- Follow existing bash script conventions
- Use shellcheck for linting when possible
- Keep functions focused and well-documented
- Include help text for new commands/options
- Keep the readme updated and as terse as possible

### Documentation:
- Update command help text (`-h, --help`) for new features
- Update README.md if adding new commands
- Add usage examples for new features

## Questions or Issues?

If you have questions or run into issues:
- Check existing issues and discussions
- Create a new issue for bugs or feature requests
- Reach out in your PR if you need guidance

Thank you for contributing! 🎉 You rock!
