# Why repowarden?

repowarden is not one more linter. The checks it applies already exist, often
better done, in specialised tools: commitlint for messages, gitleaks for
secrets, ruff or prettier for formatting, release-please for versions, GitHub
branch protection rules for the server side. **repowarden orchestrates them**
and adds what none of these tools does alone: an enforced
**ticket → design → PR → delivery** chain, including for AI agents.

This page also says when another tool is enough. That is the case as soon as
the need is limited to a single check.

## Who covers what

| Tool | What it covers | Per-project configuration | What is missing |
|---|---|---|---|
| **husky + commitlint** | Git hook orchestration; commit message format (commitlint). | `package.json`, `.husky/`, `commitlint.config.*` | Branch name, secrets, formatting, push-time tests, dead code, releases, tickets, agent guard: all to be written yourself in the hooks. |
| **pre-commit** | Multi-language hook framework; plugins for the message (`conventional-pre-commit`), secrets (gitleaks), formatting (ruff, prettier…), blocking commits on `main` (`no-commit-to-branch`), push-time tests (local hook). | `.pre-commit-config.yaml` | Branch naming, tickets, releases, agent guard; CI and server protection still have to be wired; hook environments are per repository. |
| **lefthook** | Fast, parallel execution of Git hooks, on the same events as native hooks. | `lefthook.yml` | No check provided: everything is a command to write (message, secrets, format, tests…). No tickets, no releases, no agents. |
| **gitleaks** | Secret detection in history, the index or a range of commits. | `.gitleaks.toml`, CI integration | Everything else: message, branch, format, tests, dead code, releases, tickets, agents. |
| **release-please** | Next version, changelog, tag and release from Conventional Commits. | `release-please-config.json`, `.release-please-manifest.json`, workflow | It **assumes** conventional messages but does not enforce them; no hook, no branch, secret, format or test check; no tickets, no agents. |
| **GitHub branch protection (rulesets)** | Server side: required PR, required checks, merge blocked when CI fails, no direct push, no force push or deletion on protected branches. | GitHub settings (rulesets), `CODEOWNERS` | Checks nothing itself: CI, hooks and checks are still needed. No local feedback, no branch naming, no tickets, no guard before an agent acts. |
| **Danger** | PR review rules in CI: title and description, labels, changelog, ticket reference, automated comments. | `Dangerfile` | Git hooks, secrets, formatting, push-time tests, releases; the agent guard. Danger observes the PR, it does not prevent work upstream. |
| **repowarden** | The whole chain: message, branch name, protected branch, secrets, non-ignored `.env` file, formatting, push-time tests, new dead code, functions without a comment, releases, tickets, AI agent guard; the same rules on the machine, in CI and on the server. | `.repowarden.conf`, `repowarden.yml`, `release.yml`, `tickets.yml`, `nettoyage.yml` workflows | It replaces neither linters nor formatters: it calls them. Tickets and releases are GitHub-oriented; the agent guard only acts when the agent is wired; local hooks can still be bypassed (`--no-verify`), CI is authoritative. |

## When another tool is enough

- **Only message format**: commitlint (or `conventional-pre-commit`). No need
  for tickets, releases or agents for that.
- **Only releases**: release-please, with a workflow and its two JSON files.
- **Only server protection**: GitHub rulesets. They block merge and direct push
  without installing anything on machines.
- **Only secret detection**: gitleaks, in a pre-commit hook and in CI. That is
  in fact what repowarden calls.
- **A single language, few rules**: pre-commit with three or four plugins
  covers the message, secrets, format and push-time tests. repowarden's added
  value starts beyond that: branch naming, tickets, unified
  machine/CI/server, agents.
- **No tickets, no AI agents, a team that knows its tools**: the difference
  shrinks to orchestration. If pre-commit, release-please, gitleaks, Danger and
  rulesets already do the job, repowarden mostly replaces glue; the migration
  cost is not always worth it.

## What is specific to repowarden

1. **The enforced chain, not just checks.** A validated ticket, a written
   design, a `type/<n>-subject` branch, a PR that references the ticket, a
   delivery that closes the ticket: every link is checked, and CI rejects the
   PR that misses one. See [Tickets](tickets.md) and
   [Human approval](validation.md).
2. **The AI agent guard.** Claude Code and opencode are stopped **before** the
   action: modifying a protected branch, working outside a ticket, `git commit`
   without `repowarden cc`, `--no-verify`, `git add .`, force push. Hooks only
   see the agent at commit time; CI only at the PR. See
   [AI agents](agents.md).
3. **Orchestration of existing tools.** repowarden calls gitleaks, actionlint,
   ruff, MegaLinter, the project's formatters and tests; it does not rewrite a
   linter. A missing tool warns on the machine and becomes blocking in strict
   CI ([CI](ci.md)).
4. **The same rules at all three levels.** One `.repowarden.conf` for the
   machine and CI, server protection for what must not be bypassed. See
   [In an organisation](industrialisation.md).
5. **Releases without a token.** The GitHub App publishes the pre-release,
   keeps the delivery PR up to date and merges it when the checks are green,
   with human approval if the project requires it
   ([Versions and releases](releases.md)). release-please does versions;
   repowarden adds delivery and ticket tracking.

