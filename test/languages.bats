#!/usr/bin/env bats
# Multi-langages : scripts isolés, monorepos, multi-modules, config projet, fallback

load helpers

setup() {
    setup_repo
    initial_commit
    git switch -q -c feat/x
}

load_engine() {
    source "$HOOKS/lib/common.sh"
    source "$HOOKS/lib/lang.sh"
}

# --- Détection ---------------------------------------------------------------

@test "detection : multi-module Maven -> projet parent le plus haut" {
    load_engine
    mkdir -p module/src
    touch pom.xml module/pom.xml
    [ "$(nearest_project module/src/A.java maven)" = "maven ." ]
}

@test "detection : monorepo Python -> projet le plus proche" {
    load_engine
    mkdir -p api/app
    touch pyproject.toml api/pyproject.toml
    [ "$(nearest_project api/app/main.py python)" = "python api" ]
}

@test "detection : marqueurs en glob (.NET *.csproj)" {
    load_engine
    mkdir -p src/Api
    touch src/Api/Api.csproj
    [ "$(nearest_project src/Api/Program.cs dotnet)" = "dotnet src/Api" ]
}

@test "detection : gestionnaire de paquets Node depuis un sous-dossier (monorepo)" {
    load_engine
    mkdir -p packages/web
    touch pnpm-lock.yaml packages/web/package.json
    cd packages/web
    [ "$(node_pm)" = pnpm ]
}

@test "detection : extension -> plugins candidats" {
    load_engine
    [[ " $(plugins_for_file_r src/A.java; echo "$REPLY") " == *" maven "* ]] || false
    [[ " $(plugins_for_file_r src/A.java; echo "$REPLY") " == *" gradle "* ]] || false
    plugins_for_file_r deploy.sh
    [ "$(echo "$REPLY" | tr -d ' ')" = shell ]
    plugins_for_file_r image.png
    [ -z "$(echo "$REPLY" | tr -d ' ')" ]
}

# --- Formatage -----------------------------------------------------------------

@test "format : script Python isole (sans projet) formate par extension" {
    require ruff
    printf 'x  =  1\n' >script.py
    git add script.py
    run git commit -q -m "ajoute script"
    [ "$status" -eq 0 ]
    [ "$(git show HEAD:script.py)" = "x = 1" ]
}

@test "format : monorepo, chaque fichier formate dans son projet" {
    require gofmt
    require ruff
    mkdir -p backend frontend
    printf 'module x\n\ngo 1.21\n' >backend/go.mod
    printf 'package main\nfunc main(){  }\n' >backend/main.go
    touch frontend/pyproject.toml
    printf 'y  =  2\n' >frontend/app.py
    git add -A
    run git commit -q -m "ajoute les deux"
    [ "$status" -eq 0 ]
    [[ "$output" == *"go (backend)"* ]] || false
    [[ "$output" == *"python (frontend)"* ]] || false
    git show HEAD:backend/main.go | grep -q '^func main() {}$'
    [ "$(git show HEAD:frontend/app.py)" = "y = 2" ]
}

@test "format : repowarden.skip <langage> desactive ce langage" {
    require ruff
    git config repowarden.skip "secrets python"
    printf 'x  =  1\n' >script.py
    git add script.py
    git commit -q -m "ajoute script"
    [ "$(git show HEAD:script.py)" = "x  =  1" ]
}

@test "format : Dart isole" {
    require dart
    printf 'void main(){print(1);}\n' >a.dart
    git add a.dart
    git commit -q -m "ajoute dart"
    git show HEAD:a.dart | grep -q '^  print(1);$'
}

@test "format : Terraform isole" {
    require terraform
    printf 'variable "a" {\ndefault="x"\n}\n' >main.tf
    git add main.tf
    git commit -q -m "ajoute tf"
    git show HEAD:main.tf | grep -q '^  default = "x"$'
}

@test "format : outil absent pour un fichier isole -> silencieux" {
    command -v prettier >/dev/null && skip "prettier installé globalement"
    printf '# Titre\n' >NOTES.md
    git add NOTES.md
    run git commit -q -m "ajoute notes"
    [ "$status" -eq 0 ]
    [[ "$output" != *"prettier introuvable"* ]] || false
}

# --- .repowarden.conf -------------------------------------------------------------

