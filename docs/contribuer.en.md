# Contributing

## Setup

```bash
brew install bats-core shellcheck actionlint gitleaks   # or apt / winget equivalents
./install.sh   # repowarden hooks on this repository (it tests itself)
```

## Before each PR

```bash
shellcheck bin/* ci/*.sh hooks/pre-commit hooks/prepare-commit-msg hooks/commit-msg hooks/pre-push hooks/post-checkout hooks/post-merge hooks/lib/*.sh hooks/lang/*.sh install.sh
actionlint .github/workflows/*.yml
bats test/                      # unit and integration tests
test/e2e/run.sh python go       # real-world tests (languages whose tooling is installed)
```

The CI re-runs everything on Linux, macOS and Windows, plus one e2e job per language with its real tooling.

Touched tests also run under **bash 3.2** (macOS `/bin/bash` first in `PATH`). Without bash 3.2 on the machine (Linux, devzone container), the CI's macOS jobs cover it: watch them (`repowarden pr checks <n>`) and only call the work done once they are green. Optional, to try before the CI, bash 3.2 built locally (checked on Ubuntu 24.04, gcc 13; `bison` required, the shipped parser is outdated):

```bash
curl -fsSLO https://ftp.gnu.org/gnu/bash/bash-3.2.57.tar.gz && tar xzf bash-3.2.57.tar.gz && cd bash-3.2.57
./configure --build="$(uname -m)-unknown-linux-gnu" --without-bash-malloc \
  CFLAGS="-O2 -std=gnu89 -Wno-implicit-function-declaration -Wno-implicit-int -Wno-incompatible-pointer-types -Wno-int-conversion"
make && mkdir -p ~/bash32 && cp bash ~/bash32/
PATH="$HOME/bash32:$PATH" bats test/<file>.bats   # bats follows the bash in PATH
```

## Conventions

- **Branches**: `<type>/<topic>` (`feat/helm-unittest`, `fix/windows-paths`).
- **Commits**: [Conventional Commits](https://www.conventionalcommits.org). The type determines the published version: `fix` → patch, `feat` → minor, `!` → major.
- **Bash 3.2** (macOS): no associative arrays and no `mapfile`. In functions called per file, no subprocesses (`$(…)`): return the result in `REPLY`.
- **ASCII bats test names** (bats on Windows ignores others). In `languages.bats`, the name starts with a prefix covered by the Windows filters in `ci.yml` (`detection`, `format`, `pre-push`…): a test checks that none is missed.
- **Performance**: each process creation costs 20 to 50 ms on Windows. Read the config with `cfg_r` (no subshell), reuse `GIT_TOPLEVEL`, avoid `$(…)` in loops.
- A missing tool is **never blocking** on the developer machine (`warn` / `tool_missing`); the CI's strict mode makes it blocking.

## Adding a language or a tool

1. `hooks/lang/<name>.sh`: `register`, `<name>_format`, `<name>_test` (see `docs/technologies.md`).
2. `test/e2e/<name>/`: `project/` (clean), `bad/` (badly formatted), `break/` (broken tests), `keep/` (must not be modified), `e2e.env`.
3. Add `<name>` to the matrix in `.github/workflows/e2e.yml` with the installation of its tooling.
4. Update the table in `docs/technologies.md`.

## Branches and releases

- PRs target **`develop`** (default branch); a PR opened against `main` is retargeted automatically. Only urgent fixes (`hotfix/…`) may target `main`.
- On every merge into `develop`: a **pre-release** `vX.Y.Z-next.N` (npm `next`) and the **delivery PR** `develop` → `main` kept up to date (upcoming version, notes). Merging it, as a merge commit, publishes: `vX.Y.Z` tag, GitHub release (release notes), `v4`, npm `latest`, site. No file is written: the version is carried by the tag.
- An urgent fix (`hotfix/…`) merged into `main` flows back into `develop` on its own.
- Details: [Versions and releases, tag mode](releases.md#develop-main-flow-tag-mode-recommended).
