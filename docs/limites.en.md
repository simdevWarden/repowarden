# Limitations

- **Branch creation**: Git has no hook at that point; the name is checked on the first commit and on push. To enforce it server-side: [server-side rules](ci.md#server-side-rules).
- **Local hooks can be bypassed** (`--no-verify`) and must be installed on each developer machine: CI and branch protection are authoritative.
- **Local `core.hooksPath`** (husky…) takes precedence over the global installation: run `install.sh` in the repository or let the existing tool handle it.
- **[pre-commit](https://pre-commit.com) project** with the global installation: `pre-commit install` refuses ("Cowardly refusing to install hooks with `core.hooksPath` set") and the hint it gives disables repowarden everywhere. Install its hooks in `.git/hooks`, which repowarden runs on every commit before its own checks (a failing pre-commit hook blocks the commit):

    ```bash
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0= pre-commit install
    ```

    The git configuration is not changed: `core.hooksPath` is only hidden for this command. Before git 2.31: `git config --local core.hooksPath ""`, then `pre-commit install`, then `git config --local --unset core.hooksPath`. `repowarden statut` reports a `.pre-commit-config.yaml` whose hooks are not installed.
- **Overlap**: if formatting and unstaged changes touch the same lines, the commit is formatted but the working directory stays in its original state.
- **Unlisted language**: describe it in [the configuration](configuration.md) (`format`, `test`) or [add a language file](technologies.md#adding-a-language).
- **Standalone files** (outside a project): formatted, but not tested.
- **`pre-push` outside the current branch**: tests run in a temporary worktree, where only `node_modules` is linked.
- **First run** on Helm, Kubernetes or Terraform: schemas and providers are downloaded, then cached.
- **repowarden directory moved or renamed**: Git *silently* ignores a `core.hooksPath` that no longer exists, and the hooks stop running. Re-run `install.sh` (with `--global` if needed) from the new location; check with `git config --show-origin --get-all core.hooksPath` (a local repository setting overrides the global one).
