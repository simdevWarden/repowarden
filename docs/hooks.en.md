# Hooks and rules

## The hooks

| Hook | Role |
|---|---|
| `post-checkout` | Warns as soon as you switch to a badly named branch (non-blocking) |
| `pre-commit` | Rejects badly named branches, blocks direct commits on protected branches (`main`/`master` by default), detects secrets, formats **only the staged content** (unstaged work is preserved) |
| `prepare-commit-msg` | Prefixes the message based on the branch: on `feat/bean`, `git commit -m "add X"` → `feat(bean): add X` |
| `commit-msg` | Enforces [Conventional Commits](https://www.conventionalcommits.org), 72 characters maximum |
| `pre-push` | Rejects badly named branches and direct pushes to protected branches (`protectedBranches`, initial creation allowed), and the **messages of the pushed commits** (same rule as CI, `git rebase -i` suggested to fix them); **lint** (shellcheck for shell scripts, actionlint for GitHub workflows) then builds and tests **the pushed commit**, only for the affected projects |
| `post-merge` | After a `git pull`: deletes merged local branches (regular or squash merge) whose remote branch has been deleted; never a branch containing unintegrated work |

One-off bypass: `git commit --no-verify`, `git push --no-verify` — the [CI](ci.md) re-runs the checks.

## Secrets at pre-commit

With [gitleaks](https://github.com/gitleaks/gitleaks) installed, the staged content is scanned before each commit. A secret found rejects the commit and tells **where** it is, **never showing its value**:

```text
✖ Secret detected: commit refused.
  config/app.ini:3 (github-pat)

What to do:
  1. Remove the value from the file (environment variable, ignored file), then commit again.
  2. File that must never be versioned: add it to .gitignore, then git rm --cached <file>.
  3. Key that may have leaked elsewhere (already pushed, shared): revoke it at its provider.
  False positive: add its fingerprint to .gitleaksignore:
    config/app.ini:github-pat:3
```

A failing gitleaks (invalid configuration, incompatible version) also rejects the commit, with its error message: detection was not done, and it is never presented as a leak. Without gitleaks, detection is skipped with the install command; the [CI](ci.md) `secrets` check runs it again. Disable for a repository: `git config repowarden.skip secrets`.

## Lint at pre-push

The `pre-push` hook runs linters on changed files **before** tests:

| Linter | Targeted files | Required tool |
|---|---|---|
| **shellcheck** | `*.sh`, `*.bash` and scripts without extension with shebang (`#!/bin/sh`, `#!/bin/bash`, `#!/usr/bin/env bash`…) | `shellcheck` |
| **actionlint** | `.github/workflows/*.yml`, `.github/workflows/*.yaml` | `actionlint` |

### shellcheck severity

Setting `repowarden.lintSeverity` (in `.repowarden.conf` or `git config`):

| Value | Behavior | Checks enabled |
|---|---|---|
| `error` | Blocks only on errors | Mandatory error level |
| `warning` (default) | Blocks on errors + warnings | Mandatory error + warning |
| `style` | Also blocks on style suggestions | All + optional (`-o all`) |
| `info` | Blocks on everything | All + optional (`-o all`) |

### Disable lint

- `repowarden.skip lint` (git config or `.repowarden.conf`): completely disables lint at push.
- Strict CI mode (`REPOWARDEN_WARN_FILE` set): missing tool = failure.

### Tool installation

If a linter is missing, a warning message shows the install command for the OS:
- macOS: `brew install shellcheck` / `brew install actionlint`
- Linux: `apt-get install shellcheck` / `go install github.com/rhysd/actionlint/cmd/actionlint@latest`
- Windows: `choco install shellcheck` / `scoop install actionlint`

## Commit messages

Format `<type>(<scope>): <description>`; `!` after the type for a breaking change (`feat!: …`).

| Type | Usage | Release |
|---|---|---|
| `feat` | new feature | minor version (1.**4**.0) |
| `fix` | bug fix | patch (1.4.**1**) |
| `perf` | performance | patch |
| `docs` | documentation | patch |
| `style`, `refactor`, `test`, `build`, `ci`, `chore`, `revert` | formatting, restructuring, tests, build, CI, maintenance, revert | none on their own |

**AI agents**: agent signatures (`Co-Authored-By: Claude …`, "🤖 Generated with …") are **removed** from the message, and a commit whose author or committer is an agent (`noreply@anthropic.com`, Copilot, Cursor, Devin) is **refused**: the history carries a person's identity. Automation bots (`github-actions`, repowarden App, Dependabot) are not affected. To allow agents: `git config repowarden.allowAgentSignatures true` (or in `.repowarden.conf`). To stop an agent **before** it changes a protected branch or bypasses the hooks: [AI agent guard](agents.md) (`repowarden agents init`).

A `!` (`feat!: …`) or a `BREAKING CHANGE:` footer produces a **major version**. See [automatic releases](industrialisation.md#2-versions-and-releases-automatic).

## Commit assistant: `git cc`

To write a compliant message without remembering the format, `git cc` guides you step by step (alias installed by `install.sh`), in the language chosen at installation:

```text
$ git cc
◆ repowarden · conventional commit
Enter = suggested value in [brackets] · Ctrl+C to cancel

◇ 1/5  Type of change
   1  ✨  feat      new feature
   2  🐛  fix       bug fix
   …
Number or name [feat]:                          ← suggested from the feat/cart branch

◇ 2/5  Scope (optional)
Scope ("-" for none) [cart]:

◇ 3/5  Breaking change?
Breaking? [y/N]:

◇ 4/5  Description
  Imperative mood, no initial capital or final period; 60 characters max.
feat(cart): add the cart

◇ 5/5  Details (optional)
> The customer keeps their items between two visits.
>
References (e.g. Closes #12; Enter for none): Closes #12

┌─ Message ───────────────────────────────────────────────
│ feat(cart): add the cart
│
│ The customer keeps their items between two visits.
│
│ Closes #12
└─────────────────────────────────────────────────────────
Commit? [Y/n]:
```

| Step | Required | Help |
|---|---|---|
| Type | yes | menu (number or name), suggested from the branch; nothing is suggested on a branch outside the convention (`wip/…`): the type must be chosen |
| Scope | no | suggested from the branch; an invalid scope is fixed and suggested ("doc test" → `doc-test`) |
| Breaking change | no | adds `!` and the `BREAKING CHANGE: …` footer, described right away (at least 10 characters); skipped on the repository's first commit |
| Description | yes | header length checked (72 characters); final period removed |
| Body | no | several lines: the why; an empty line (or only `;`, `.`) finishes it |
| References | no | example adapted to the platform: `Closes #12`, `!34` (GitLab), `PROJ-42` (Bitbucket) |

**On a protected branch** (`main`…), the commit would be refused: the assistant says so at step 2 and suggests a `<type>/<scope>` branch (Enter to create it, your changes follow; "n" to cancel). An incomplete answer is completed (`feat` → `feat/<scope>`), an approximate name fixed (`My Test` → `feat/my-test`).

**Robust input**: arrow keys and deletion in a terminal, stray keys ignored; an invalid yes/no answer is asked again; Ctrl+D cancels. If a hook refuses the commit, the message is kept (`git commit -F .git/repowarden-message` once fixed).

`git commit` options are passed through (`git cc --no-verify`…); `git cc --dry-run` shows the message without committing. Answers supplied by a script (one per line on standard input): `git cc --strict`, so that a refused answer stops everything instead of reading the next line as a new answer. Without `install.sh`: `git config --global alias.cc '!bash /path/to/repowarden/bin/commit'`.

**Without questions** (scripts, agents, CI): answers are passed as options, with the same checks, and any refused value stops everything without committing. An omitted type and scope are inferred from the branch, as with Enter; on a protected branch, no branch is created.

```bash
git cc -m "add the cart"                                      # on feat/cart → feat(cart): add the cart
git cc --type fix --scope - -m "fix the total" \
       --body "The total ignored the discount." --refs "Closes #12"
git cc --type feat --breaking "the total is in cents" -m "change the cart API"
```

| Option | Purpose |
|---|---|
| `-m`, `--message` | description (required without questions) |
| `--type` | type (name or menu number) |
| `--scope` | scope; `-` for none |
| `--breaking` | breaking change: `!` and `BREAKING CHANGE: <text>` footer |
| `--body` | body (several lines allowed) |
| `--refs` | references (`Closes #12`) |

Other options are passed to `git commit`; `--` ends the assistant's options.

## Branch naming

Format `<type>/<topic>` (topic in `a-z0-9._-`, `/` to subdivide): `feat/signup`, `fix/user/login`, `hotfix/db-timeout`.

- Warning on creation, rejected on commit and push, with the rename command to copy.
- Default exceptions: `main`, `master`, `develop`, `release/*` and bot branches (`release-please--*`, `dependabot/*`, `renovate/*`); `allowedBranches` setting.
- The type becomes the commit prefix and the topic its scope (omitted beyond 20 characters).
- Aliases: `feature/` → `feat`, `bugfix/` and `hotfix/` → `fix`.
- A message that is already compliant is never modified; merge, squash and amend are ignored.

!!! tip "Git has no hook on branch creation"
    The name is therefore checked on the first commit and on push. To enforce it on the server side, see the [server-side rules](ci.md#server-side-rules).