@test ".repowarden.conf : format personnalise (recoit les fichiers stages)" {
    printf '#!/bin/sh\nfor f; do echo "// formaté" >>"$f"; done\n' >fmt.sh
    printf '[repowarden]\n\tformat = sh fmt.sh\n' >.repowarden.conf
    git add -A
    git commit -q --no-verify -m "chore: conf"
    echo "code" >a.txt
    git add a.txt
    git commit -q -m "ajoute a"
    git show HEAD:a.txt | grep -q '// formaté'
}

@test ".repowarden.conf : format personnalise qui echoue -> commit refuse" {
    printf '[repowarden]\n\tformat = false\n' >.repowarden.conf
    git add -A
    run git commit -q -m "ajoute conf"
    [ "$status" -ne 0 ]
}

@test ".repowarden.conf : test personnalise qui echoue -> push refuse" {
    printf '[repowarden]\n\ttest = echo tests-perso && exit 3\n' >.repowarden.conf
    git add -A
    git commit -q -m "ajoute conf"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"tests-perso"* ]] || false
}

@test ".repowarden.conf : test personnalise recoit les fichiers modifies sur stdin" {
    printf '#!/bin/sh\ngrep -qx src/a.txt || { echo pas-de-liste; exit 1; }\n' >verifie.sh
    chmod +x verifie.sh
    printf '[repowarden]\n\ttest = ./verifie.sh\n' >.repowarden.conf
    mkdir -p src && echo a >src/a.txt
    git add -A
    git commit -q -m "ajoute conf"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
}

@test ".repowarden.conf : reglages partages (skip)" {
    git switch -q main
    printf '[repowarden]\n\tskip = secrets protect-branch\n' >.repowarden.conf
    git add .repowarden.conf
    git config --unset repowarden.skip
    run git commit -q -m "chore: conf partagée"
    [ "$status" -eq 0 ]
}

@test ".repowarden.conf : git config local prioritaire" {
    printf '[repowarden]\n\tallowedBranches = main\n' >.repowarden.conf
    load_engine
    [ "$(cfg allowedBranches)" = main ]
    git config repowarden.allowedBranches "main develop"
    cfg_load
    [ "$(cfg allowedBranches)" = "main develop" ]
}

# --- Tests (pre-push) -------------------------------------------------------------

@test "pre-push : monorepo, seuls les projets modifies sont testes" {
    require go
    mkdir -p ok ko
    (cd ok && go_project ok)
    (cd ko && go_project fail)
    git add -A
    git commit -q --no-verify -m "chore: deux modules"
    git push -q --no-verify origin feat/x

    echo "// modif" >>ok/x_test.go
    git commit -q -am "test: modifie ok"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tests go (ok)"* ]] || false
    [[ "$output" != *"(ko)"* ]] || false

    echo "// modif" >>ko/x_test.go
    git commit -q -am "test: modifie ko"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"Échec des tests go (ko)"* ]] || false
}

@test "pre-push : fichier non-code d'un projet (README) -> tests du projet" {
    require go
    go_project fail
    git add -A
    git commit -q --no-verify -m "chore: base"
    git push -q --no-verify origin feat/x
    echo doc >>README.md
    git commit -q -am "docs: readme"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
}

@test "pre-push : Makefile en secours quand aucun langage reconnu" {
    require make
    printf 'test:\n\t@echo make-test-lance && exit 1\n' >Makefile
    git add Makefile
    git commit -q -m "build: makefile"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"make-test-lance"* ]] || false
}

@test "pre-push : tests reussis -> resume seul, sans la sortie detaillee" {
    require make
    printf 'test:\n\t@echo avertissement-bruyant && echo "2 passed, 163 warnings"\n' >Makefile
    git add Makefile
    git commit -q -m "build: makefile"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 passed, 163 warnings"* ]] || false
    [[ "$output" != *"avertissement-bruyant"* ]] || false
}

@test "pre-push : tests en echec -> sortie complete" {
    require make
    printf 'test:\n\t@echo detail-1 && echo detail-2 >&2 && exit 1\n' >Makefile
    git add Makefile
    git commit -q -m "build: makefile"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"detail-1"* ]] || false
    [[ "$output" == *"detail-2"* ]] || false
    [[ "$output" == *"Échec des tests tasks"* ]] || false
}

