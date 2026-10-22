#!/usr/bin/env bats
# Langue du projet pour le suivi des tickets (ci/langue-projet.sh) : gh simulé,
# fichiers de réglages servis depuis $FAKE/<nom du fichier>

load helpers

LANGUE="$BATS_TEST_DIRNAME/../ci/langue-projet.sh"

setup() {
    F="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$F/bin"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
# gh simulé : api repos/o/r/contents/<fichier> sert $FAKE/<fichier>, sinon 404
echo "$*" >>"$FAKE/log"
for a in "$@"; do
    case "$a" in
        repos/o/r/contents/*)
            f="$FAKE/${a#repos/o/r/contents/}"
            [ -f "$f" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
            cat "$f"; exit 0 ;;
    esac
done
exit 1
GH
    chmod +x "$F/bin/gh"
    export FAKE="$F" PATH="$F/bin:$PATH" GH_REPO=o/r
    unset LANG_INPUT REPOWARDEN_LANG
}

@test "langue projet : lang = fr du .repowarden.conf lue par l'API" {
    printf '[repowarden]\n    integrationBranch = develop\n    lang = fr\n' >"$F/.repowarden.conf"
    run bash "$LANGUE"
    [ "$status" -eq 0 ]
    [ "$output" = fr ]
    grep -q 'repos/o/r/contents/.repowarden.conf' "$F/log"
}

@test "langue projet : sans lang, rien (la CI garde l'anglais)" {
    printf '[repowarden]\n    integrationBranch = develop\n' >"$F/.repowarden.conf"
    run bash "$LANGUE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "langue projet : fichier absent ou API en echec, rien et code 0" {
    run bash "$LANGUE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "langue projet : ancien .repogarde.conf lu, le nouveau l'emporte" {
    printf '[repogarde]\n    lang = fr\n' >"$F/.repogarde.conf"
    run bash "$LANGUE"
    [ "$output" = fr ]
    printf '[repowarden]\n    lang = en\n' >"$F/.repowarden.conf"
    run bash "$LANGUE"
    [ "$output" = en ]
}

@test "langue projet : entree lang du workflow prioritaire, sans appel a l'API" {
    printf '[repowarden]\n    lang = en\n' >"$F/.repowarden.conf"
    LANG_INPUT=fr run bash "$LANGUE"
    [ "$output" = fr ]
    [ ! -e "$F/log" ]
}

@test "langue projet : le pied du bot suit la langue lue (fr), anglais sans lang" {
    printf '[repowarden]\n    lang = fr\n' >"$F/.repowarden.conf"
    # hors de tout dépôt, sans config git globale : comme le job tickets en CI
    cd "$BATS_TEST_TMPDIR"
    run env CI=true GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 REPOWARDEN_LANG="$(bash "$LANGUE")" bash -c \
        'source "$1/hooks/lib/common.sh"; t tk.footer x; echo "$REPLY"' _ "$BATS_TEST_DIRNAME/.."
    [[ "$output" == *"Commentaire automatique de"* ]] || false
    [[ "$output" != *"Automated comment from"* ]] || false
    rm "$F/.repowarden.conf"
    run env CI=true GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 REPOWARDEN_LANG="$(bash "$LANGUE")" bash -c \
        'source "$1/hooks/lib/common.sh"; t tk.footer x; echo "$REPLY"' _ "$BATS_TEST_DIRNAME/.."
    [[ "$output" == *"Automated comment from"* ]] || false
}

@test "langue projet : tickets.yml passe la langue du projet a l'etape Tickets" {
    f="$BATS_TEST_DIRNAME/../.github/workflows/tickets.yml"
    # entrée lang du workflow, transmise au script, langue exportée avant tickets.sh
    grep -q '^      lang:$' "$f"
    grep -q 'LANG_INPUT: ${{ inputs.lang }}' "$f"
    awk '/REPOWARDEN_LANG="\$\(bash .repowarden-ci\/ci\/langue-projet.sh\)"/ { l = NR } /tickets.sh pr$/ { t = NR } END { exit !(l && t && l < t) }' "$f"
}
