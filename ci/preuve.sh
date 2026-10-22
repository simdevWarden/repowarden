#!/usr/bin/env bash
# Preuve reproductible du ticket #169 : compare repowarden à un assemblage
# classique (pre-commit, release-please, protection GitHub) sur le même projet.
# Le mode complet a besoin du réseau et installe ses outils dans un dossier
# temporaire. --scenario <id> rejoue un seul cas hors ligne, avec les hooks de
# ce dépôt (utilisé par test/preuve.bats).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEMO_URL="${PREUVE_DEMO_URL:-https://github.com/simdevWarden/repowarden-demo}"
DEMO_COMMIT="${PREUVE_DEMO_COMMIT:-83b6099c935a24b5aec56645c7a28d71dc80253b}"
GITLEAKS_VERSION="${PREUVE_GITLEAKS_VERSION:-8.30.1}"
RUFF_VERSION="${PREUVE_RUFF_VERSION:-0.16.10}"
PYTEST_VERSION="${PREUVE_PYTEST_VERSION:-9.1.1}"
CONVENTIONAL_REV="${PREUVE_CONVENTIONAL_REV:-v4.4.0}"
HOOKS_REV="${PREUVE_HOOKS_REV:-v6.0.0}"
RUFF_PRECOMMIT_REV="${PREUVE_RUFF_PRECOMMIT_REV:-v0.16.10}"

MODE=complet
SCENARIO=""
TMP=""
OUT=""
CODE=0
RESULTAT=""
DETAIL=""
VERSION_PRECOMMIT=""
VERSION_REPOWARDEN=""

SCENARIOS="message-non-conforme commit-sur-main mauvais-nom-branche secret env-non-ignore format test-casse-push message-invalide-push fonction-sans-commentaire force-push-agent"

FICHIERS_CLASSIQUE=(
    .pre-commit-config.yaml
    release-please-config.json
    .release-please-manifest.json
    .github/workflows/ci.yml
    .github/workflows/release-please.yml
)
FICHIERS_REPOWARDEN=(
    .repowarden.conf
    .github/workflows/repowarden.yml
    .github/workflows/release.yml
    .github/workflows/tickets.yml
    .github/workflows/nettoyage.yml
)

# Supprime le dossier temporaire (copies, remotes, environnements) en gardant
# le code de sortie du script.
nettoyer() {
    local code=$?
    trap - EXIT INT TERM
    [ -z "$TMP" ] || rm -rf "$TMP"
    exit "$code"
}
trap nettoyer EXIT INT TERM

erreur() {
    printf 'preuve : %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage : ci/preuve.sh [--scenario <id>] [--liste]

Sans option : mesure complète (réseau, outils tiers dans un dossier temporaire).
  --scenario <id>  rejoue un scénario hors ligne avec les hooks de ce dépôt
  --liste          affiche les identifiants des scénarios

Scénarios : message-non-conforme, commit-sur-main, mauvais-nom-branche, secret,
env-non-ignore, format, test-casse-push, message-invalide-push,
fonction-sans-commentaire, force-push-agent.
EOF
}

besoin() {
    command -v "$1" >/dev/null 2>&1 || erreur "$1 est requis"
}

# Vrai si l'identifiant de scénario existe.
scenario_connu() {
    case " $SCENARIOS " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

lister_scenarios() {
    local id
    for id in $SCENARIOS; do
        printf '%s\t%s\n' "$id" "$(libelle_scenario "$id")"
    done
}

# Libellé lisible d'un scénario (tableau publié dans docs/pourquoi.md).
libelle_scenario() {
    case "$1" in
        message-non-conforme) printf 'Message non conforme' ;;
        commit-sur-main) printf 'Commit direct sur main' ;;
        mauvais-nom-branche) printf 'Mauvais nom de branche' ;;
        secret) printf 'Secret dans un fichier stagé' ;;
        env-non-ignore) printf '.env ni suivi ni ignoré' ;;
        format) printf 'Fichier mal formaté' ;;
        test-casse-push) printf 'Test cassé au push' ;;
        message-invalide-push) printf 'Message invalide découvert au push' ;;
        fonction-sans-commentaire) printf 'Fonction ajoutée sans commentaire' ;;
        force-push-agent) printf 'Force push demandé par un agent' ;;
        *) printf '%s' "$1" ;;
    esac
}

