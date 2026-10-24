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

# Dépôt de test avec une copie du vrai bin/garde de repowarden
projet_garde() {
    mkdir -p bin
    cp "$BATS_TEST_DIRNAME/../bin/garde" bin/garde
    git add bin/garde
    git commit -q --no-verify -m "feat: garde"
}

@test "carte : fichier -> ses fonctions et leurs commentaires" {
    projet_garde
    run "$RW" carte bin/garde
    [ "$status" -eq 0 ]
    [[ "$output" == *"bin/garde"* ]] || false
    ligne="$(grep -n '^verifier_gh()' bin/garde | cut -d: -f1)"
    [[ "$output" == *"$ligne  verifier_gh — "* ]] || false
    [[ "$output" == *"dossier_r — REPLY = dossier existant le plus proche"* ]] || false
}

@test "carte : fonction -> fichier, ligne, commentaire ; inconnue -> code 1" {
    projet_garde
    ligne="$(grep -n '^verifier_gh()' bin/garde | cut -d: -f1)"
    run "$RW" carte verifier_gh
    [ "$status" -eq 0 ]
    [[ "$output" == *"verifier_gh  bin/garde:$ligne"* ]] || false
    pourquoi="$(sed -n "$((ligne - 1))p" bin/garde | sed 's/^# *//')"
    [[ "$output" == *"$pourquoi"* ]] || false
    run "$RW" carte fonction_inconnue
    [ "$status" -eq 1 ]
    [[ "$output" == *"fonction_inconnue"*"ni un fichier ni une fonction de la carte"* ]] || false
}

@test "carte : --json du fichier et de la fonction, valide" {
    projet_shell
    run "$RW" carte lib/outil.sh --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.fichier' <<<"$output")" = lib/outil.sh ]
    [ "$(jq -r '.fonctions[0].nom' <<<"$output")" = range ]
    run "$RW" carte --json vide
    [ "$status" -eq 0 ]
    [ "$(jq -c '.' <<<"$output")" = '[{"fichier":"lib/outil.sh","ligne":10,"nom":"vide","pourquoi":"Vide le cache, sinon il grossit sans fin"}]' ]
    run "$RW" carte --json
    [ "$status" -eq 0 ]
    jq -e '.fichiers["bin/outil"]' <<<"$output" >/dev/null
}

@test "carte : fichier depuis un sous-dossier, sans fonction, sans commentaire" {
    projet_shell
    cd lib
    run "$RW" carte outil.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"lib/outil.sh"* ]] || false
    [[ "$output" == *"13  nu (sans commentaire)"* ]] || false
    cd ..
    run "$RW" carte notes.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"notes.txt : aucune fonction"* ]] || false
}

@test "carte : absente ou perimee -> regeneree avant de repondre, a jour -> gardee" {
    projet_shell
    run "$RW" carte range
    [ "$status" -eq 0 ]
    [ -f "$CARTE" ]
    # À jour : pas réécrite
    touch -t 202001010000 "$CARTE" "$(git rev-parse --git-path index)" lib/outil.sh bin/outil notes.txt README.md
    touch -t 202101010000 "$CARTE"
    run "$RW" carte range
    [ "$status" -eq 0 ]
    [ -z "$(find "$CARTE" -newermt 2022-01-01)" ]
    # Fichier modifié après la carte : régénérée, nouvelle fonction vue
    printf '# Ajoutée apres la carte\nneuve() { :; }\n' >>lib/outil.sh
    touch -t 202001010000 "$CARTE"
    run "$RW" carte neuve
    [ "$status" -eq 0 ]
    [[ "$output" == *"neuve  lib/outil.sh:15"* ]] || false
}

@test "carte : fichier en CRLF (Windows) -> commentaire sans retour chariot" {
    printf '#!/usr/bin/env bash\r\n# Texte du pourquoi\r\ncr() { :; }\r\n' >crlf.sh
    git add crlf.sh
    git commit -q --no-verify -m "feat: crlf"
    "$RW" carte >/dev/null
    [ "$(jq -r '.fichiers["crlf.sh"].fonctions[0].pourquoi' "$CARTE")" = "Texte du pourquoi" ]
}
