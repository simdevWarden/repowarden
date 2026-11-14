#!/usr/bin/env bats
# Carte du projet (repowarden map) : fonctions, leur « pourquoi » (le
# commentaire juste au-dessus), dans .repowarden/carte/carte.json

load helpers

RW="$BATS_TEST_DIRNAME/../bin/repowarden"
CARTE=.repowarden/carte/carte.json

setup() {
    require jq
    setup_repo
    initial_commit
    git switch -q -c feat/1-carte
    faux_gh
}

# Faux gh en tête du PATH : aucun test n'appelle le vrai (ni réseau). Appels
# journalisés dans $GH_LOG ; connecté si $GH_CONNECTE=1 ; issue list renvoie
# le fichier $GH_ISSUES
faux_gh() {
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log" GH_ISSUES="$BATS_TEST_TMPDIR/issues.json"
    mkdir -p "$BATS_TEST_TMPDIR/faux"
    cat >"$BATS_TEST_TMPDIR/faux/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$1 ${2:-}" in
    "auth token") [ "${GH_CONNECTE:-}" = 1 ] && echo jeton-de-test && exit 0; exit 1 ;;
    "issue list") cat "$GH_ISSUES" ;;
    *) exit 1 ;;
esac
GH
    chmod +x "$BATS_TEST_TMPDIR/faux/gh"
    export PATH="$BATS_TEST_TMPDIR/faux:$PATH"
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
    run "$RW" map
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
    run "$RW" map
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 fichier(s), 4 fonction(s), dont 1 sans commentaire"* ]] || false
    [[ "$output" == *".repowarden/carte/carte.json"* ]] || false
}

@test "carte : deux lancements donnent un fichier identique" {
    projet_shell
    "$RW" map >/dev/null
    cp "$CARTE" "$BATS_TEST_TMPDIR/premiere.json"
    touch lib/outil.sh
    "$RW" map >/dev/null
    cmp "$BATS_TEST_TMPDIR/premiere.json" "$CARTE"
}

@test "carte : dossier de la carte ignore par git, jamais versionne" {
    projet_shell
    "$RW" map >/dev/null
    [ -z "$(git status --porcelain)" ]
    [ "$(cat .repowarden/carte/.gitignore)" = "*" ]
}

@test "carte : repowarden.exclude respecte" {
    projet_shell
    git config repowarden.exclude "bin/*"
    "$RW" map >/dev/null
    run jq -r '.fichiers | keys[]' "$CARTE"
    [ "$output" = "lib/outil.sh" ]
}

@test "carte : lancee depuis un sous-dossier, chemins depuis la racine" {
    projet_shell
    cd lib
    "$RW" map >/dev/null
    cd ..
    [ -f "$CARTE" ]
    [ ! -e lib/.repowarden ]
    jq -e '.fichiers["lib/outil.sh"]' "$CARTE" >/dev/null
}

@test "carte : hors depot git -> erreur claire" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p hors && cd hors
    run "$RW" map
    [ "$status" -ne 0 ]
    [[ "$output" == *"dépôt git"* ]] || false
}

@test "carte : --help en francais et en anglais" {
    run "$RW" map --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage : repowarden map"* ]] || false
    [ ! -e "$CARTE" ]
    REPOWARDEN_LANG=en run "$RW" map --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: repowarden map"* ]] || false
    REPOWARDEN_LANG=en run "$RW" map
    [[ "$output" == *"function(s)"* ]] || false
}

# Dépôt de test avec une copie du vrai bin/guard de repowarden
projet_garde() {
    mkdir -p bin
    cp "$BATS_TEST_DIRNAME/../bin/guard" bin/guard
    git add bin/guard
    git commit -q --no-verify -m "feat: garde"
}

@test "carte : fichier -> ses fonctions et leurs commentaires" {
    projet_garde
    run "$RW" map bin/guard
    [ "$status" -eq 0 ]
    [[ "$output" == *"bin/guard"* ]] || false
    ligne="$(grep -n '^verifier_gh()' bin/guard | cut -d: -f1)"
    [[ "$output" == *"$ligne  verifier_gh — "* ]] || false
    [[ "$output" == *"dossier_r — REPLY = dossier existant le plus proche"* ]] || false
}

