# CI: GitHub and GitLab

The CI re-runs all the hook checks on each PR / MR: **it is the authoritative source** (local hooks can be bypassed with `--no-verify`).

## What is checked

| Check | Fails if |
|---|---|
| `commits` | a message is not Conventional Commits, exceeds 72 characters, or is an unsquashed `fixup!`/`squash!`; non-compliant **PR title** (it becomes the commit message on squash merge); a commit whose **author or committer is an AI agent**, or an **agent signature** (`Co-Authored-By: Claude …`, "Generated with …") in a message or in the PR description (`allowAgentSignatures` setting) |
| `branch` | the branch name does not follow `<type>/<topic>` (outside the exceptions) |
| `secrets` | gitleaks finds a secret in the branch's commits |
| `format` | a modified file is not formatted (the formatter is run, nothing is committed) |
| `tests` | the tests of an affected project fail (monorepo: only the modified projects) |

Errors appear as annotations on GitHub and in the job log on GitLab, with the command to fix them.

## GitHub Actions

```yaml title=".github/workflows/repowarden.yml"
name: repowarden
on:
  pull_request:
    types: [opened, synchronize, reopened, edited] # edited: PR title re-checked
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  repowarden:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      # Project tools (formatting, tests), e.g.:
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install ruff pytest
      - uses: simdevWarden/repowarden@v4
        with:
          strict: true
```

| Input | Default | Role |
|---|---|---|
| `checks` | `commits branch secrets format tests deadcode comments` | checks to run |
| `strict` | `false` | a missing formatting / test tool causes a failure |
| `megalinter` | `false` | also runs MegaLinter |
| `fix-pr` | `false` | on a PR: retargets a wrongly targeted PR (`integrationBranch` flow, duplicate closed) and replaces a non-compliant title, then checks with the corrected values; requires `permissions: pull-requests: write` |
| `gitleaks-version` | `8.30.1` | installed version (SHA-256 checksum verified) |
| `actionlint-version` | `1.7.12` | installed version used to check the workflows |

## GitLab CI

```yaml title=".gitlab-ci.yml"
include:
  - project: outils/repowarden                # repowarden hosted on your GitLab
    ref: v4 # latest 4.x (vX.Y.Z to pin)
    file: templates/gitlab/repowarden.gitlab-ci.yml

repowarden:
  image: python:3.12                         # image with bash, git, curl and the project's tools
  variables:
    REPOWARDEN_STRICT: "true"
  before_script:
    - pip install ruff pytest
```

Variables: `REPOWARDEN_CHECKS`, `REPOWARDEN_STRICT`, `REPOWARDEN_MEGALINTER`, `REPOWARDEN_URL`, `REPOWARDEN_REF`, `GITLEAKS_VERSION`, `GITLEAKS_SHA256`, `REPOWARDEN_DOWNLOAD_MIRROR` ([internal sources](industrialisation.md#8-internal-sources-closed-network-nexus-artifactory)).

## Strict mode

On the developer machine, a missing tool is skipped. In CI with `strict`, it makes the check **fail**: the CI image must contain the project's tooling. repowarden installs gitleaks and actionlint itself (pinned versions, verified checksums).

## MegaLinter

Linters (ESLint, Checkstyle, golangci-lint…) are delegated to [MegaLinter](https://megalinter.io) rather than reimplemented: `megalinter: true` (GitHub) or `REPOWARDEN_MEGALINTER: "true"` (GitLab). Only modified files are analysed; configuration lives in the project's `.mega-linter.yml`.

## Server-side rules

To make the rules **impossible to bypass**:

| Host | Where | Availability |
|---|---|---|
| GitHub | *Settings → Rules → Rulesets*: require the `repowarden` check, block force pushes; "Restrict branch names", "Restrict commit metadata" | free on public repositories, Pro / Team on private repositories |
| GitLab | *Protected branches*, *Pipelines must succeed*; *Push rules* (Premium) | depending on plan |
| Bitbucket | *Branch restrictions* | depending on plan |

Regular expressions to copy:

```text
# Branch name
^((feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|feature|bugfix|hotfix)/[a-z0-9._-]+(/[a-z0-9._-]+)*|main|master|develop|release/.+)$

# Commit message
^((feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._-]+\))?!?: .+|Merge .+|Revert .+)
```
