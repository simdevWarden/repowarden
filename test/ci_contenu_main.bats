#!/usr/bin/env bats
# ci/contenu-main.sh : contenu propre à la branche principale (release-auto)

load helpers

CONTENU="${CONTENU_MAIN_SCRIPT:-$BATS_TEST_DIRNAME/../ci/contenu-main.sh}"

setup() {
    setup_repo
    # contexte CI : pas de hooks (prepare-commit-msg corrigerait les messages)
    mkdir -p "$BATS_TEST_TMPDIR/nohooks"
    git config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
    git config --unset repowarden.skip
    initial_commit
    git push -q origin main
    export GH_REPO=o/r INTEGRATION=develop MAIN=main
}

# Commit d'un fichier sur la branche courante (dépôt jetable, sans hooks)
fichier() {
    printf '%s\n' "$2" >"$1"
    git add "$1"
    git commit -q -m "chore: $1"
}

@test "contenu main : instantane livre pendant que develop avance -> passe" {
    git switch -q -c develop
    fichier a "a"
    instantane="$(git rev-parse HEAD)"
    fichier b "b"
    git push -q origin develop
    # livraison de l'instantané sur main : merge du commit livré, arbre inchangé
    git switch -q main
    git merge -q --no-ff --no-edit "$instantane"
    run bash "$CONTENU"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ne contient rien de propre"* ]] || false
}

@test "contenu main : commit pousse directement sur main -> echoue" {
    git switch -q -c develop
    fichier a "a"
    git push -q origin develop
    git switch -q main
    fichier propre "propre"
    run bash "$CONTENU"
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::main contient du contenu absent de develop"* ]] || false
    [[ "$output" == *"propre"* ]] || false
}

@test "contenu main : livraison squashee puis reunie dans develop -> passe" {
    git switch -q -c develop
    fichier a "a"
    git switch -q main
    git merge -q --squash develop >/dev/null
    git commit -q -m "chore(release): v1.0.0"
    # historiques réunis : main revient dans develop
    git switch -q develop
    git merge -q --no-ff --no-edit main
    git push -q origin develop
    git switch -q main
    run bash "$CONTENU"
    [ "$status" -eq 0 ]
    [[ "$output" == *"contient déjà tout le contenu de main"* ]] || false
}

@test "contenu main : premier commit sans parent -> comparaison actuelle" {
    git switch -q --orphan develop
    fichier dev "dev"
    git push -q origin develop
    git switch -q main
    run bash "$CONTENU"
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::main contient du contenu absent de develop"* ]] || false
}

@test "release-auto : controle du contenu avant tag et release" {
    local wf="$BATS_TEST_DIRNAME/../.github/workflows/release-auto.yml"
    run grep -q 'bash .repowarden-ci/ci/contenu-main.sh' "$wf"
    [ "$status" -eq 0 ]
    # un vrai contenu propre échoue avant toute release GitHub (npm, tickets)
    awk '/- name: Tag et release$/ { t = NR } /- name: Contenu propre à la branche principale$/ { c = NR } END { exit !(t && c && c < t) }' "$wf"
}