# Libellé lisible d'un résultat (bloqué, averti, passé).
libelle_resultat() {
    case "$1" in
        bloque) printf 'bloqué' ;;
        averti) printf 'averti' ;;
        passe) printf 'passé' ;;
        erreur) printf 'erreur' ;;
        *) printf 'non mesuré' ;;
    esac
}

# Temps réel en secondes d'une commande, sortie masquée (TIMEFORMAT de bash 3.2).
chronometrer() {
    local t code=0
    TIMEFORMAT='%3R'
    t=$( { time "$@" >/dev/null 2>&1; } 2>&1 ) || code=$?
    printf '%s\n' "$t"
    return "$code"
}

# Médiane de trois durées (le mode complet en mesure toujours trois).
mediane() {
    sort -n | sed -n '2p'
}

# Vrai si la sortie capturée contient un des motifs : un échec inconnu n'est
# jamais présenté comme un blocage.
motif() {
    local m
    for m in "$@"; do
        case "$OUT" in
            *"$m"*) return 0 ;;
        esac
    done
    return 1
}

# Traduit CODE/OUT en résultat : bloqué si le refus attendu est présent, averti
# si un avertissement connu est présent, passé sinon, erreur si l'échec est
# inconnu.
conclure_commit() {
    if [ "$CODE" -ne 0 ]; then
        if motif "$@"; then
            RESULTAT=bloque
        else
            RESULTAT=erreur
            DETAIL="échec inattendu"
        fi
    elif motif "sans commentaire" "Fichier sensible" "Sensitive file"; then
        RESULTAT=averti
    else
        RESULTAT=passe
    fi
}

# Nombre de lignes utiles (ni vides ni commentaires) d'un fichier.
lignes_utiles() {
    awk '!/^[[:space:]]*(#|$)/' "$1" | wc -l | tr -d ' '
}

# Total « fichiers, lignes, lignes utiles » d'une liste de fichiers relative $1.
compter_fichiers() {
    local dir="$1" f n=0 total=0 utiles=0 lignes
    shift
    for f in "$@"; do
        [ -f "$dir/$f" ] || continue
        n=$((n + 1))
        lignes=$(wc -l <"$dir/$f" | tr -d ' ')
        total=$((total + lignes))
        utiles=$((utiles + $(lignes_utiles "$dir/$f")))
    done
    printf '%s\t%s\t%s\n' "$n" "$total" "$utiles"
}

# Installe les outils de mesure (pre-commit, ruff, pytest, gitleaks) dans un
# dossier temporaire : rien n'est installé globalement.
preparer_outils() {
    local venv="$TMP/outils" os arch url
    besoin python3
    besoin git
    besoin curl
    besoin tar
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet --disable-pip-version-check \
        pre-commit "ruff==$RUFF_VERSION" "pytest==$PYTEST_VERSION"
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"
    case "$arch" in
        arm64 | aarch64) arch=arm64 ;;
        x86_64 | amd64) arch=x64 ;;
        *) erreur "architecture non gérée : $arch" ;;
    esac
    case "$os" in
        darwin | linux) ;;
        *) erreur "système non géré : $os" ;;
    esac
    url="https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_${os}_${arch}.tar.gz"
    curl -fsSL "$url" | tar -xz -C "$venv/bin" gitleaks
    export PATH="$venv/bin:$PATH"
}

