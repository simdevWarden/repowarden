# Configuration

Everything is optional: without configuration, repowarden detects the languages and applies the default rules.

## `.repowarden.conf` file (shared)

Versioned at the project root, in `git config` format, read **by the hooks and by the CI**: an exception agreed during review applies everywhere.

```ini
[repowarden]
    version = 3.1                       # minimum repowarden version expected on developer machines
    # Custom commands: replace automatic detection
    format = npm run lint:fix --        # receives the staged files as arguments
    test = make ci                      # run at the root; modified files on standard input
    # Settings
    skip = protect-branch python        # disabled steps, hooks or languages
    protectedBranches = main develop    # direct commit and push forbidden; default: main master
    allowedBranches = main develop release/*
    exclude = vendor/* generated/*      # paths neither formatted nor tested
    allowAgentSignatures = false        # AI agents (author, Co-Authored-By) refused; default false
    releaseUpdate = npm update -g my-tool     # "Update" command in the release notes
    # Organization bot (repowarden bot)
    bot = auto                          # auto (default): protection applied and migration PRs; pr: PRs only; off: ignored
    requiredChecks = repowarden,tests   # required checks set by the bot; default: the online ones
```


`version`: if repowarden is older on a machine, the hooks say so with the update command (`npm update -g repowarden`, or `git pull` for a clone). It is a warning only: the CI checks every PR at its own version.

## Integration branch flow (`develop`)

By default, everything starts from `main` and returns to it through a PR. For a flow with two long-lived branches, where work is integrated into `develop` and then delivered to `main`:

```ini
[repowarden]
    integrationBranch = develop     # enables the flow
    mainBranch = main               # default: main
    protectedBranches = main develop
    allowedBranches = main develop release/* release-please--* dependabot/* renovate/*
```

The CI then checks the target of each PR:

| PR branch                                       | Expected target      |
| ----------------------------------------------- | -------------------- |
| work (`feat/…`, `fix/…`), bots (`dependabot/…`) | `develop`            |
| `develop`                                       | `main`               |
| `release/…`, `hotfix/…`                         | `develop`            |

Only `develop` goes into `main`: everything, urgent fixes included, goes through its test pre-releases before production.

**`develop` branch without a declared flow**: if `develop` exists but `integrationBranch` is missing, repowarden would treat the project as "`main` only". The CI then refuses a work PR to `main`, and `repowarden statut` reports it: declare `integrationBranch = develop`, or delete `develop`.

A wrongly targeted PR is rejected, with the command to fix it (`gh pr edit --base develop`). With the action's `fix-pr: true` input, it is **retargeted automatically** (or closed if a PR from the same branch already targets the right branch), and a non-compliant title is replaced: by the compliant commit with the highest version impact (breaking, then `feat`, then `fix`/`perf`; "!" added if a `BREAKING CHANGE` footer exists), otherwise derived from the branch.

## Local settings (not shared)

Take precedence over `.repowarden.conf`:

```bash
git config repowarden.skip true                    # disables everything
git config repowarden.skip "pre-push"              # disables a hook
git config repowarden.skip "protect-branch,format" # disables steps
git config repowarden.skip "node"                  # disables a language
```

**Skip a step just once**, without changing the configuration: `git -c repowarden.skip=<value> <command>`.

```bash
git -c repowarden.skip=tests push                   # this push without the tests
git -c repowarden.skip=protect-branch commit -m "…" # this commit on a protected branch
```

Refusal messages give the way forward (create a branch, rename it…), never the command to disable the rule: skipping a step remains a deliberate choice, made once.

## What can be disabled (`skip`)

| Category            | Values                                                                                           |
| ------------------- | ------------------------------------------------------------------------------------------------ |
| Hooks               | `pre-commit`, `prepare-commit-msg`, `commit-msg`, `pre-push`, `post-checkout`, `post-merge`      |
| Steps               | `branch-name`, `protect-branch`, `secrets`, `format`, `tests`, `deadcode`, `prune-branches`                  |
| Languages and tools | `maven`, `gradle`, `node`, `python`, `go`, `helm`, `docker`… (file name in `hooks/lang/`)        |
| Everything          | `true`                                                                                           |

## Project-specific hooks

An executable script `.repowarden/<hook>` (or `.git/hooks/<hook>`) is also run, before the common checks. This is where the project's own commands go (lefthook is no longer supported since repowarden 4: a hook installed by lefthook in `.git/hooks` is ignored, with a warning).

## Output

All repowarden messages (hooks, CI, `git cc` assistant, installation) follow the same style: `✔` success in green, `✖` error in red, `⚠` warning in yellow, `ℹ` information in blue, `▶` step in progress in cyan, hints in dimmed grey.

Colours are displayed in a terminal and in the GitHub action logs. They are disabled by `NO_COLOR=1`, by `TERM=dumb` or when the output is redirected (file, pipe); `FORCE_COLOR=1` forces them.

## Message language

French or English, chosen **once at installation** (prompted, or `./install.sh --global --lang en`) and stored in `repowarden.lang`. Order of precedence:

| Where | Language used |
|---|---|
| Developer machine | `REPOWARDEN_LANG`, otherwise `repowarden.lang` (installation), otherwise `lang` from `.repowarden.conf`, otherwise the system language |
| CI | `REPOWARDEN_LANG`, otherwise `lang` from `.repowarden.conf` (team language), otherwise English |

## Platform (GitHub, GitLab, Bitbucket, Gitea)

repowarden recognises the platform and adapts its vocabulary (PR or MR) and its examples (`Closes #12`, `!34` on GitLab, `PROJ-42` on Bitbucket): `forge` setting, otherwise CI variables (GitHub Actions, GitLab CI, Bitbucket Pipelines, Gitea / Forgejo Actions), otherwise the URL of the `origin` remote. A self-hosted GitLab whose URL does not contain "gitlab" is declared as follows:

```ini
[repowarden]
    forge = gitlab        # github, gitlab, bitbucket, gitea
```

## Internal sources (proxy, Nexus, Artifactory)

Without direct Internet access, or to go through the company repositories: the projects' tools (Maven, Gradle, npm, pip, Go…) use their own configuration (`settings.xml`, `.npmrc`…), and repowarden can fetch its CI tools through a mirror (`REPOWARDEN_DOWNLOAD_MIRROR`), checksums verified. Details: [In an organisation, internal sources](industrialisation.md#8-internal-sources-closed-network-nexus-artifactory).
