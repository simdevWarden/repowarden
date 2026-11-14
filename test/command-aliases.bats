#!/usr/bin/env bats
# Alias de compatibilité (#565) : noms français acceptés, avertissement sur stderr.

load helpers
bats_require_minimum_version 1.5.0

RW="$BATS_TEST_DIRNAME/../bin/repowarden"

setup() {
    setup_repo
    initial_commit
}

@test "command_canonical : mot inconnu rendu tel quel" {
    source "$BATS_TEST_DIRNAME/../hooks/lib/command-aliases.sh"
    [ "$(command_canonical "mot-inconnu")" = "mot-inconnu" ]
    [ "$(command_canonical "")" = "" ]
}

@test "alias : chaque alias donne la meme sortie que le nom anglais (avertissement stderr)" {
    aliases=(
        "statut:status"
        "code-mort:dead-code"
        "carte:map"
        "proteger:protect"
        "migrer:migrate"
        "npm-publication:npm-publish"
        "garde:guard"
    )
    for pair in "${aliases[@]}"; do
        fr="${pair%%:*}"
        en="${pair##*:}"
        run --separate-stderr "$RW" "$fr" --help
        [ "$status" -eq 0 ]
        out_fr="$output"
        err_fr="$stderr"
        run --separate-stderr "$RW" "$en" --help
        [ "$status" -eq 0 ]
        out_en="$output"
        err_en="$stderr"
        [ "$out_fr" = "$out_en" ]
        [[ "$err_fr" == *"ancien nom"* ]] || false
        [ -z "$err_en" ]
    done
}

@test "alias : sous-commandes" {
    # ticket nouveau
    run --separate-stderr "$RW" ticket nouveau --help
    [ "$status" -eq 0 ]
    out1="$output"; err1="$stderr"
    run --separate-stderr "$RW" ticket new --help
    [ "$status" -eq 0 ]
    [ "$out1" = "$output" ]
    [[ "$err1" == *"ancien nom"* ]] || false
    [ -z "$stderr" ]

    # agents retirer
    run --separate-stderr "$RW" agents retirer --help
    [ "$status" -eq 0 ]
    out3="$output"; err3="$stderr"
    run --separate-stderr "$RW" agents remove --help
    [ "$status" -eq 0 ]
    [ "$out3" = "$output" ]
    [[ "$err3" == *"ancien nom"* ]] || false
    [ -z "$stderr" ]

    # bot rapport
    run --separate-stderr "$RW" bot rapport --help
    [ "$status" -eq 0 ]
    out5="$output"; err5="$stderr"
    run --separate-stderr "$RW" bot report --help
    [ "$status" -eq 0 ]
    [ "$out5" = "$output" ]
    [[ "$err5" == *"ancien nom"* ]] || false
    [ -z "$stderr" ]
}

@test "alias : nom anglais n'avertit pas" {
    run --separate-stderr "$RW" status --help
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}