# Crée les modèles complets : repowarden-demo au commit fixé, puis l'assemblage
# classique (pre-commit + release-please + workflow CI) et repowarden (modèles).
preparer_modeles_complets() {
    local base="$TMP/base" demo="$TMP/demo" c="$TMP/template-classique" r="$TMP/template-repowarden"
    git clone -q "$DEMO_URL" "$demo"
    git -C "$demo" checkout -q "$DEMO_COMMIT"
    mkdir -p "$base"
    git -C "$demo" archive "$DEMO_COMMIT" README.md README.en.md pyproject.toml src tests .gitignore |
        tar -x -C "$base"

    cp -R "$base" "$c"
    mkdir -p "$c/.github/workflows"
    cat >"$c/.pre-commit-config.yaml" <<EOF
# Assemblage « classique » : chaque contrôle vient d'un outil distinct.
repos:
  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: $CONVENTIONAL_REV
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]
  - repo: https://github.com/gitleaks/gitleaks
    rev: v$GITLEAKS_VERSION
    hooks:
      - id: gitleaks-system
        pass_filenames: false
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: $RUFF_PRECOMMIT_REV
    hooks:
      - id: ruff-format
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: $HOOKS_REV
    hooks:
      - id: no-commit-to-branch
        args: [--branch, main]
  - repo: local
    hooks:
      - id: pytest
        name: pytest
        entry: pytest -q
        language: system
        pass_filenames: false
        stages: [pre-push]
EOF
    cat >"$c/release-please-config.json" <<'EOF'
{
  "release-type": "python",
  "packages": {
    ".": {
      "package-name": "calc",
      "changelog-path": "CHANGELOG.md"
    }
  }
}
EOF
    cat >"$c/.release-please-manifest.json" <<'EOF'
{
  ".": "0.1.1"
}
EOF
    cat >"$c/.github/workflows/ci.yml" <<'EOF'
name: ci
on: [push, pull_request]
jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install pre-commit ruff pytest
      - run: pre-commit run --all-files
      - run: pytest -q
      - run: pre-commit run --hook-stage pre-push --all-files
EOF
    cat >"$c/.github/workflows/release-please.yml" <<'EOF'
name: release-please
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: write
jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v5
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
EOF

    cp -R "$base" "$r"
    cp "$demo/.repowarden.conf" "$r/"
    mkdir -p "$r/.github/workflows"
    cp "$demo/.github/workflows/repowarden.yml" "$r/.github/workflows/"
    cp "$demo/.github/workflows/release.yml" "$r/.github/workflows/"
    cp "$demo/.github/workflows/tickets.yml" "$r/.github/workflows/"
    cp "$demo/.github/workflows/nettoyage.yml" "$r/.github/workflows/"
}

# Crée le modèle hors ligne : projet minimal, hooks du dépôt, formateur et
# gitleaks simulés, commande de test volontairement en échec.
preparer_modele_local() {
    local modele="$TMP/template-repowarden" outils="$TMP/outils"
    mkdir -p "$modele/src/calc" "$modele/tests" "$outils/bin"
    printf '# calc\n\nProjet minimal de la preuve.\n' >"$modele/README.md"
    printf '__pycache__/\n.pytest_cache/\n' >"$modele/.gitignore"
    printf '[project]\nname = "calc"\nversion = "0.1.1"\nrequires-python = ">=3.10"\n' >"$modele/pyproject.toml"
    printf 'def add(a, b):\n    return a + b\n' >"$modele/src/calc/__init__.py"
    printf 'from calc import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n' >"$modele/tests/test_calc.py"

    cat >"$outils/bin/gitleaks" <<'EOF'
#!/usr/bin/env bash
# gitleaks simulé pour le test hors ligne : signale un jeton ghp_ stagé, avec
# le même rapport JSON minimal que gitleaks 8.30.
set -u
rapport=""
while [ $# -gt 0 ]; do
    case "$1" in
        --report-path) rapport="${2:-}"; shift ;;
    esac
    shift
done
fichier=""
ligne=0
while IFS= read -r f; do
    [ -f "$f" ] || continue
    n="$(grep -n 'ghp_' "$f" 2>/dev/null | sed -n '1p' | cut -d: -f1 || true)"
    if [ -n "$n" ]; then
        fichier="$f"
        ligne="$n"
        break
    fi
done < <(git diff --cached --name-only)
if [ -n "$fichier" ]; then
    printf '[{"RuleID":"github-pat","StartLine":%s,"File":"%s","Secret":"REDACTED"}]\n' \
        "$ligne" "$fichier" >"$rapport"
    exit 42
fi
printf '[]\n' >"$rapport"
exit 0
EOF
    chmod +x "$outils/bin/gitleaks"

    cat >"$outils/formateur.sh" <<'EOF'
#!/bin/sh
# Formateur simulé : corrige seulement le fichier du scénario de formatage.
for f in "$@"; do
    case "$f" in
        *moche.py) printf 'x = 1\n' >"$f" ;;
    esac