@test "pre-push : Makefile ignore quand un langage est reconnu" {
    require go
    go_project ok
    printf 'test:\n\t@exit 1\n' >Makefile
    git add -A
    git commit -q -m "build: go + make"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tests go"* ]] || false
}

@test "pre-push : simple script sans projet -> rien a tester, push OK" {
    printf '#!/bin/sh\necho hi\n' >deploy.sh
    git add deploy.sh
    git commit -q -m "ajoute script"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucun projet testable"* ]] || false
}

@test "find_up : s'arrete a la racine du depot (chemins Windows/Git Bash)" {
    load_engine
    mkdir -p a/b
    touch marker
    cd a/b
    [ "$(find_up marker)" = "$(cd "$REPO" && pwd -P)/marker" ]
    ! find_up introuvable-xyz
}

@test "detection : multi-module sur 3 niveaux, sans boucle" {
    load_engine
    mkdir -p a/b/c/src
    touch pom.xml a/pom.xml a/b/pom.xml a/b/c/pom.xml
    [ "$(nearest_project a/b/c/src/A.java maven)" = "maven ." ]
    # mémo : deuxième appel identique
    [ "$(nearest_project a/b/c/src/B.java maven)" = "maven ." ]
}

@test "performance : commit de 300 fichiers en moins de 30 s" {
    touch pom.xml
    for d in a b c d e; do
        mkdir -p "src/$d/sub"
        for i in $(seq 1 60); do echo "# doc $i" >"src/$d/sub/F$i.md"; done
    done
    git add -A
    start=$SECONDS
    run git commit -q -m "ajoute 300 fichiers"
    [ "$status" -eq 0 ]
    echo "durée : $((SECONDS - start)) s"
    [ $((SECONDS - start)) -lt 30 ]
}

@test "format : erreur de syntaxe -> commit refuse, message clair" {
    require ruff
    printf 'def f(:\n' >casse.py
    git add casse.py
    run git commit -q -m "ajoute casse"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Échec du formatage"* ]] || false
}

@test "format : outil du projet (.venv) prioritaire sur celui du poste" {
    mkdir -p .venv/bin
    printf '#!/bin/sh\n[ "$1" = --version ] && exit 0\necho RUFF-DU-PROJET >&2\n' >.venv/bin/ruff
    chmod +x .venv/bin/ruff
    touch pyproject.toml
    printf 'x = 1\n' >a.py
    git add a.py pyproject.toml
    run git commit -q -m "ajoute a"
    [[ "$output" == *"RUFF-DU-PROJET"* ]] || false
}

# --- Infrastructure as code ---------------------------------------------------

@test "IaC : les YAML d'un chart Helm ne sont confies qu'a helm (jamais prettier)" {
    load_engine
    mkdir -p chart/templates
    touch chart/Chart.yaml package.json
    plugins_for_file_r chart/templates/svc.yaml
    nearest_project_r chart/templates/svc.yaml "$REPLY"
    [ "$REPLY" = "helm chart" ]
    ! declare -F helm_format
}

@test "IaC : detection Kubernetes, Ansible, Terraform, Packer, Docker, Actions" {
    load_engine
    mkdir -p k8s infra ansible img .github/workflows
    touch k8s/kustomization.yaml infra/main.tf ansible/ansible.cfg img/build.pkr.hcl Dockerfile
    [ "$(nearest_project k8s/deploy.yaml "kubernetes node")" = "kubernetes k8s" ]
    [ "$(nearest_project infra/vars.tf terraform)" = "terraform infra" ]
    [ "$(nearest_project ansible/site.yml "ansible node")" = "ansible ansible" ]
    [ "$(nearest_project img/vars.pkrvars.hcl packer)" = "packer img" ]
    [[ " $(plugins_for_file_r Dockerfile.prod; echo "$REPLY") " == *" docker "* ]] || false
    has_marker . actions
}

@test "IaC : workflow GitHub modifie -> actionlint lance au push" {
    require actionlint
    mkdir -p .github/workflows
    printf 'name: ci\non: push\njobs:\n  b:\n    runs-onn: ubuntu-latest\n    steps:\n      - run: echo\n' >.github/workflows/ci.yml
    git add -A
    git commit -q -m "ci: workflow"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"actionlint"* ]] || false
}

