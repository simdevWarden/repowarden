#!/usr/bin/env bats
# Aide des commandes (ticket #294) : une seule source (clés help.* des
# catalogues fr/en), --help affiché avant toute action, dans la langue de
# repowarden.lang ; repowarden ticket sans argument dit pourquoi et donne l'usage.

load helpers

RW="$BATS_TEST_DIRNAME/../bin/repowarden"
TICKET="$BATS_TEST_DIRNAME/../bin/ticket"

setup() {
    setup_repo
    initial_commit
}

# gh minimal (l'aide et l'affichage du ticket n'en appellent aucun)
setup_gh() {
    F="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$F/bin"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
exit 0
GH
    chmod +x "$F/bin/gh"
    export FAKE="$F"
}

@test "aide : chaque commande --help donne l'usage (code 0, rien n'est fait)" {
    avant_head="$(git rev-parse HEAD)"
    for cmd in statut install uninstall cc code-mort ticket tickets pr run \
        proteger migrer npm-publication app bots bot agents garde \
        "ticket comment" "ticket label"; do
        run "$RW" $cmd --help
        if [ "$status" -ne 0 ]; then
            echo "repowarden $cmd --help : code $status"
            echo "$output"
            return 1
        fi
        [[ "$output" == *"Usage"* ]] || false
        [[ "$output" == *"repowarden $cmd"* ]] || false
    done
    # Aucune commande n'a agi : ni commit, ni fichier touché
    [ "$(git rev-parse HEAD)" = "$avant_head" ]
    [ -z "$(git status --porcelain)" ]
}

@test "aide : help.main complet (ticket sans argument, tickets sync)" {
    run "$RW" --help
    [ "$status" -eq 0 ]
    grep -q 'repowarden tickets sync' <<<"$output"
    grep -Eq '^  repowarden ticket[[:space:]]+ticket de la branche courante' <<<"$output"
    grep -q 'repowarden code-mort' <<<"$output"
}

@test "aide : version anglaise de repowarden --help et d'une commande" {
    REPOWARDEN_LANG=en run "$RW" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"commit assistant"* ]] || false
    [[ "$output" != *"étape suivante"* ]] || false
    REPOWARDEN_LANG=en run "$RW" statut --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Read-only"* ]] || false
    [[ "$output" != *"Lecture seule"* ]] || false
}

@test "aide : code-mort --help s'arrete avant l'analyse" {
    run "$RW" code-mort --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage : repowarden code-mort"* ]] || false
    [[ "$output" != *"━━"* ]] || false
    [[ "$output" != *"Aucune modification par rapport"* ]] || false
}

@test "aide : statut --help ne lit pas le statut" {
    run "$RW" statut --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage : repowarden statut"* ]] || false
    [[ "$output" != *"Hooks git"* ]] || false
    [[ "$output" != *"Étape suivante"* ]] || false
}

@test "aide : cc --help n'envoie rien dans l'assistant, -m --help reste un message" {
    run "$RW" cc --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage : repowarden cc"* ]] || false
    [[ "$output" != *"1/5"* ]] || false
    git switch -q -c feat/panier
    echo a >a.txt
    git add a.txt
    avant="$(git rev-parse HEAD)"
    run "$RW" cc -m "--help"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Usage :"* ]] || false
    [ "$(git rev-parse HEAD)" != "$avant" ]
    [ "$(subject)" = "feat(panier): --help" ]
}

@test "aide : pr --help et run --help donnent l'aide des sous-commandes" {
    run "$RW" pr --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"repowarden pr label"* ]] || false
    [[ "$output" == *"repowarden pr checks"* ]] || false
    run "$RW" run --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"repowarden run rerun"* ]] || false
    [[ "$output" == *"repowarden run list"* ]] || false
}

@test "aide : feuille traduite (pr-label --help en anglais)" {
    REPOWARDEN_LANG=en run "$BATS_TEST_DIRNAME/../bin/pr-label" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"adds or removes a label"* ]] || false
    [[ "$output" != *"Ajoute ou retire"* ]] || false
}

