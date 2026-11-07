#!/usr/bin/env bats
# ci/check.sh tests : où se lit la déclaration « Tests retirés : … » (#545)

load helpers

CHECK="$BATS_TEST_DIRNAME/../ci/check.sh"

setup() {
    setup_repo
    mkdir -p "$BATS_TEST_TMPDIR/nohooks" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/pr"
    git config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
    git config --unset repowarden.skip
    initial_commit
    printf '@test "a" {\n  true\n}\n@test "b" {\n  true\n}\n' >extra.bats
    git add extra.bats
    git commit -q --no-verify -m "test: deux tests"
    export REPOWARDEN_BASE="$(git rev-parse HEAD)" REPOWARDEN_BRANCH=main
    export REPOWARDEN_BIN="$BATS_TEST_TMPDIR/repowarden-bin"
    mkdir -p "$REPOWARDEN_BIN"
    unset GITHUB_ACTIONS GITHUB_BASE_REF GITHUB_HEAD_REF GITHUB_REF_NAME CI_COMMIT_BRANCH \
        CI_MERGE_REQUEST_SOURCE_BRANCH_NAME CI_MERGE_REQUEST_DIFF_BASE_SHA \
        CI_MERGE_REQUEST_TARGET_BRANCH_NAME REPOWARDEN_TARGET REPOWARDEN_PR_BODY \
        CI_MERGE_REQUEST_DESCRIPTION GITHUB_TOKEN GITHUB_REPOSITORY
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
}

# Faux gh : lit pr/commit-<sha> (numéros de PR du commit) et pr/body-<n>
# (description de la PR) ; journalise chaque appel dans pr/appels
faux_gh() {
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
d="$(dirname "$0")/../pr"
echo "$*" >>"$d/appels"
case "$2" in
    */commits/*/pulls) f="$d/commit-$(basename "$(dirname "$2")")" ;;
    */pulls/*) f="$d/body-$(basename "$2")" ;;
    *) exit 1 ;;
esac
[ ! -f "$f" ] || cat "$f"
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GITHUB_TOKEN=faux GITHUB_REPOSITORY=o/r
}

# Fusionne (--no-ff) une branche qui retire un test ; $1 = nom, $2 = n° de PR
# (vide : aucune), $3 = description de cette PR pour le faux gh
fusion_retrait() {
    git switch -q -c "fix/$1"
    printf '@test "a" {\n  true\n}\n' >extra.bats
    git commit -q --no-verify -am "test: retire b ($1)"
    git switch -q main
    git merge -q --no-ff --no-verify -m "Merge $1" "fix/$1"
    if [ -n "$2" ]; then
        echo "$2" >"$BATS_TEST_TMPDIR/pr/commit-$(git rev-parse HEAD)"
        printf '%s\n' "$3" >"$BATS_TEST_TMPDIR/pr/body-$2"
    fi
}

@test "tests declares : la description de la PR suffit" {
    fusion_retrait un "" ""
    run "$CHECK" tests
    [ "$status" -ne 0 ]
    REPOWARDEN_PR_BODY=$'Corrige.\n\nTests retirés : doublon' run "$CHECK" tests
    [ "$status" -eq 0 ]
}

@test "tests declares : une ligne dans un message de commit vaut declaration" {
    git switch -q -c fix/x
    printf '@test "a" {\n  true\n}\n' >extra.bats
    git commit -q --no-verify -am "test: retire b" -m "Tests retirés : doublon de a"
    run "$CHECK" tests
    [ "$status" -eq 0 ]
}

@test "tests declares : push apres fusion, la PR fusionnee declare (faux gh)" {
    faux_gh
    fusion_retrait un 7 $'Retire b.\n\nTests retirés : doublon'
    run "$CHECK" tests
    [ "$status" -eq 0 ]
    grep -q 'pulls/7' "$BATS_TEST_TMPDIR/pr/appels"
}

@test "tests declares : livraison de deux fusions dont une declare (faux gh)" {
    faux_gh
    fusion_retrait un 7 "Retire b, sans raison."
    printf '@test "a" {\n  true\n}\n@test "c" {\n  true\n}\n' >extra2.bats
    git add extra2.bats
    git commit -q --no-verify -m "test: deux autres"
    git switch -q -c fix/deux
    printf '@test "c" {\n  true\n}\n' >extra2.bats
    git commit -q --no-verify -am "test: retire a"
    git switch -q main
    git merge -q --no-ff --no-verify -m "Merge deux" fix/deux
    echo 8 >"$BATS_TEST_TMPDIR/pr/commit-$(git rev-parse HEAD)"
    printf 'Retire a.\n\nTests removed: duplicate\n' >"$BATS_TEST_TMPDIR/pr/body-8"
    run "$CHECK" tests
    [ "$status" -eq 0 ]
}

@test "tests declares : aucune declaration nulle part, retrait refuse" {
    faux_gh
    fusion_retrait un 7 "Retire b, sans raison."
    run "$CHECK" tests
    [ "$status" -ne 0 ]
    [[ "$output" == *"extra.bats : 2 → 1 tests"* ]] || false
    [[ "$output" == *"message de commit"* ]] || false
}

@test "tests declares : sans gh, seules la PR et les commits sont lus" {
    fusion_retrait un 7 $'Tests retirés : doublon'
    # PATH réduit à l'essentiel, sans gh
    run env PATH="$(dirname "$(command -v git)"):/usr/bin:/bin" GITHUB_TOKEN=x GITHUB_REPOSITORY=o/r "$CHECK" tests
    [ "$status" -ne 0 ]
    [[ "$output" == *"extra.bats : 2 → 1 tests"* ]] || false
}

@test "tests declares : sans jeton, gh n est jamais appele" {
    faux_gh
    unset GITHUB_TOKEN
    fusion_retrait un 7 $'Tests retirés : doublon'
    run "$CHECK" tests
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/pr/appels" ]
}