@test "carte : fonction -> fichier, ligne, commentaire ; inconnue -> code 1" {
    projet_garde
    ligne="$(grep -n '^verifier_gh()' bin/guard | cut -d: -f1)"
    run "$RW" map verifier_gh
    [ "$status" -eq 0 ]
    [[ "$output" == *"verifier_gh  bin/guard:$ligne"* ]] || false
    pourquoi="$(sed -n "$((ligne - 1))p" bin/guard | sed 's/^# *//')"
    [[ "$output" == *"$pourquoi"* ]] || false
    run "$RW" map fonction_inconnue
    [ "$status" -eq 1 ]
    [[ "$output" == *"fonction_inconnue"*"ni un fichier ni une fonction de la carte"* ]] || false
}

@test "carte : --json du fichier et de la fonction, valide" {
    projet_shell
    run "$RW" map lib/outil.sh --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.fichier' <<<"$output")" = lib/outil.sh ]
    [ "$(jq -r '.fonctions[0].nom' <<<"$output")" = range ]
    run "$RW" map --json vide
    [ "$status" -eq 0 ]
    [ "$(jq -c '.' <<<"$output")" = '[{"fichier":"lib/outil.sh","ligne":10,"nom":"vide","pourquoi":"Vide le cache, sinon il grossit sans fin"}]' ]
    run "$RW" map --json
    [ "$status" -eq 0 ]
    jq -e '.fichiers["bin/outil"]' <<<"$output" >/dev/null
}

@test "carte : fichier depuis un sous-dossier, sans fonction, sans commentaire" {
    projet_shell
    cd lib
    run "$RW" map outil.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"lib/outil.sh"* ]] || false
    [[ "$output" == *"13  nu (sans commentaire)"* ]] || false
    cd ..
    run "$RW" map notes.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"notes.txt : aucune fonction"* ]] || false
}

@test "carte : absente ou perimee -> regeneree avant de repondre, a jour -> gardee" {
    projet_shell
    run "$RW" map range
    [ "$status" -eq 0 ]
    [ -f "$CARTE" ]
    # À jour : pas réécrite
    touch -t 202001010000 "$CARTE" "$(git rev-parse --git-path index)" lib/outil.sh bin/outil notes.txt README.md
    touch -t 202101010000 "$CARTE"
    run "$RW" map range
    [ "$status" -eq 0 ]
    [ -z "$(find "$CARTE" -newermt 2022-01-01)" ]
    # Fichier modifié après la carte : régénérée, nouvelle fonction vue
    printf '# Ajoutée apres la carte\nneuve() { :; }\n' >>lib/outil.sh
    touch -t 202001010000 "$CARTE"
    run "$RW" map neuve
    [ "$status" -eq 0 ]
    [[ "$output" == *"neuve  lib/outil.sh:15"* ]] || false
}

@test "carte : fichier -> ses tests (nommage) et la commande pour les lancer" {
    projet_garde
    mkdir -p test
    printf '#!/usr/bin/env bats\n@test "x" { true; }\n' >test/guard.bats
    git add test/guard.bats
    git commit -q --no-verify -m "test: guard"
    run "$RW" map bin/guard
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tests : test/guard.bats"* ]] || false
    [[ "$output" == *"bats test/guard.bats"* ]] || false
}

@test "carte : tests lies par chemin cite et par commande repowarden, noms voisins ignores" {
    projet_shell
    printf '#!/bin/sh\n# Variante\nv() { :; }\n' >bin/outil2
    printf '# Copie\nb() { :; }\n' >lib/outil.sh.bak
    mkdir -p test
    printf '#!/usr/bin/env bats\nS="$BATS_TEST_DIRNAME/../lib/outil.sh"\n@test "a" { true; }\n' >test/chemins.bats
    printf '#!/usr/bin/env bats\n@test "b" { run repowarden outil --help; }\n' >test/commande.bats
    git add -A
    git commit -q --no-verify -m "test: liens"
    "$RW" map >/dev/null
    [ "$(jq -c '.fichiers["lib/outil.sh"].tests' "$CARTE")" = '["test/chemins.bats"]' ]
    [ "$(jq -c '.fichiers["bin/outil"].tests' "$CARTE")" = '["test/commande.bats"]' ]
    [ "$(jq -c '.fichiers["bin/outil2"].tests' "$CARTE")" = '[]' ]
}

@test "carte : fichier sans test signale, --json avec tests vides" {
    projet_shell
    run "$RW" map lib/outil.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucun test trouvé pour lib/outil.sh"* ]] || false
    run "$RW" map lib/outil.sh --json
    [ "$(jq -c '.tests' <<<"$output")" = '[]' ]
}

