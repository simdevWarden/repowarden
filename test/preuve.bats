#!/usr/bin/env bats
# Preuve du comparatif (ticket #169) : chaque scénario du jeu fautif donne, côté
# repowarden, le résultat publié dans docs/pourquoi.md. Hors ligne et avec les
# hooks de ce dépôt ; ci/preuve.sh prépare son propre dépôt jetable.

load helpers

PREUVE="$BATS_TEST_DIRNAME/../ci/preuve.sh"

@test "preuve : script present et executable" {
    [ -x "$PREUVE" ]
}

@test "preuve : message non conforme bloque" {
    run "$PREUVE" --scenario message-non-conforme
    [ "$status" -eq 0 ]
    [[ "$output" == *$'message-non-conforme\tbloque'* ]] || false
}

@test "preuve : commit direct sur main bloque" {
    run "$PREUVE" --scenario commit-sur-main
    [ "$status" -eq 0 ]
    [[ "$output" == *$'commit-sur-main\tbloque'* ]] || false
}

@test "preuve : mauvais nom de branche bloque" {
    run "$PREUVE" --scenario mauvais-nom-branche
    [ "$status" -eq 0 ]
    [[ "$output" == *$'mauvais-nom-branche\tbloque'* ]] || false
}

@test "preuve : secret bloque" {
    run "$PREUVE" --scenario secret
    [ "$status" -eq 0 ]
    [[ "$output" == *$'secret\tbloque'* ]] || false
}

@test "preuve : .env non ignore avertit sans bloquer" {
    run "$PREUVE" --scenario env-non-ignore
    [ "$status" -eq 0 ]
    [[ "$output" == *$'env-non-ignore\taverti'* ]] || false
}

@test "preuve : fichier mal formate corrige et commit passe" {
    run "$PREUVE" --scenario format
    [ "$status" -eq 0 ]
    [[ "$output" == *$'format\tpasse'* ]] || false
}

@test "preuve : test casse au push bloque" {
    run "$PREUVE" --scenario test-casse-push
    [ "$status" -eq 0 ]
    [[ "$output" == *$'test-casse-push\tbloque'* ]] || false
}

@test "preuve : message invalide decouvert au push bloque" {
    run "$PREUVE" --scenario message-invalide-push
    [ "$status" -eq 0 ]
    [[ "$output" == *$'message-invalide-push\tbloque'* ]] || false
}

@test "preuve : fonction sans commentaire avertit sans bloquer" {
    run "$PREUVE" --scenario fonction-sans-commentaire
    [ "$status" -eq 0 ]
    [[ "$output" == *$'fonction-sans-commentaire\taverti'* ]] || false
}

@test "preuve : force push d'un agent bloque" {
    require jq
    run "$PREUVE" --scenario force-push-agent
    [ "$status" -eq 0 ]
    [[ "$output" == *$'force-push-agent\tbloque'* ]] || false
}