## The evidence, numbers in hand

The measurement is reproducible: [`ci/preuve.sh`](https://github.com/simdevWarden/repowarden/blob/develop/ci/preuve.sh)
starts from [repowarden-demo](https://github.com/simdevWarden/repowarden-demo/tree/83b6099c935a24b5aec56645c7a28d71dc80253b)
(commit `83b6099`, 17 October 2026) and builds two copies of the same Python
project:

- **classical assembly**: pre-commit (`conventional-pre-commit`, gitleaks,
  ruff, `no-commit-to-branch`, pytest in `pre-push`), release-please and a CI
  workflow;
- **repowarden**: the `.repowarden.conf` and the published template workflows
  (`repowarden.yml`, `release.yml`, `tickets.yml`, `nettoyage.yml`).

The tools are installed in a temporary directory, never globally.
Measurement made on **22 October 2026** on **Darwin arm64** (macOS), with
**pre-commit 4.7.0**, **repowarden 4.11.1**, **ruff 0.16.10**,
**gitleaks 8.30.1**, **Python 3.14.6**, **Node 26.9.0**; installation times are
the median of 3 runs, with a package cache specific to each run.

### Per-project configuration

| Assembly | Files | Lines | Useful lines (excluding blanks and comments) |
|---|---|---|---|
| Classical assembly | 5 | 70 | 69 |
| repowarden | 5 | 181 | 108 |

repowarden requires **more lines**: its `release`, `tickets` and `nettoyage`
workflows have no equivalent in the classical assembly, and the templates are
commented. At strictly equal scope (message, secrets, format, protected branch,
tests), the gap shrinks.

### Machine installation time

| Assembly | Median (s) | Versions |
|---|---|---|
| pre-commit + wiring one repository | 10.5 | pre-commit 4.7.0 |
| repowarden (npm) + global hooks | 1.3 | repowarden 4.11.1 |

The classical time covers creating a fresh Python environment, installing
pre-commit and wiring **one** repository (`pre-commit install`); repowarden
installs the npm package and enables the hooks for **every** repository. The
network moves both figures by a few seconds. On a machine where Python and
pre-commit are already installed, the incremental cost per repository is
lower; the gap mostly measures the initial setup.

### The same set of faulty commits

Each scenario is replayed on a fresh copy. "Blocked" = the commit or push
fails; "warned" = it goes through with a warning; "passed" = nothing reports
it.

| Scenario | Classical assembly | repowarden |
|---|---|---|
| Non-conforming message | blocked | blocked |
| Direct commit on `main` | blocked | blocked |
| Wrong branch name | passed | blocked |
| Secret in a staged file | blocked | blocked |
| `.env` neither tracked nor ignored | passed | warned |
| Badly formatted file | blocked (fix to re-stage) | passed (fixed) |
| Broken test on push | blocked | blocked |
| Invalid message discovered on push | passed | blocked |
| Function added without a comment | passed | warned |
| Force push requested by an agent | passed (no guard) | blocked |

### How to read these results

- **What both do equally well**: conventional message, secret, blocking commits
  on `main`, broken test on push. No surprise: repowarden calls the same tools,
  or applies the same rule.
- **Branch name** is not checked by `no-commit-to-branch`, which only protects
  the named branches; a script or repowarden is needed.
- **A non-ignored `.env`** passes silently in the classical assembly.
  repowarden warns without blocking: the file is neither tracked nor read, but
  a `git add .` would publish it.
- **Formatting**: ruff fixes in both cases. pre-commit stops to ask you to
  re-stage; repowarden re-stages the fixed content and the commit goes through
  in one go.
- **A message created outside the hooks** (another tool, rebase, `--no-verify`)
  is seen by repowarden at push time; the classical assembly never looks at it
  again.
- **A function without a comment** is a warning specific to repowarden.
- **Force push**: GitHub rulesets block force push on a **protected** branch,
  on the server side. The scenario uses a work branch; only repowarden refuses
  the command before it leaves.
- **The classical secret check depends on one configuration line**:
  `gitleaks-system` from the gitleaks repository lacks
  `pass_filenames: false`. Without it, pre-commit passes file names to gitleaks,
  which exits 0 without scanning anything. The measurement adds the line; a
  good example of the fragility of an assembly made of separate parts.

### Limitations of the measurement

- One project only, in Python, on macOS arm64. Times and tools change with the
  language, the OS and the network.
- The classical assembly is **minimal and correctly configured**, not
  deliberately bad. A team can add Danger, a ticket bot and naming rules:
  coverage gets closer, at the price of more glue.
- Server rules (rulesets) are not replayed: they only apply to a real GitHub
  repository. The classical column therefore does not include them.
- The offline test [`test/preuve.bats`](https://github.com/simdevWarden/repowarden/blob/develop/test/preuve.bats)
  checks the repowarden column with the repository's hooks, without network; it
  does not replay the classical assembly.

To redo the measurement (network required):

```bash
ci/preuve.sh
```

The script prints the tables above in Markdown. `ci/preuve.sh --liste` lists
the scenarios; `ci/preuve.sh --scenario <id>` replays one of them, offline,
with the repository's hooks.