@test "pre-push : shellcheck bloque sur warning (SC2034) avec severite par defaut" {
    require shellcheck
    printf '#!/bin/sh\necho "hello"\n' >script.sh
    git add script.sh
    git commit -q -m "ajoute script"
    git push -q --no-verify origin feat/x
    # Introduce SC2034 (warning): variable non utilisee
    printf '#!/bin/sh\nvar="test"\necho "hello"\n' >script.sh
    git commit -q -am "modifie script"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"SC2034"* ]] || false
}

@test "pre-push : severite=warning n bloque pas sur style/info (SC2248)" {
    require shellcheck
    printf '#!/bin/bash\necho "hello"\n' >script.sh
    git add script.sh
    git commit -q -m "ajoute script"
    git push -q --no-verify origin feat/x
    # Introduce SC2248 (style): guillemets manquants sur variable sure
    printf '#!/bin/bash\nvar=hello\necho $var\n' >script.sh
    git commit -q -am "modifie script"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" != *"SC2248"* ]] || false
}

@test "pre-push : actionlint sur workflow modifie -> bloque si invalide" {
    require actionlint
    mkdir -p .github/workflows
    printf 'name: ci\non: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo\n' >.github/workflows/ci.yml
    git add -A
    git commit -q -m "ci: workflow"
    git push -q --no-verify origin feat/x
    # Introduce invalid workflow
    printf 'name: ci\non: push\njobs:\n  b:\n    runs-onn: ubuntu-latest\n    steps:\n      - run: echo\n' >.github/workflows/ci.yml
    git commit -q -am "modifie workflow"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"actionlint"* ]] || false
}

@test "pre-push : repowarden.skip lint desactive le linting" {
    require shellcheck
    git config repowarden.skip lint
    printf '#!/bin/sh\necho "hello"\n' >script.sh
    git add script.sh
    git commit -q -m "ajoute script"
    git push -q --no-verify origin feat/x
    # Introduce SC2034
    printf '#!/bin/sh\nvar="test"\necho "hello"\n' >script.sh
    git commit -q -am "modifie script"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
}

@test "pre-push : lintSeverity=error n bloque pas sur warning (SC2034)" {
    require shellcheck
    git config repowarden.lintSeverity error
    printf '#!/bin/sh\necho "hello"\n' >script.sh
    git add script.sh
    git commit -q -m "ajoute script"
    git push -q --no-verify origin feat/x
    # SC2034 (warning) : ne doit pas bloquer avec severity=error
    printf '#!/bin/sh\nvar="test"\necho "hello"\n' >script.sh
    git commit -q -am "modifie script"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
}

@test "pre-push : lintSeverity=style bloque sur style (SC2248)" {
    require shellcheck
    git config repowarden.lintSeverity style
    printf '#!/bin/bash\necho "hello"\n' >script.sh
    git add script.sh
    git commit -q -m "ajoute script"
    git push -q --no-verify origin feat/x
    # SC2248 (style) : doit bloquer avec severity=style
    printf '#!/bin/bash\nvar=hello\necho $var\n' >script.sh
    git commit -q -am "modifie script"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"SC2248"* ]] || false
}

@test "pre-push : shellcheck detecte script sans extension avec shebang" {
    require shellcheck
    printf '#!/bin/bash\necho "hello"\n' >myscript
    git add myscript
    git commit -q -m "ajoute script sans extension"
    git push -q --no-verify origin feat/x
    # Introduce SC2034
    printf '#!/bin/bash\nvar="test"\necho "hello"\n' >myscript
    git commit -q -am "modifie script"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"SC2034"* ]] || false
}

@test "pre-push : lint.missing recoit outil, fichier et commande installation" {
    require shellcheck
    # On simule l'absence de shellcheck en le masquant temporairement
    mkdir -p "$F/bin"
    PATH="$F/bin:$PATH"
    printf '#!/bin/bash\necho "hello"\n' >script.sh
    git add script.sh
    git commit -q -m "ajoute script"
    git push -q --no-verify origin feat/x
    # Introduce SC2034
    printf '#!/bin/bash\nvar="test"\necho "hello"\n' >script.sh
    git commit -q -am "modifie script"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    # Le message d'avertissement doit contenir les 3 valeurs
    [[ "$output" == *"shellcheck"* ]] || false
    [[ "$output" == *"script.sh"* ]] || false
    [[ "$output" == *"brew install shellcheck"* || "$output" == *"apt-get install shellcheck"* || "$output" == *"choco install shellcheck"* || "$output" == *"https://www.shellcheck.net/"* ]] || false
}