done
EOF
    chmod +x "$outils/formateur.sh"

    printf '[repowarden]\n    lang = fr\n    format = /bin/sh %s/formateur.sh\n    test = exit 1\n' \
        "$outils" >"$modele/.repowarden.conf"
}

# Prépare une copie jetable du modèle avec son remote nu et les hooks du côté
# demandé (pre-commit installé, ou hooks repowarden du dépôt).
preparer_depot() {
    local dir="$1" side="$2" modele
    case "$side" in
        classique) modele="$TMP/template-classique" ;;
        repowarden) modele="$TMP/template-repowarden" ;;
        *) erreur "côté inconnu : $side" ;;
    esac
    mkdir -p "$TMP/cas"
    cp -R "$modele" "$dir"
    git init -q -b main "$dir"
    git init -q --bare -b main "$dir.git"
    git -C "$dir" config user.name preuve
    git -C "$dir" config user.email preuve@example.com
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" config repowarden.skip tickets
    git -C "$dir" remote add origin "$dir.git"
    if [ "$side" = classique ]; then
        if ! (cd "$dir" && "$TMP/outils/bin/pre-commit" install \
            --hook-type pre-commit --hook-type commit-msg --hook-type pre-push) >/dev/null 2>&1; then
            erreur "câblage pre-commit impossible dans $dir"
        fi
        git -C "$dir" add -A
        git -C "$dir" commit -q --no-verify -m "chore: init"
    else
        git -C "$dir" config core.hooksPath "$ROOT/hooks"
        git -C "$dir" add -A
        (cd "$dir" && git commit -q -m "chore: init") >/dev/null 2>&1 ||
            erreur "commit initial repowarden refusé"
    fi
    git -C "$dir" push -q --no-verify origin main
}

# Lance un commit dans $1 avec le message $2 ; garde code et sortie dans CODE/OUT.
lancer_commit() {
    local dir="$1" msg="$2"
    CODE=0
    OUT="$(cd "$dir" && git commit -q -m "$msg" 2>&1)" || CODE=$?
}

# Lance un push de $2 dans $1 ; garde code et sortie dans CODE/OUT.
lancer_push() {
    local dir="$1" branche="$2"
    CODE=0
    OUT="$(cd "$dir" && git push -q origin "$branche" 2>&1)" || CODE=$?
}

sc_message() {
    git -C "$1" switch -q -c feat/x
    printf '\nmodif\n' >>"$1/README.md"
    git -C "$1" add README.md
    lancer_commit "$1" "doc: essai"
    conclure_commit "Message de commit invalide" "Type « doc » inconnu" "Conventional Commits" "conventional-pre-commit"
}

sc_main() {
    printf '\nmodif\n' >>"$1/README.md"
    git -C "$1" add README.md
    lancer_commit "$1" "chore: essai"
    conclure_commit "Commit direct sur" "no-commit-to-branch"
}

sc_branche() {
    git -C "$1" switch -q -c wip-x
    printf '\nmodif\n' >>"$1/README.md"
    git -C "$1" add README.md
    lancer_commit "$1" "feat: essai"
    conclure_commit "nom de branche non conforme" "branch name"
}

sc_secret() {
    git -C "$1" switch -q -c feat/x
    printf 'token = ghp_%s\n' "4Rk9vQ2xLm7TzP0aWc3Ny8BdHs5Ju1Ef6GiX" >"$1/config.ini" # factice
    git -C "$1" add config.ini
    lancer_commit "$1" "feat: config"
    conclure_commit "Secret détecté" "gitleaks" "hardcoded secrets"
}

sc_env() {
    git -C "$1" switch -q -c feat/x
    printf 'API_KEY=valeur-tres-secrete\n' >"$1/.env"
    printf '\nmodif\n' >>"$1/README.md"
    git -C "$1" add README.md
    lancer_commit "$1" "feat: suite"
    conclure_commit
}