# Historique avec tickets : pieds « Ticket : #n », fusion d'une branche fix/40-x
projet_tickets() {
    mkdir -p lib
    printf '#!/usr/bin/env bash\n# Somme\na() { :; }\n' >lib/a.sh
    echo doc >>README.md
    git add -A
    git commit -q --no-verify -m "feat: a" -m "Ticket : #12"
    printf '# Produit\nb() { :; }\n' >>lib/a.sh
    printf '#!/usr/bin/env bash\n# Autre\nc() { :; }\n' >lib/c.sh
    git add -A
    git commit -q --no-verify -m "feat: b" -m "Corps." -m "Ticket : #30"
    git switch -q -c fix/40-x
    echo fusion >fusion.txt
    git add fusion.txt
    git commit -q --no-verify -m "fix: sans pied"
    git switch -q feat/1-carte
    git merge -q --no-ff --no-verify -m "Merge branch 'fix/40-x'" fix/40-x
}

@test "carte : ticket -> fichiers modifies ; fichier -> ses tickets (git seul)" {
    projet_tickets
    run "$RW" map '#12'
    [ "$status" -eq 0 ]
    [[ "$output" == *"lib/a.sh"* ]] || false
    [[ "$output" == *"README.md"* ]] || false
    [[ "$output" != *"lib/c.sh"* ]] || false
    run "$RW" map lib/a.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tickets : #12 #30"* ]] || false
    run "$RW" map README.md
    [[ "$output" == *"Tickets : #12"* ]] || false
    run "$RW" map fusion.txt
    [[ "$output" == *"Tickets : #40"* ]] || false
    run "$RW" map '#40' --json
    [ "$status" -eq 0 ]
    [ "$(jq -c . <<<"$output")" = '{"fichiers":["fusion.txt"],"ticket":40}' ]
    run "$RW" map '#99'
    [ "$status" -eq 1 ]
    [[ "$output" == *"#99"* ]] || false
}

@test "carte : tickets sans appel reseau (gh non connecte, aucune lecture gh)" {
    projet_tickets
    "$RW" map >/dev/null
    [[ "$(cat "$GH_LOG")" != *"issue"* ]] || false
    [ "$(jq -c '.tickets["12"].fichiers' "$CARTE")" = '["README.md","lib/a.sh"]' ]
    [ "$(jq -c '.fichiers["lib/a.sh"].tickets' "$CARTE")" = '[12,30]' ]
}

@test "carte : fichier en CRLF (Windows) -> commentaire sans retour chariot" {
    printf '#!/usr/bin/env bash\r\n# Texte du pourquoi\r\ncr() { :; }\r\n' >crlf.sh
    git add crlf.sh
    git commit -q --no-verify -m "feat: crlf"
    "$RW" map >/dev/null
    [ "$(jq -r '.fichiers["crlf.sh"].fonctions[0].pourquoi' "$CARTE")" = "Texte du pourquoi" ]
}

# Réponse de « gh issue list » : ticket 12 avec conception et ajout de
# mainteneur, commentaire d'un tiers ignoré ; ticket 30 sans conception
issues_simulees() {
    cat >"$GH_ISSUES" <<'JSON'
[{"number":12,"comments":[
  {"authorAssociation":"OWNER","body":"## Conception retenue\n\n### Ce qui change\n\n- Somme des paniers dans lib/a.sh\n\n### Tests prévus\n\n- un test\n\n### Hors périmètre\n\nLes remises."},
  {"authorAssociation":"NONE","body":"## Conception retenue\n\n### Ce qui change\n\n- Avis d un tiers"},
  {"authorAssociation":"MEMBER","body":"**Ajout** : arrondi au centime."}]},
 {"number":30,"comments":[{"authorAssociation":"OWNER","body":"Merci"}]}]
JSON
}

@test "carte : conception des tickets lue par gh, citee par ticket et par fichier" {
    projet_tickets
    issues_simulees
    export GH_CONNECTE=1
    run "$RW" map '#12'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conception :"* ]] || false
    [[ "$output" == *"Somme des paniers dans lib/a.sh"* ]] || false
    [[ "$output" == *"Les remises."* ]] || false
    [[ "$output" == *"arrondi au centime"* ]] || false
    [[ "$output" != *"Avis d un tiers"* ]] || false
    [[ "$output" != *"un test"* ]] || false
    run "$RW" map lib/a.sh
    [[ "$output" == *"#12 — "*"Somme des paniers dans lib/a.sh"* ]] || false
    [[ "$output" != *"#30 — "* ]] || false
    jq -e '.tickets["30"] | has("conception") | not' "$CARTE" >/dev/null
    [ "$(cat .repowarden/carte/conception/30.md)" = "" ]
    git status --porcelain | grep -q . && return 1
    true
}