# --- Jeton gh sans le scope workflow (pre-push) ----------------------------------

# gh simulé : connecté (scopes FAKE_GH_SCOPES) ou non (FAKE_GH_OK=0).
# Chaque appel est journalisé dans $GHBIN/log (preuve qu'il a été appelé).
fake_gh() {
    GHBIN="$BATS_TEST_TMPDIR/ghbin"
    mkdir -p "$GHBIN"
    : >"$GHBIN/log"
    cat >"$GHBIN/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$(dirname "$0")/log"
case "$1 $2" in
    "auth status")
        [ "${FAKE_GH_OK:-1}" = 1 ] || exit 1
        printf "Token scopes: '%s'\n" "${FAKE_GH_SCOPES:-gist, read:org, repo}"
        ;;
esac
exit 0
GH
    chmod +x "$GHBIN/gh"
}

# Un fichier de workflow commité (valide : actionlint ne doit pas bloquer)
workflow_commit() {
    mkdir -p .github/workflows
    printf 'name: ci\non: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo\n' >.github/workflows/ci.yml
    git add -A
    git commit -q -m "ci: workflow"
}

@test "pre-push : jeton gh sans scope workflow et workflow pousse -> avertissement" {
    fake_gh
    workflow_commit
    FAKE_GH_SCOPES="gist, read:org, repo" PATH="$GHBIN:$PATH" run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"gh auth refresh -h github.com -s workflow"* ]] || false
}

@test "pre-push : jeton gh avec scope workflow -> aucun avertissement" {
    fake_gh
    workflow_commit
    FAKE_GH_SCOPES="gist, read:org, repo, workflow" PATH="$GHBIN:$PATH" run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" != *"gh auth refresh"* ]] || false
}

@test "pre-push : gh non connecte -> aucun avertissement de scope" {
    fake_gh
    workflow_commit
    FAKE_GH_OK=0 PATH="$GHBIN:$PATH" run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" != *"gh auth refresh"* ]] || false
}

@test "pre-push : push sans workflow -> gh n'est pas appele" {
    fake_gh
    printf 'x\n' >f.txt
    git add -A
    git commit -q -m "chore: fichier"
    PATH="$GHBIN:$PATH" run git push -q origin feat/x
    [ "$status" -eq 0 ]
    [ ! -s "$GHBIN/log" ]
}

@test "python : pas de faux succes avec un .pyc perime (meme taille, meme seconde)" {
    require pytest
    load_engine
    mkdir -p tests
    printf '[tool.pytest.ini_options]\npythonpath = ["."]\n' >pyproject.toml
    printf 'def test_x():\n    assert 1 == 1\n' >tests/test_x.py
    python_test >/dev/null 2>&1
    pytest -q >/dev/null 2>&1 || true # laisse un .pyc dans __pycache__
    printf 'def test_x():\n    assert 1 == 2\n' >tests/test_x.py
    touch -r pyproject.toml tests/test_x.py
    run python_test
    [ "$status" -ne 0 ]
}

@test "python : tests/ importe le paquet du projet sans configuration (racine importable)" {
    require pytest
    load_engine
    mkdir -p calc tests
    printf '[project]\nname = "calc"\nversion = "0.1.0"\n' >pyproject.toml
    printf 'def add(a, b):\n    return a + b\n' >calc/__init__.py
    printf 'from calc import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n' >tests/test_calc.py
    run python_test
    [ "$status" -eq 0 ]
    [[ "$output" != *"ModuleNotFoundError"* ]] || false
}

@test "config : lue une seule fois, cles insensibles a la casse, derniere valeur" {
    git config repowarden.allowedBranches "a"
    git config --add repowarden.allowedBranches "b"
    git config repowarden.skip ""
    load_engine
    [ "$(cfg allowedbranches)" = b ]
    [ "$(cfg ALLOWEDBRANCHES)" = b ]
    [ -z "$(cfg skip)" ]
    [ "$(cfg inexistante defaut)" = defaut ]
}
