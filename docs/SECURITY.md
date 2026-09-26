# Security Policy

## Supported Versions

The following versions of this project are currently receiving security updates:

| Version | Supported |
|--------|-----------|
| 3.x.x  | ✅        |
| < 3.0  | ❌        |

Security fixes are only applied to the latest minor/patch release of the **3.x.x** series. Older versions must be upgraded to receive patches.

Versions before 2.0 executed repository `.gitbashrc` files as shell code, so opening a cloned repository with a malicious `.gitbashrc` could run arbitrary commands. Upgrade to 2.0 or later.

---

## Trust Model

- Configuration files (`~/.gitbashrc`, a repository's `.gitbashrc` and `.gitbashrc-user`) are **parsed, never executed**. Only plain `GITBASH_*="value"` lines from a fixed list of settings are read; values containing `$`, backticks, backslashes or quotes are rejected.
- A repository's committed `.gitbashrc` is treated as untrusted: it cannot set `GITBASH_MERGE_COMMAND` (the only setting that names a program to run). That setting is only read from `~/.gitbashrc` and `.gitbashrc-user`.
- Settings that reach git as arguments are validated: `GITBASH_BASE_BRANCH` (and a base branch taken from the remote's `HEAD`) must be a valid branch name that does not start with `-`, and `GITBASH_REMOTE` must not start with `-`. Before 3.0.0, a committed `.gitbashrc` could set `GITBASH_BASE_BRANCH="--output=<file>"` and make `switch` or `cleanup` overwrite that file.
- `gitbash --init` prints wrapper functions that call the installed `gitbash` binary; command code is not sourced into your shell.
- `pr` and `repo` never pass credentials from the remote URL to the browser.

---

## Releases

- Releases are staged only by the Release workflow in GitHub Actions, with npm trusted publishing (OIDC, no long-lived npm token) and [provenance](https://docs.npmjs.com/generating-provenance-statements). A version goes live only after a maintainer approves it with 2FA ([staged publishing](https://docs.npmjs.com/staged-publishing/)); neither the workflow nor a leaked GitHub token can publish on its own. Check an installed copy with `npm audit signatures`.
- The npm package is published before the GitHub release, which `gitbash --update` and the install script use.
- Third-party actions are pinned to commit SHAs and kept up to date by Dependabot; each workflow job gets only the permissions it needs.

---

## Reporting a Vulnerability

We take security vulnerabilities seriously and appreciate your efforts to responsibly disclose them.

### How to Report

- **Email:** `matthias.jaeggli@gmail.com`
- **Do not** open a public GitHub issue for security concerns.

### Response Expectations

- We will acknowledge your report **within 48 hours**.
- You will receive progress updates **at least weekly** until the issue is resolved.
- If additional information is needed, we will contact you directly.

### After You Report

After we receive your report:

1. We assess and validate the vulnerability.
2. If confirmed, we classify its severity and begin developing a fix.
3. We work with you on a responsible disclosure timeline.
4. A patched release is published along with a security advisory.
5. If the issue is not accepted, we will explain why.

### Responsible Disclosure

To protect users, please avoid public disclosure until:

- A fix has been released, **or**
- 30 days have passed since we acknowledged the report (unless otherwise agreed).

---

## Preferred Report Format

When reporting, please include:

- A description of the vulnerability.
- Steps to reproduce or a proof-of-concept.
- Expected vs. actual behavior.
- Affected versions.
- Impact and severity (if known).
- Optional: suggested remediation ideas.

---

Thank you for helping improve the security of this project.