@test "carte : second lancement servi par le cache, sans appel gh" {
    projet_tickets
    issues_simulees
    export GH_CONNECTE=1
    "$RW" map >/dev/null
    [ "$(grep -c '^issue list' "$GH_LOG")" = 1 ]
    : >"$GH_LOG"
    "$RW" map >/dev/null
    run "$RW" map '#12' --json
    [ "$status" -eq 0 ]
    [[ "$(jq -r .conception <<<"$output")" == *"Somme des paniers"* ]] || false
    [ ! -s "$GH_LOG" ]
}

@test "carte : gh non connecte -> avertissement, code 0, sans conception" {
    projet_tickets
    run "$RW" map
    [ "$status" -eq 0 ]
    [[ "$output" == *"carte sans la conception des tickets"* ]] || false
    jq -e '.tickets["12"] | has("conception") | not' "$CARTE" >/dev/null
    touch lib/a.sh
    "$RW" map '#12' --json 2>/dev/null | jq -e '.fichiers' >/dev/null
}

# Poste prêt (hooks et git cc du dépôt, garde-fou branché) : seule la carte
# peut donner l'étape suivante de statut
poste_pret() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    git config --unset core.hooksPath
    "$BATS_TEST_DIRNAME/../install.sh" --lang fr >/dev/null
    garde_branche
}

@test "carte : statut -> perimee signalee, etape suivante repowarden map" {
    poste_pret
    projet_shell
    run "$RW" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Carte du projet absente"*"repowarden map"* ]] || false
    [[ "$output" != *"Étape suivante : repowarden map"* ]] || false
    "$RW" map >/dev/null
    run "$RW" status
    [[ "$output" == *"Carte du projet à jour"* ]] || false
    printf '# Nouvelle\nneuve() { :; }\n' >>lib/outil.sh
    touch -t 202001010000 "$CARTE"
    run "$RW" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Carte du projet périmée"* ]] || false
    [[ "$output" == *"Étape suivante : repowarden map"* ]] || false
}

@test "carte : post-merge -> carte existante recalculee hors ligne, sinon rien" {
    projet_shell
    git switch -q -c feat/2-autre
    printf '# Fusionnee\nfusion() { :; }\n' >>lib/outil.sh
    git commit -q --no-verify -am "feat: fusion" -m "Ticket : #2"
    git switch -q feat/1-carte
    # Sans carte : rien n'est créé
    git merge -q --no-ff --no-verify -m "Merge branch 'feat/2-autre'" feat/2-autre
    [ ! -e "$CARTE" ]
    git reset -q --hard HEAD~1
    "$RW" map >/dev/null
    touch -t 202001010000 "$CARTE"
    export GH_CONNECTE=1
    : >"$GH_LOG"
    git merge -q --no-ff --no-verify -m "Merge branch 'feat/2-autre'" feat/2-autre
    jq -e '.fichiers["lib/outil.sh"].fonctions[] | select(.nom == "fusion")' "$CARTE" >/dev/null
    [ -z "$(find "$CARTE" -mmin +60)" ]
    [[ "$(cat "$GH_LOG")" != *"issue"* ]] || false
}

@test "carte : post-merge sur une copie de repowarden, duree mesuree" {
    git clone -q "$BATS_TEST_DIRNAME/.." "$BATS_TEST_TMPDIR/copie"
    cd "$BATS_TEST_TMPDIR/copie"
    TIMEFORMAT=%R
    sans="$({ time "$HOOKS/post-merge" >/dev/null 2>&1; } 2>&1)"
    "$RW" map >/dev/null
    touch -t 202001010000 "$CARTE"
    avec="$({ time "$HOOKS/post-merge" >/dev/null 2>&1; } 2>&1)"
    echo "post-merge : ${sans}s sans carte, ${avec}s avec carte" >&3
    [ -z "$(find "$CARTE" -mmin +60)" ]
    # Seuil large (CI lentes, Windows) : le recalcul reste de l'ordre de la seconde
    awk -v a="$avec" -v s="$sans" 'BEGIN { exit !(a - s < 15) }'
}
