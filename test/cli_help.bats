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
        proteger migrer npm-publication app bots bot \
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