sc_format() {
    git -C "$1" switch -q -c feat/x
    printf 'x=1\n' >"$1/src/calc/moche.py"
    git -C "$1" add src/calc/moche.py
    lancer_commit "$1" "feat: format"
    if [ "$CODE" -eq 0 ]; then
        RESULTAT=passe
        if [ "$(git -C "$1" show HEAD:src/calc/moche.py | tr -d '\n')" = "x = 1" ]; then
            DETAIL="corrigé"
        fi
    elif motif "files were modified" "ruff" "reformatted"; then
        RESULTAT=bloque
        DETAIL="correction à re-stager"
    else
        RESULTAT=erreur
        DETAIL="échec inattendu"
    fi
}

sc_test() {
    git -C "$1" switch -q -c feat/x
    printf '\n\ndef test_ko():\n    assert False\n' >>"$1/tests/test_calc.py"
    git -C "$1" add tests/test_calc.py
    lancer_commit "$1" "test: casse"
    if [ "$CODE" -ne 0 ]; then
        RESULTAT=erreur
        DETAIL="commit refusé"
        return
    fi
    lancer_push "$1" feat/x
    conclure_commit "pytest" "failed" "échec"
}

sc_message_push() {
    git -C "$1" switch -q -c feat/x
    printf '\nmodif\n' >>"$1/README.md"
    git -C "$1" add README.md
    CODE=0
    OUT="$(cd "$1" && git -c core.hooksPath=/dev/null commit -q -m "pas conforme" 2>&1)" || CODE=$?
    if [ "$CODE" -ne 0 ]; then
        RESULTAT=erreur
        DETAIL="commit hors hooks refusé"
        return
    fi
    lancer_push "$1" feat/x
    conclure_commit "message de commit non conforme" "commit message"
}

sc_commentaires() {
    git -C "$1" switch -q -c feat/x
    printf '#!/usr/bin/env bash\nsans_commentaire() { :; }\n' >"$1/outils.sh"
    git -C "$1" add outils.sh
    lancer_commit "$1" "feat: outil"
    conclure_commit
}

sc_garde() {
    if [ "$2" = classique ]; then
        RESULTAT=passe
        DETAIL="aucun garde-fou d'agent"
        return
    fi
    if ! command -v jq >/dev/null 2>&1; then
        RESULTAT=non-mesure
        DETAIL="jq absent"
        return
    fi
    local json
    json="$(jq -cn --arg c "git push --force origin feat/x" --arg d "$1" \
        '{tool: "bash", args: {command: $c}, cwd: $d}')"
    CODE=0
    OUT="$(printf '%s' "$json" | (cd "$1" && "$ROOT/bin/repowarden" garde) 2>&1)" || CODE=$?
    if [ "$CODE" -eq 2 ] && motif "force le push"; then
        RESULTAT=bloque
    else
        RESULTAT=erreur
        DETAIL="garde : code $CODE"
    fi
}

# Joue un scénario sur un côté et renseigne RESULTAT/DETAIL.
jouer_scenario() {
    local id="$1" side="$2" dir="$3"
    RESULTAT=""
    DETAIL=""
    preparer_depot "$dir" "$side"
    case "$id" in
        message-non-conforme) sc_message "$dir" ;;
        commit-sur-main) sc_main "$dir" ;;
        mauvais-nom-branche) sc_branche "$dir" ;;
        secret) sc_secret "$dir" ;;
        env-non-ignore) sc_env "$dir" ;;
        format) sc_format "$dir" ;;
        test-casse-push) sc_test "$dir" ;;
        message-invalide-push) sc_message_push "$dir" ;;
        fonction-sans-commentaire) sc_commentaires "$dir" ;;
        force-push-agent) sc_garde "$dir" "$side" ;;
        *) erreur "scénario inconnu : $id" ;;
    esac
}

# Résultat attendu côté repowarden, publié dans docs/pourquoi.md.
attendu_pour() {
    case "$1" in
        message-non-conforme | commit-sur-main | mauvais-nom-branche | secret | \
            test-casse-push | message-invalide-push | force-push-agent)
            printf 'bloque'
            ;;
        env-non-ignore | fonction-sans-commentaire)
            printf 'averti'
            ;;
        format)
            printf 'passe'
            ;;
        *)
            printf 'inconnu'
            ;;
    esac
}