@test "aide : ticket sans argument, sans ticket -> message, usage, code 1" {
    setup_gh
    git switch -q -c feat/panier
    PATH="$F/bin:$PATH" run "$TICKET"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Aucun ticket pour cette branche"* ]] || false
    [[ "$output" == *"Usage : repowarden ticket"* ]] || false
}

@test "aide : ticket sans argument avec ticket -> branche et ticket affiches" {
    setup_gh
    git switch -q -c feat/12-panier
    PATH="$F/bin:$PATH" run "$TICKET"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Branche feat/12-panier : ticket #12"* ]] || false
}

# Commandes citées dans la doc (ticket #308) : « fichier:ligne:commande
# sous-commande » pour chaque `repowarden …` en code en ligne, et chaque ligne
# de bloc de code qui commence par repowarden (la prose, où repowarden est un
# nom, n'est pas lue). Mots hors [a-z-] (12, <n>, --global, #…) : vides.
doc_commands() {
    awk '
        function out(s,    w) {
            split(s, w, /[[:space:]]+/)
            if (w[2] !~ /^[a-z][a-z-]*$/) return
            if (w[3] !~ /^[a-z][a-z-]*$/) w[3] = ""
            print FILENAME ":" FNR ":" w[2] ":" w[3]
        }
        FNR == 1 { fence = 0 }
        /^[[:space:]]*```/ { fence = !fence; next }
        fence {
            l = $0
            sub(/^[[:space:]]*(\$[[:space:]]+)?(npx[[:space:]]+)?/, "", l)
            if (l ~ /^repowarden[[:space:]]/) out(l)
            next
        }
        {
            l = $0
            while (match(l, /`(npx )?repowarden [^`]*`/)) {
                s = substr(l, RSTART + 1, RLENGTH - 2)
                l = substr(l, RSTART + RLENGTH)
                sub(/^npx /, "", s)
                out(s)
            }
        }' "$@"
}

# Confronte les commandes citées à la CLI, même source que --help : la
# commande doit avoir une aide (help_key_r, alias compris) ; la sous-commande
# n'est vérifiée que si l'aide de la commande en liste (repowarden <cmd> <mot>).
# Un appel --help par commande distincte (lent sous Windows).
check_doc_commands() {
    local ligne fichier num cmd sous vus="" connues="" ko=0 aides="$BATS_TEST_TMPDIR/aides"
    mkdir -p "$aides"
    while IFS= read -r ligne; do
        sous="${ligne##*:}"
        ligne="${ligne%:*}"
        cmd="${ligne##*:}"
        ligne="${ligne%:*}"
        num="${ligne##*:}"
        fichier="${ligne%:*}"
        if [[ " $vus " != *" $cmd "* ]]; then
            vus="$vus $cmd"
            "$RW" "$cmd" --help >"$aides/$cmd" 2>/dev/null && connues="$connues $cmd"
        fi
        if [[ " $connues " != *" $cmd "* ]]; then
            echo "$fichier:$num: repowarden $cmd : commande inconnue de la CLI"
            ko=1
        elif [ -n "$sous" ] && grep -Eq "repowarden $cmd [a-z]" "$aides/$cmd" &&
            ! grep -Eq "repowarden $cmd $sous([^a-z-]|\$)" "$aides/$cmd"; then
            echo "$fichier:$num: repowarden $cmd $sous : sous-commande inconnue de la CLI"
            ko=1
        fi
    done < <(doc_commands "$@")
    return "$ko"
}

