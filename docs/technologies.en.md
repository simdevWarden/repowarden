# Supported technologies

Detected automatically; each one is **tested in CI on a real project** with its tooling (formatting on commit, CI check, tests passing then broken).

| Area | Technologies |
|---|---|
| **Java / JVM** | Maven, Gradle (Java, Kotlin, Groovy) — Spring Boot, Quarkus, Android |
| **JavaScript / TypeScript** | npm, pnpm, yarn, bun, Deno — React, Next.js, Vue, Angular, Svelte, Nest |
| **Python** | pip, uv, poetry, pipenv — Django, FastAPI, Flask, scripts |
| **Other languages** | Go · Rust · PHP (Laravel, Symfony) · Ruby (Rails) · .NET (C#, F#, ASP.NET) · Dart / Flutter · Swift · Elixir (Phoenix) · C / C++ / Objective-C (CMake, Meson) · Shell |
| **Infrastructure** | Terraform / OpenTofu · Packer · Ansible · Helm · Kubernetes (kustomize) · Docker (Dockerfile, Compose) · GitHub Actions |
| **No recognized language** | `Makefile`, `justfile`, `Taskfile` — or any command via [the configuration](configuration.md) |
| **Hosting** | GitHub, GitLab, Bitbucket, Gitea, Git server |
| **CI** | GitHub Actions (action), GitLab CI (template) |
| **Operating systems** | Linux, macOS, Windows (Git Bash) |
| **Projects** | standalone script, single project, monorepo, multi-module |

## Detection

**Formatting (pre-commit)** — each staged file is handled according to:

1. the **nearest project**, walking up its directories (`backend/pom.xml`, `apps/web/package.json`…);
2. otherwise, its **extension** (standalone script: `deploy.sh`, `outil.py`), with the tool installed on the developer machine.

**Tests (pre-push and CI)** — only the **affected projects** are tested; a non-code file (README) counts for its project. With no recognized language: `test` target of a `Makefile`, `justfile` or `Taskfile`.

## Details by technology

| Language / tool | Detected by | Formatting | Tests / validation |
|---|---|---|---|
| Java — Maven | `pom.xml` ¹ | Spotless if configured (staged files) | `mvnw verify` |
| Java / Kotlin — Gradle | `settings.gradle`, `build.gradle(.kts)` ¹ | Spotless if configured (staged files) | `gradlew check` |
| JavaScript / TypeScript | `package.json` ² | prettier (from the project, otherwise global) | `npm` / `pnpm` / `yarn` / `bun` `test` (depending on the lockfile) |
| Deno | `deno.json` | `deno fmt` | `deno test` |
| Python | `pyproject.toml`, `requirements.txt`, `setup.py`, `Pipfile`, `manage.py` ² | ruff, otherwise black (project's version first) | pytest via uv / poetry / pipenv / `.venv` · `manage.py test` (Django) |
| Go | `go.mod` ² | gofmt | `go test ./...` |
| Rust | `Cargo.toml` ¹ ² | rustfmt (staged files) | `cargo test` |
| PHP | `composer.json` | pint, otherwise php-cs-fixer | `composer test` · `artisan test` · pest · phpunit |
| Ruby | `Gemfile` | rubocop -a / standardrb (if in the Gemfile) | `rails test` · rspec · `rake test` |
| .NET | `*.sln`, `*.csproj`… ¹ | `dotnet format` | `dotnet test` |
| Dart / Flutter | `pubspec.yaml` ² | `dart format` | `flutter test` / `dart test` |
| Swift | `Package.swift` ² | swift-format / SwiftFormat **if a config exists** | `swift test` |
| Elixir | `mix.exs` | `mix format` | `mix test` |
| C / C++ / Objective-C | `CMakeLists.txt`, `meson.build` ¹ ² | clang-format **if `.clang-format`** | rebuild + ctest / meson test |
| Shell | — ² | shfmt (`.editorconfig`, otherwise 4 spaces) | — |
| Terraform / OpenTofu | `*.tf` ² | `terraform fmt` / `tofu fmt` | `init -backend=false` + `validate` · tflint |
| Packer | `*.pkr.hcl` ² | `packer fmt` | `packer validate -syntax-only` |
| Ansible | `ansible.cfg`, `galaxy.yml`, `requirements.yml` | YAML reformatting (`ansible-lint`) | `ansible-lint` |
| Helm | `Chart.yaml` | **none**: Go templates, a YAML formatter would break them | `helm lint` · `helm template` + kubeconform · `helm unittest` |
| Kubernetes (kustomize) | `kustomization.yaml` | prettier | `kubectl kustomize` + kubeconform |
| Docker | `Dockerfile`, `Containerfile`, `compose.yaml` | — | hadolint · `docker compose config` |
| GitHub Actions | `.github/workflows` | — | actionlint |
| Other | `Makefile`, `justfile`, `Taskfile.yml` | — | `make test` · `just test` · `task test` |

¹ multi-module: build from the topmost parent project. ² also formats standalone files, outside any project.

!!! note "Infrastructure"
    For infrastructure, the "tests" step is a **validation** (lint, rendering, schemas): nothing is deployed. Kubernetes schemas and Terraform providers are cached (`~/.cache/repowarden`).

!!! note "Helm: dependency repositories"
    Before `helm dependency build`, the `https://` or `http://` repositories listed in the `dependencies:` of `Chart.yaml` are added (`helm repo add`) for the duration of the check, in a temporary configuration and cache deleted afterwards: the user's helm configuration is never modified. An unreachable repository fails the check. `oci://` and `file://` dependencies are not affected. Limit: if a chart mixes an HTTP repository and an `@alias` dependency (a repository the user already added), the check does not resolve the alias.

**Missing tool**: skipped on the developer machine (warning in a project, silent for a standalone file); blocking in CI with [strict mode](ci.md).

**Tool versions**: the project's own versions take priority (`node_modules`, `.venv` / uv, `vendor/bin`, `bundle exec`, Maven / Gradle wrapper, versioned Spotless plugin), so that everyone formats identically.

**Linters**: delegated to [MegaLinter](https://megalinter.io) (a [CI](ci.md#megalinter) option).

## Adding a language

Create `hooks/lang/<nom>.sh`:

```bash
register elm "elm.json" '\.elm$' standalone   # name, markers, extension regex, options
elm_format() { elm-format --yes "$@"; }       # files relative to the project
elm_test()   { elm-test; }                    # run in the project directory
```

Options: `standalone` (formats outside a project), `outermost` (multi-module), `fallback` (tests only if nothing else). See [Contributing](contribuer.md) for the example project and the CI.