# Mode hors ligne : un scénario, hooks du dépôt, outils simulés, résultat
# comparé à la page.
executer_scenario() {
    local id="$1" dir attendu
    scenario_connu "$id" || erreur "scénario inconnu : $id"
    preparer_modele_local
    export PATH="$TMP/outils/bin:$PATH"
    export REPOWARDEN_LANG=fr
    dir="$TMP/cas/local-$id"
    jouer_scenario "$id" repowarden "$dir"
    attendu="$(attendu_pour "$id")"
    if [ "$RESULTAT" != "$attendu" ]; then
        printf 'preuve : %s attendu %s, obtenu %s (%s)\n' \
            "$id" "$attendu" "$RESULTAT" "$DETAIL" >&2
        [ -z "$OUT" ] || printf 'sortie :\n%s\n' "$OUT" >&2
        exit 1
    fi
    printf '%s\t%s\n' "$id" "$RESULTAT"
}

# Installe pre-commit dans un environnement neuf et câble une copie jetable :
# temps d'installation d'un poste pour l'assemblage classique.
installer_classique_mesure() {
    local d="$1"
    export PIP_CACHE_DIR="$d/pip-cache"
    python3 -m venv "$d/venv"
    "$d/venv/bin/pip" install --quiet --disable-pip-version-check pre-commit
    mkdir -p "$d/repo"
    cp "$TMP/template-classique/.pre-commit-config.yaml" "$d/repo/"
    git init -q -b main "$d/repo"
    (cd "$d/repo" && "$d/venv/bin/pre-commit" install \
        --hook-type pre-commit --hook-type commit-msg --hook-type pre-push) >/dev/null
    [ -x "$d/repo/.git/hooks/pre-commit" ]
}

# Installe repowarden (npm) dans un préfixe temporaire puis active les hooks
# globaux avec un HOME et une configuration git isolés.
installer_repowarden_mesure() {
    local d="$1"
    mkdir -p "$d/home"
    : >"$d/gitconfig"
    env HOME="$d/home" GIT_CONFIG_GLOBAL="$d/gitconfig" npm_config_cache="$d/npm-cache" \
        npm install -g --silent --prefix "$d/prefix" repowarden@latest
    env HOME="$d/home" GIT_CONFIG_GLOBAL="$d/gitconfig" \
        "$d/prefix/bin/repowarden" install --global --sans-bots --lang fr
}

# Affiche les temps d'installation (médiane de 3) et les versions réellement
# utilisées.
mesurer_installations() {
    local i d c r v
    local valeurs_c=() valeurs_r=()
    for i in 1 2 3; do
        d="$TMP/mesure-c-$i"
        if ! v="$(chronometrer installer_classique_mesure "$d")"; then
            erreur "installation pre-commit échouée (essai $i)"
        fi
        valeurs_c+=("$v")
        d="$TMP/mesure-r-$i"
        if ! v="$(chronometrer installer_repowarden_mesure "$d")"; then
            erreur "installation repowarden échouée (essai $i)"
        fi
        valeurs_r+=("$v")
    done
    c="$(printf '%s\n' "${valeurs_c[@]}" | mediane)"
    r="$(printf '%s\n' "${valeurs_r[@]}" | mediane)"
    VERSION_PRECOMMIT="$("$TMP/mesure-c-1/venv/bin/pre-commit" --version)"
    VERSION_REPOWARDEN="$("$TMP/mesure-r-1/prefix/bin/repowarden" --version)"

    printf "## Temps d'installation d'un poste\n\n"
    printf '| Assemblage | Médiane (s) | Versions |\n'
    printf '|---|---|---|\n'
    printf "| pre-commit + câblage d'un dépôt | %s | %s |\n" "$c" "$VERSION_PRECOMMIT"
    printf '| repowarden (npm) + hooks globaux | %s | %s |\n\n' "$r" "$VERSION_REPOWARDEN"
    printf 'Versions des outils de mesure : %s, %s, gitleaks %s, Python %s, Node %s.\n\n' \
        "$VERSION_PRECOMMIT" "$("$TMP/outils/bin/ruff" --version)" "$GITLEAKS_VERSION" \
        "$(python3 --version | sed 's/^Python //')" "$(node --version 2>/dev/null || printf 'absent')"
    printf 'Machine : %s %s. Date : %s (UTC).\n\n' \
        "$(uname -s)" "$(uname -m)" "$(date -u +%Y-%m-%d)"
}

