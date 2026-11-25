#!/usr/bin/env bats
# repowarden pr body (ticket #601) : remplacer la description d'une PR sans
# gh pr edit à la main. gh est simulé (faux exécutable dans le PATH) : aucun
# accès à GitHub, tout appel est journalisé dans $GH_DIR/log.

load helpers

RW="$BATS_TEST_DIRNAME/../bin/repowarden"

setup() {
    setup_repo
    initial_commit
}

# Faux gh : la PR $1 existe (état $2, titre $3, branche de tête $4, corps
# courant dans $GH_DIR/body) ; gh pr edit copie le fichier reçu dans
# $GH_DIR/ecrit, son chemin dans $GH_DIR/tmp. Pourquoi : vérifier ce qui est
# écrit octet pour octet, sans jamais toucher GitHub.
faux_gh() {
    GH_DIR="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$GH_DIR/bin"
    export GH_DIR
    printf '%s' "${1:-42}" >"$GH_DIR/num"
    printf '%s\n%s\n%s\n' "${2:-OPEN}" "${3:-Mon titre}" "${4:-feat/601-x}" >"$GH_DIR/meta"
    printf '%s' "${5:-Description actuelle}" >"$GH_DIR/body"
    : >"$GH_DIR/log"
    cat >"$GH_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_DIR/log"
case "$1 $2" in
    "auth status") exit 0 ;;
    "pr view")
        [ "$3" = "$(cat "$GH_DIR/num")" ] || { echo "no pull requests found" >&2; exit 1; }
        case "$*" in
            *"--json body"*) cat "$GH_DIR/body" ;;
            *) cat "$GH_DIR/meta" ;;
        esac
        ;;
    "pr edit")
        while [ $# -gt 0 ]; do
            if [ "$1" = "--body-file" ]; then
                printf '%s' "$2" >"$GH_DIR/tmp"
                cp "$2" "$GH_DIR/ecrit"
            fi
            shift
        done
        ;;
esac
exit 0
GH
    chmod +x "$GH_DIR/bin/gh"
}

# Vrai si gh pr edit n'a jamais été appelé
aucune_ecriture() { ! grep -q '^pr edit' "$GH_DIR/log"; }

@test "pr body : remplace la description depuis --file" {
    faux_gh
    printf 'Nouveau texte\nsur deux lignes\n' >"$BATS_TEST_TMPDIR/t.md"
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --file "$BATS_TEST_TMPDIR/t.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    grep -q '^pr edit 42 --body-file ' "$GH_DIR/log"
    cmp "$GH_DIR/ecrit" "$BATS_TEST_TMPDIR/t.md"
    [[ "$output" == *"Description de la PR #42 mise à jour"* ]] || false
}

@test "pr body : remplace la description depuis --text" {
    faux_gh
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text "Texte direct"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(cat "$GH_DIR/ecrit")" = "Texte direct" ]
    [[ "$output" == *"Description de la PR #42 mise à jour"* ]] || false
}

@test "pr body : corps multiligne, guillemets et dollar preserves octet pour octet" {
    faux_gh
    cat >"$BATS_TEST_TMPDIR/t.md" <<'TXT'
## Pourquoi
Il dit "bonjour" et 'salut' ; coût : $5, $HOME, $(date), `ls`, \n littéral.

- puce 1 & puce 2 | pipe > chevron

Fin
TXT
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --file "$BATS_TEST_TMPDIR/t.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    cmp "$GH_DIR/ecrit" "$BATS_TEST_TMPDIR/t.md"
    # --text : mêmes octets, sans retour ligne ajouté
    texte=$'ligne "un"\ncoût $5 $HOME $(date) `ls`\n\\n fin'
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text "$texte"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    printf '%s' "$texte" >"$BATS_TEST_TMPDIR/attendu"
    cmp "$GH_DIR/ecrit" "$BATS_TEST_TMPDIR/attendu"
    # le texte ne passe jamais par la ligne de commande de gh
    ! grep -q 'coût' "$GH_DIR/log" || false
    ! grep -qE -- '--body( |$)' "$GH_DIR/log" || false
}

@test "pr body : le fichier temporaire est supprime apres l'ecriture" {
    faux_gh
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text "Texte"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ -s "$GH_DIR/tmp" ]
    [ ! -e "$(cat "$GH_DIR/tmp")" ]
}

@test "pr body : affiche numero, titre et branche avant d'ecrire" {
    faux_gh 42 OPEN "Ajout du panier" feat/601-panier
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text "Texte"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"#42"*"Ajout du panier"*"feat/601-panier"*"mise à jour"* ]] || false
}

@test "pr body : PR fermee refusee, etat affiche, rien n'est ecrit" {
    faux_gh 42 CLOSED
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text "Texte"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR #42 n'est pas ouverte (état : CLOSED)"* ]] || false
    aucune_ecriture
}

@test "pr body : PR fusionnee refusee, etat affiche, rien n'est ecrit" {
    faux_gh 42 MERGED
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text "Texte"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR #42 n'est pas ouverte (état : MERGED)"* ]] || false
    aucune_ecriture
}

@test "pr body : PR introuvable refusee, rien n'est ecrit" {
    faux_gh 42
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 99 --text "Texte"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR #99 introuvable"* ]] || false
    aucune_ecriture
}

