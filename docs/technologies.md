# Technologies prises en charge

Détectées automatiquement ; chacune est **vérifiée en CI sur un vrai projet** avec son outillage (formatage au commit, vérification CI, tests au vert puis cassés).

| Domaine | Technologies |
|---|---|
| **Java / JVM** | Maven, Gradle (Java, Kotlin, Groovy) — Spring Boot, Quarkus, Android |
| **JavaScript / TypeScript** | npm, pnpm, yarn, bun, Deno — React, Next.js, Vue, Angular, Svelte, Nest |
| **Python** | pip, uv, poetry, pipenv — Django, FastAPI, Flask, scripts |
| **Autres langages** | Go · Rust · PHP (Laravel, Symfony) · Ruby (Rails) · .NET (C#, F#, ASP.NET) · Dart / Flutter · Swift · Elixir (Phoenix) · C / C++ / Objective-C (CMake, Meson) · Shell |
| **Infrastructure** | Terraform / OpenTofu · Packer · Ansible · Helm · Kubernetes (kustomize) · Docker (Dockerfile, Compose) · GitHub Actions |
| **Sans langage reconnu** | `Makefile`, `justfile`, `Taskfile` — ou toute commande via [la configuration](configuration.md) |
| **Hébergement** | GitHub, GitLab, Bitbucket, Gitea, serveur Git |
| **CI** | GitHub Actions (action), GitLab CI (template) |
| **Systèmes** | Linux, macOS, Windows (Git Bash) |
| **Projets** | script isolé, projet unique, monorepo, multi-module |

## Détection

**Formatage (pre-commit)** — chaque fichier stagé est traité selon :

1. le **projet le plus proche** en remontant ses dossiers (`backend/pom.xml`, `apps/web/package.json`…) ;
2. sinon, son **extension** (script isolé : `deploy.sh`, `outil.py`), avec l'outil installé sur le poste.

**Tests (pre-push et CI)** — seuls les **projets touchés** sont testés ; un fichier non-code (README) compte pour son projet. Sans langage reconnu : cible `test` d'un `Makefile`, `justfile` ou `Taskfile`.

## Détail par technologie

| Langage / outil | Détecté par | Formatage | Tests / validation |
|---|---|---|---|
| Java — Maven | `pom.xml` ¹ | Spotless si configuré (fichiers stagés) | `mvnw verify` |
| Java / Kotlin — Gradle | `settings.gradle`, `build.gradle(.kts)` ¹ | Spotless si configuré (fichiers stagés) | `gradlew check` |
| JavaScript / TypeScript | `package.json` ² | prettier (du projet, sinon global) | `npm` / `pnpm` / `yarn` / `bun` `test` (selon le lockfile) |
| Deno | `deno.json` | `deno fmt` | `deno test` |
| Python | `pyproject.toml`, `requirements.txt`, `setup.py`, `Pipfile`, `manage.py` ² | ruff, sinon black (du projet en priorité) | pytest via uv / poetry / pipenv / `.venv` · `manage.py test` (Django) |
| Go | `go.mod` ² | gofmt | `go test ./...` |
| Rust | `Cargo.toml` ¹ ² | rustfmt (fichiers stagés) | `cargo test` |
| PHP | `composer.json` | pint, sinon php-cs-fixer | `composer test` · `artisan test` · pest · phpunit |
| Ruby | `Gemfile` | rubocop -a / standardrb (si dans le Gemfile) | `rails test` · rspec · `rake test` |
| .NET | `*.sln`, `*.csproj`… ¹ | `dotnet format` | `dotnet test` |
| Dart / Flutter | `pubspec.yaml` ² | `dart format` | `flutter test` / `dart test` |
| Swift | `Package.swift` ² | swift-format / SwiftFormat **si une config existe** | `swift test` |
| Elixir | `mix.exs` | `mix format` | `mix test` |
| C / C++ / Objective-C | `CMakeLists.txt`, `meson.build` ¹ ² | clang-format **si `.clang-format`** | recompilation + ctest / meson test |
| Shell | — ² | shfmt (`.editorconfig`, sinon 4 espaces) | — |
| Terraform / OpenTofu | `*.tf` ² | `terraform fmt` / `tofu fmt` | `init -backend=false` + `validate` · tflint |
| Packer | `*.pkr.hcl` ² | `packer fmt` | `packer validate -syntax-only` |
| Ansible | `ansible.cfg`, `galaxy.yml`, `requirements.yml` | reformatage YAML (`ansible-lint`) | `ansible-lint` |
| Helm | `Chart.yaml` | **aucun** : templates Go, un formateur YAML les casserait | `helm lint` · `helm template` + kubeconform · `helm unittest` |
| Kubernetes (kustomize) | `kustomization.yaml` | prettier | `kubectl kustomize` + kubeconform |
| Docker | `Dockerfile`, `Containerfile`, `compose.yaml` | — | hadolint · `docker compose config` |
| GitHub Actions | `.github/workflows` | — | actionlint |
| Autre | `Makefile`, `justfile`, `Taskfile.yml` | — | `make test` · `just test` · `task test` |

¹ multi-module : build depuis le projet parent le plus haut. ² formate aussi les fichiers isolés, hors de tout projet.

!!! note "Infrastructure"
    Pour l'infrastructure, l'étape « tests » est une **validation** (lint, rendu, schémas) : rien n'est déployé. Schémas Kubernetes et providers Terraform sont mis en cache (`~/.cache/repowarden`).

!!! note "Helm : dépôts des dépendances"
    Avant `helm dependency build`, les dépôts `https://` ou `http://` listés dans les `dependencies:` de `Chart.yaml` sont ajoutés (`helm repo add`) le temps du contrôle, dans une configuration et un cache temporaires supprimés ensuite : la configuration helm de l'utilisateur n'est pas modifiée. Un dépôt injoignable fait échouer le contrôle. Les dépendances `oci://` et `file://` ne sont pas concernées. Limite : si un chart mêle un dépôt HTTP et une dépendance `@alias` (dépôt déjà ajouté par l'utilisateur), l'alias n'est pas résolu par le contrôle.

**Outil absent** : ignoré sur le poste (avertissement dans un projet, silence pour un fichier isolé) ; bloquant en CI avec le [mode strict](ci.md).

**Versions des outils** : celles du projet sont prioritaires (`node_modules`, `.venv` / uv, `vendor/bin`, `bundle exec`, wrapper Maven / Gradle, plugin Spotless versionné), pour que tout le monde formate à l'identique.

**Linters** : délégués à [MegaLinter](https://megalinter.io) (option de la [CI](ci.md#megalinter)).

## Ajouter un langage

Créer `hooks/lang/<nom>.sh` :

```bash
register elm "elm.json" '\.elm$' standalone   # nom, marqueurs, regex d'extensions, options
elm_format() { elm-format --yes "$@"; }       # fichiers relatifs au projet
elm_test()   { elm-test; }                    # lancé dans le dossier du projet
```

Options : `standalone` (formate hors projet), `outermost` (multi-module), `fallback` (tests seulement si rien d'autre). Voir [Contribuer](contribuer.md) pour le projet exemple et la CI.