# Affiche le nombre de fichiers et de lignes de configuration par assemblage.
mesurer_configuration() {
    local res n total utiles
    printf '## Configuration par projet\n\n'
    printf '| Assemblage | Fichiers | Lignes | Lignes utiles |\n'
    printf '|---|---|---|---|\n'
    res="$(compter_fichiers "$TMP/template-classique" ${FICHIERS_CLASSIQUE[@]+"${FICHIERS_CLASSIQUE[@]}"})"
    IFS="$(printf '\t')" read -r n total utiles <<<"$res"
    printf '| Assemblage classique | %s | %s | %s |\n' "$n" "$total" "$utiles"
    res="$(compter_fichiers "$TMP/template-repowarden" ${FICHIERS_REPOWARDEN[@]+"${FICHIERS_REPOWARDEN[@]}"})"
    IFS="$(printf '\t')" read -r n total utiles <<<"$res"
    printf '| repowarden | %s | %s | %s |\n\n' "$n" "$total" "$utiles"
}

# Cellule Markdown d'un scénario joué sur un côté.
cellule() {
    local id="$1" side="$2"
    jouer_scenario "$id" "$side" "$TMP/cas/$side-$id"
    libelle_resultat "$RESULTAT"
    [ -z "$DETAIL" ] || printf ' (%s)' "$DETAIL"
}

# Affiche le jeu de commits fautifs sur les deux assemblages.
afficher_scenarios() {
    local id cell_c cell_r erreurs=0
    printf '## Jeu de commits fautifs\n\n'
    printf '| Scénario | Assemblage classique | repowarden |\n'
    printf '|---|---|---|\n'
    for id in $SCENARIOS; do
        cell_c="$(cellule "$id" classique)"
        cell_r="$(cellule "$id" repowarden)"
        case "$cell_c$cell_r" in
            *erreur*) erreurs=1 ;;
        esac
        printf '| %s | %s | %s |\n' "$(libelle_scenario "$id")" "$cell_c" "$cell_r"
    done
    printf '\n'
    [ "$erreurs" -eq 0 ] || erreur "au moins un scénario n'a pas donné le résultat attendu"
}

executer_complet() {
    besoin git
    besoin python3
    besoin npm
    besoin jq
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/preuve.XXXXXX")"
    export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1
    : >"$GIT_CONFIG_GLOBAL"
    export PIP_CACHE_DIR="$TMP/pip-cache"
    export npm_config_cache="$TMP/npm-cache"
    export PRE_COMMIT_HOME="$TMP/pre-commit-home"
    export REPOWARDEN_LANG=fr
    preparer_outils
    preparer_modeles_complets
    printf '# Résultats mesurés\n\n'
    printf "Commande : \`ci/preuve.sh\` · repowarden-demo \`%s\`.\n\n" "$DEMO_COMMIT"
    mesurer_configuration
    mesurer_installations
    afficher_scenarios
}

while [ $# -gt 0 ]; do
    case "$1" in
        --scenario)
            shift
            SCENARIO="${1:-}"
            [ -n "$SCENARIO" ] || erreur "--scenario attend un identifiant"
            MODE=scenario
            ;;
        --liste)
            lister_scenarios
            exit 0
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            erreur "option inconnue : $1"
            ;;
    esac
    shift
done

if [ "$MODE" = scenario ]; then
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/preuve.XXXXXX")"
    export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
    export GIT_CONFIG_NOSYSTEM=1
    : >"$GIT_CONFIG_GLOBAL"
    executer_scenario "$SCENARIO"
else
    executer_complet
fi