@test "pr body : texte vide refuse (--text vide, espaces, fichier vide)" {
    faux_gh
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"texte de la description est vide"* ]] || false
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text $' \n\t '
    [ "$status" -eq 1 ]
    [[ "$output" == *"texte de la description est vide"* ]] || false
    : >"$BATS_TEST_TMPDIR/vide.md"
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --file "$BATS_TEST_TMPDIR/vide.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"texte de la description est vide"* ]] || false
    aucune_ecriture
}

@test "pr body : fichier absent refuse, rien n'est ecrit" {
    faux_gh
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --file "$BATS_TEST_TMPDIR/absent.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Fichier illisible ou absent"*"absent.md"* ]] || false
    aucune_ecriture
}

@test "pr body : --file et --text ensemble refuses" {
    faux_gh
    printf 'a\n' >"$BATS_TEST_TMPDIR/t.md"
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --file "$BATS_TEST_TMPDIR/t.md" --text "b"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--file et --text s'excluent"* ]] || false
    aucune_ecriture
}

@test "pr body : aucune source de texte refusee" {
    faux_gh
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"Indique le texte"* ]] || false
    aucune_ecriture
}

@test "pr body : numero de PR absent refuse" {
    faux_gh
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body --text "Texte"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Numéro de PR manquant"* ]] || false
    aucune_ecriture
}

@test "pr body : ligne Ticket reprise de l'ancien corps quand le nouveau texte n'en a pas" {
    faux_gh 42 OPEN "T" feat/601-x $'Ancien corps\n\nTicket : #601\n'
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text $'Nouveau pourquoi\nsur deux lignes'
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(tail -n 1 "$GH_DIR/ecrit")" = "Ticket : #601" ]
    [ "$(grep -c '^Ticket : #' "$GH_DIR/ecrit")" -eq 1 ]
    grep -q '^Nouveau pourquoi$' "$GH_DIR/ecrit"
    ! grep -q 'Ancien corps' "$GH_DIR/ecrit" || false
    [[ "$output" == *"Ticket : #601"*"reprise"* ]] || false
}

@test "pr body : ligne Ticket jamais dupliquee quand le nouveau texte a la sienne" {
    faux_gh 42 OPEN "T" feat/601-x $'Ancien\n\nTicket : #601\n'
    printf 'Nouveau\n\nTicket : #602\n' >"$BATS_TEST_TMPDIR/t.md"
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --file "$BATS_TEST_TMPDIR/t.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    cmp "$GH_DIR/ecrit" "$BATS_TEST_TMPDIR/t.md"
    [ "$(grep -c '^Ticket : #' "$GH_DIR/ecrit")" -eq 1 ]
}

@test "pr body : sans ligne Ticket dans l'ancien corps, le texte est ecrit tel quel" {
    faux_gh 42 OPEN "T" feat/601-x "Ancien sans reference"
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text "Nouveau"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(cat "$GH_DIR/ecrit")" = "Nouveau" ]
}

@test "pr body : --dry-run affiche la cible et n'ecrit rien" {
    faux_gh 42 OPEN "Ajout du panier" feat/601-panier $'Ancien\n\nTicket : #601\n'
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body 42 --text "Nouveau" --dry-run
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"#42"*"Ajout du panier"*"feat/601-panier"* ]] || false
    [[ "$output" == *"Simulation"* ]] || false
    aucune_ecriture
    [ ! -e "$GH_DIR/ecrit" ]
}

@test "pr body : #n accepte comme numero" {
    faux_gh
    PATH="$GH_DIR/bin:$PATH" run "$RW" pr body '#42' --text "Texte"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    grep -q '^pr edit 42 --body-file ' "$GH_DIR/log"
    ! grep -q '#42' "$GH_DIR/log" || false
}

@test "pr body : gh absent refuse avec son message" {
    # Le PATH reduit se fait avec des liens symboliques, impossibles sous Git Bash
    case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) skip "liens symboliques absents sous Windows" ;; esac
    faux_gh
    sans="$BATS_TEST_TMPDIR/sans-gh"
    mkdir -p "$sans"
    for o in bash env dirname basename cat grep sed awk mktemp rm cp mkdir tr head tail \
        wc sort uname git cut date id ls readlink printf tee; do
        p="$(command -v "$o" 2>/dev/null || true)"
        case "$p" in /*) ln -s "$p" "$sans/$o" ;; esac
    done
    run "$(command -v env)" PATH="$sans" "$RW" pr body 42 --text "Texte"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GitHub CLI (gh) requis"* ]] || false
}

@test "pr body : aide en francais et en anglais, sans gh" {
    run "$RW" pr body --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"repowarden pr body"*"--file"*"--text"* ]] || false
    REPOWARDEN_LANG=en run "$RW" pr body --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"repowarden pr body"*"replaces"* ]] || false
    run "$RW" pr --help
    [[ "$output" == *"repowarden pr body"* ]] || false
    run "$RW" --help
    [[ "$output" == *"repowarden pr body"* ]] || false
}

@test "pr body : messages en anglais (--dry-run)" {
    faux_gh 42 OPEN "Cart" feat/601-cart
    PATH="$GH_DIR/bin:$PATH" REPOWARDEN_LANG=en run "$RW" pr body 42 --text "Text" --dry-run
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"Dry run"* ]] || false
    aucune_ecriture
}