@test "aide : doc, chaque commande repowarden citee existe dans la CLI" {
    cd "$BATS_TEST_DIRNAME/.."
    # Le contrôle lit bien la doc (pas un vert par extraction vide)
    run doc_commands README.md
    [[ "$output" == *"README.md:"*":proteger:"* ]] || false
    # shellcheck disable=SC2046
    run check_doc_commands README.md $(find docs -name '*.md')
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "aide : doc, commande inconnue signalee avec fichier et ligne" {
    mkdir -p doc
    cat >doc/guide.md <<'MD'
# Guide

Lancer `repowarden protector --checks x` puis `repowarden ticket 12`.

```bash
repowarden install --global
repowarden tickets synchro
$ npx repowarden app init
```

repowarden protector en prose : ignore.
MD
    run check_doc_commands doc/guide.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"doc/guide.md:3: repowarden protector : commande inconnue"* ]] || false
    [[ "$output" == *"doc/guide.md:7: repowarden tickets synchro : sous-commande inconnue"* ]] || false
    [[ "$output" != *"guide.md:11"* ]] || false
    [[ "$output" != *"install"* ]] || false
    [[ "$output" != *"app"* ]] || false
    [[ "$output" != *"ticket 12"* ]] || false
    [ "$(printf '%s\n' "$output" | grep -c ':')" -eq 2 ]
}

# --- pr checks, run list, --help des sous-commandes (ticket #427) -------------

# gh simulé : journal des appels dans $GH_LOG ; gh pr checks répond le JSON
# de $GH_CHECKS (ce que donne -q '.[] | …' sur la réponse réelle)
setup_gh_log() {
    F="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$F/bin"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
    "pr checks "*) printf '%b' "${GH_CHECKS:-}" ;;
    "repo view "*) echo o/r ;;
esac
exit 0
GH
    chmod +x "$F/bin/gh"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    : >"$GH_LOG"
}

@test "aide : --help de chaque sous-commande de ticket, pr, run (code 0, sans gh)" {
    setup_gh_log
    git switch -q -c feat/panier
    for sous in "ticket nouveau" "ticket 12" "ticket comment" "ticket label" \
        "pr checks" "pr label" "run list" "run rerun"; do
        PATH="$F/bin:$PATH" run "$RW" $sous --help
        if [ "$status" -ne 0 ]; then
            echo "repowarden $sous --help : code $status"
            echo "$output"
            return 1
        fi
        [[ "$output" == *"Usage"* ]] || false
        [[ "$output" != *"Argument inconnu"* ]] || false
    done
    [ ! -s "$GH_LOG" ] || { cat "$GH_LOG"; return 1; }
    [ "$(git symbolic-ref --short HEAD)" = feat/panier ]
}

@test "pr checks : echecs et attentes listes, verdict, code 1 si un job echoue" {
    setup_gh_log
    export GH_CHECKS='pass\tlint\thttps://x/1\nfail\ttests (ubuntu)\thttps://x/2\npending\te2e (go)\thttps://x/3\n'
    PATH="$F/bin:$PATH" run "$RW" pr checks 42
    [ "$status" -eq 1 ]
    grep -q '^pr checks 42 ' "$GH_LOG"
    ! grep -q 'check-runs' "$GH_LOG"
    [[ "$output" == *"tests (ubuntu)"*"https://x/2"* ]] || false
    [[ "$output" == *"e2e (go)"* ]] || false
    [[ "$output" == *"1 réussi(s), 1 en échec, 1 en attente"* ]] || false
    [[ "$output" != *"lint"* ]] || false
}

@test "pr checks : tout vert -> verdict et code 0" {
    setup_gh_log
    export GH_CHECKS='pass\tlint\thttps://x/1\nskipping\tdeploy\thttps://x/4\n'
    PATH="$F/bin:$PATH" run "$RW" pr checks 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tous les checks de la PR #42 sont verts"* ]] || false
}

@test "run list : sans argument -> runs recents de tous les workflows" {
    setup_gh_log
    PATH="$F/bin:$PATH" run "$RW" run list
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"unbound variable"* ]] || false
    grep -q '^run list --repo o/r --limit 20 ' "$GH_LOG"
    ! grep -q -- '--workflow' "$GH_LOG"
    # identifiants entiers (--jq), pas en notation scientifique (--template)
    grep -q -- '--jq' "$GH_LOG"
    ! grep -q -- '--template' "$GH_LOG"
}
