# Quick start

Three paths, depending on your use case. The fastest way to try it: **On my machine**.

=== "On my machine"

    All your repositories, without adding anything to the projects or their `package.json`:

    ```bash
    npm install -g repowarden     # 1. the package (yarn global add, pnpm add -g: same)
    repowarden install --global           # 2. enables the hooks: asks for the language, installs git cc
    repowarden                            # 3. checks: machine status and next step
    ```

    Step 2 is required: for security, the package runs nothing at install time (no `postinstall` script).

    Try it right away, in any repository:

    ```bash
    git switch -c feat/cart              # branch name checked
    git add . && git cc                  # commit assistant (type, scope, description…)
    git push -u origin feat/cart         # tests of the affected projects before sending
    repowarden code-mort                  # new dead code on the branch
    ```

    | Action | Command |
    |---|---|
    | Machine status, next step | `repowarden` (or `repowarden statut`) |
    | Every command | `repowarden --help` |
    | Check | `git config --global core.hooksPath` → `…/repowarden/hooks` |
    | Update | `npm update -g repowarden` (the hooks follow) |
    | Try the next version | `npm install -g repowarden@next` (back: `@latest`) |
    | Change language | `repowarden install --global --lang fr` |
    | A single repository | `cd my-project && repowarden install` |
    | GitHub repository bots (CI, releases, tickets, protection…) | `repowarden bots` (offered by `repowarden install` in a GitHub repository; `--sans-bots` to stop seeing it) |
    | Uninstall | `repowarden uninstall --global`, then `npm uninstall -g repowarden` ([full uninstall](desinstallation.md)) |

    `npx` is refused for the global installation: its temporary folder can be deleted at any time. With nvm, each Node version has its own global packages: run `repowarden install --global` again after switching versions.

    **Internal npm registry** (company, proxy): `npm install -g repowarden --registry <url>`, or `registry=<url>` in `~/.npmrc`; see [internal sources](industrialisation.md#8-internal-sources-closed-network-nexus-artifactory).

    **Without Node**: same result from a clone, updated with `git -C ~/repowarden pull` (the commands become `~/repowarden/install.sh`, `~/repowarden/bin/code-mort`…).

    ```bash
    git clone https://github.com/simdevWarden/repowarden.git ~/repowarden
    ~/repowarden/install.sh --global
    ```

=== "A team project"

    1. **Everyone** installs repowarden once on their machine ("On my machine" tab): `npm install -g repowarden`, then `repowarden install --global`.

    2. **The project**, on GitHub: `repowarden bots` (someone with admin rights) offers each bot (CI, releases, cleanup, tickets, GitHub App, protection, npm), shows what will be created or changed, then waits for confirmation. Nothing is done without consent, and an existing file is never overwritten. Otherwise, by hand, it adds the templates from [`templates/project/`](https://github.com/simdevWarden/repowarden/tree/main/templates/project):

        | File | Role |
        |---|---|
        | `.github/workflows/repowarden.yml` | GitHub CI: re-runs the checks on every PR, it is authoritative (add the `setup-*` steps for the project's tools) |
        | `.repowarden.conf` | shared settings, including `version`: minimum repowarden version expected on developer machines |
        | `.github/workflows/release.yml` | [automatic releases](releases.md) (optional) |
        | `gitlab-ci.yml` | for GitLab, to merge into `.gitlab-ci.yml` |

    3. **Make the CI required** to merge: `repowarden proteger` (see [In an organisation](industrialisation.md)).

    A machine whose repowarden is older than the project `version` is warned on every commit, with the update command. Without hooks, the CI re-runs every check anyway.

=== "An organisation"

    The [In an organisation guide](industrialisation.md) covers hosting repowarden, versions, automatic installation on developer machines (Maven, Gradle, npm) and GitHub / GitLab branch protection.

=== "Contributing to repowarden"

    ```bash
    git clone https://github.com/simdevWarden/repowarden.git && cd repowarden
    ./install.sh                         # repowarden checks itself
    bats test/                           # tests (bats-core), also run on push
    ```

    See [Contributing](contribuer.md).

## Prerequisites

| Item | Required | Notes |
|---|---|---|
| git + bash | yes | macOS, Linux, Windows via [Git for Windows](https://gitforwindows.org) |
| Tools for the languages used | depending on the projects | a missing tool is skipped on the developer machine |
| [gitleaks](https://github.com/gitleaks/gitleaks) | recommended | `brew install gitleaks` · `apt install gitleaks` · `winget install gitleaks` |
| [GitHub CLI (`gh`)](https://cli.github.com) | optional | GitHub tickets and repository management: `gh auth login -s workflow` (the `workflow` scope allows changing `.github/workflows/`) |
