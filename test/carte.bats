#!/usr/bin/env bats
# Carte du projet (repowarden carte) : fonctions, leur « pourquoi » (le
# commentaire juste au-dessus), dans .repowarden/carte/carte.json

load helpers

RW="$BATS_TEST_DIRNAME/../bin/repowarden"
CARTE=.repowarden/carte/carte.json

setup() {
    require jq
    setup_repo
    initial_commit
    git switch -q -c feat/1-carte
}

# Petit projet shell : script .sh, script à shebang sans extension, fichier texte
projet_shell() {
    mkdir -p bin lib
    cat >lib/outil.sh <<'SH'
#!/usr/bin/env bash
# En-tête du fichier, séparé par une ligne vide

# Range les fichiers : évite les doublons
range() { :; }

# Vide le cache,
# sinon il grossit sans fin
# shellcheck disable=SC2034
vide() {
    :
}
nu() { :; }
SH
    cat >bin/outil <<'SH'
#!/bin/sh
# Point d'entrée : lit les options
main() { :; }
SH
    printf 'q() { :; }\n' >notes.txt
    git add -A
    git commit -q --no-verify -m "feat: projet"
}

@test "carte : chaque fonction shell avec fichier, ligne et commentaire" {
    projet_shell
    run "$RW" carte
    [ "$status" -eq 0 ]
    [ -f "$CARTE" ]
    run jq -c '.fichiers["lib/outil.sh"].fonctions' "$CARTE"
    [ "$output" = '[{"ligne":5,"nom":"range","pourquoi":"Range les fichiers : évite les doublons"},{"ligne":10,"nom":"vide","pourquoi":"Vide le cache, sinon il grossit sans fin"},{"ligne":13,"nom":"nu","pourquoi":""}]' ]
    run jq -c '.fichiers["bin/outil"].fonctions' "$CARTE"
    [ "$output" = '[{"ligne":3,"nom":"main","pourquoi":"Point d'"'"'entrée : lit les options"}]' ]
    # Fichier non shell : ignoré
    run jq -r '.fichiers | keys[]' "$CARTE"
    [[ "$output" != *"notes.txt"* ]] || false
    [ "$(jq -r .version "$CARTE")" = 1 ]
}

@test "carte : resume avec le nombre de fonctions sans commentaire" {
    projet_shell
    run "$RW" carte
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 fichier(s), 4 fonction(s), dont 1 sans commentaire"* ]] || false
    [[ "$output" == *".repowarden/carte/carte.json"* ]] || false
}

@test "carte : deux lancements donnent un fichier identique" {
    projet_shell
    "$RW" carte >/dev/null
    cp "$CARTE" "$BATS_TEST_TMPDIR/premiere.json"
    touch lib/outil.sh
    "$RW" carte >/dev/null
    cmp "$BATS_TEST_TMPDIR/premiere.json" "$CARTE"
}

@test "carte : dossier de la carte ignore par git, jamais versionne" {
    projet_shell
    "$RW" carte >/dev/null
    [ -z "$(git status --porcelain)" ]
    [ "$(cat .repowarden/carte/.gitignore)" = "*" ]
}

@test "carte : repowarden.exclude respecte" {
    projet_shell
    git config repowarden.exclude "bin/*"
    "$RW" carte >/dev/null
    run jq -r '.fichiers | keys[]' "$CARTE"
    [ "$output" = "lib/outil.sh" ]
}

@test "carte : lancee depuis un sous-dossier, chemins depuis la racine" {
    projet_shell
    cd lib
    "$RW" carte >/dev/null
    cd ..
    [ -f "$CARTE" ]
    [ ! -e lib/.repowarden ]
    jq -e '.fichiers["lib/outil.sh"]' "$CARTE" >/dev/null
}

@test "carte : hors depot git -> erreur claire" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p hors && cd hors
    run "$RW" carte
    [ "$status" -ne 0 ]
    [[ "$output" == *"dépôt git"* ]] || false
}

@test "carte : --help en francais et en anglais" {
    run "$RW" carte --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage : repowarden carte"* ]] || false
    [ ! -e "$CARTE" ]
    REPOWARDEN_LANG=en run "$RW" carte --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: repowarden carte"* ]] || false
    REPOWARDEN_LANG=en run "$RW" carte
    [[ "$output" == *"function(s)"* ]] || false
}
