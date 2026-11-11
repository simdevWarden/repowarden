#!/usr/bin/env bats
# ci/aligner-develop.sh : develop alignee sur main apres une livraison (mode tag)
# Faux git et faux gh : pas de reseau, pas de poussée reelle.

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../ci/aligner-develop.sh"

setup() {
    setup_repo
    mkdir -p "$BATS_TEST_TMPDIR/nohooks" "$BATS_TEST_TMPDIR/bin"
    git config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
    git config --unset repowarden.skip
    initial_commit
    git push -q origin main
    git switch -q -c develop
    git push -q origin develop
    git switch -q main
    export GH_REPO=o/r INTEGRATION=develop MAIN=main
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    : >"$GIT_LOG" ; : >"$GH_LOG"
    # Etat factice des branches lointaines, controle par les tests
    export DEV_SHA="dev-sha" MAIN_SHA="main-sha" DEV_ANCESTOR_MAIN=1
}

# Faux git : journalise, pilote merge-base --is-ancestor et rev-parse,
# accepte le push rapide, refuse tout --force
faux_git() {
    cat >"$BATS_TEST_TMPDIR/bin/git" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GIT_LOG"
case "$*" in
    *"fetch"*)
        if [ -n "${FETCH_REFUSE:-}" ]; then
            echo "fatal: unable to access remote" >&2
            exit 128
        fi ;;
    *"merge-base --is-ancestor"*) [ "$DEV_ANCESTOR_MAIN" = 1 ] || exit 1 ;;
    "rev-parse origin/develop") echo "$DEV_SHA" ;;
    "rev-parse origin/main") echo "$MAIN_SHA" ;;
    *"push origin origin/main:refs/heads/develop"*)
        # push refuse si $PUSH_REFUSE (ruleset sans bypass de l'App)
        if [ -n "${PUSH_REFUSE:-}" ]; then
            echo "remote: error: GH013: Repository rule violations found" >&2
            exit 1
        fi ;;
    *) exit 0 ;;
esac
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Faux gh : gere la requete d'identifiants du fetch (jamais appelee vraiment,
# git etant factice) et journalise.
faux_gh() {
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
    "auth git-credential") printf 'protocol=https\nhost=github.com\nusername=x\npassword=token\n' ;;
    *) exit 0 ;;
esac
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

poussee() { grep -q "push origin origin/main:refs/heads/develop" "$GIT_LOG"; }
force() { grep -q -- "--force" "$GIT_LOG"; }

@test "aligner-develop : develop egal a main -> deja alignee, pas de push" {
    require python3
    faux_git
    faux_gh
    DEV_SHA="main-sha" DEV_ANCESTOR_MAIN=1
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deja alignee sur main"* ]] || false
    ! poussee
    ! force
}

@test "aligner-develop : develop ancetre de main -> pousse sans --force" {
    require python3
    faux_git
    faux_gh
    DEV_SHA="dev-sha" MAIN_SHA="main-sha" DEV_ANCESTOR_MAIN=1
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alignee sur main"* ]] || false
    poussee
    ! force
}

@test "aligner-develop : le push porte les identifiants de l'App (credential.helper)" {
    require python3
    faux_git
    faux_gh
    DEV_SHA="dev-sha" MAIN_SHA="main-sha" DEV_ANCESTOR_MAIN=1
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "credential.helper=!gh auth git-credential push origin origin/main:refs/heads/develop" "$GIT_LOG"
}

@test "aligner-develop : develop a avance sur main -> pas de push, jamais --force" {
    require python3
    faux_git
    faux_gh
    DEV_SHA="dev-sha" MAIN_SHA="main-sha" DEV_ANCESTOR_MAIN=0
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"aucun rattrapage automatique"* ]] || false
    ! poussee
    ! force
}

@test "aligner-develop : push refuse -> code 0, avertissement avec la raison, resume" {
    require python3
    faux_git
    faux_gh
    export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary"
    : >"$GITHUB_STEP_SUMMARY"
    DEV_SHA="dev-sha" MAIN_SHA="main-sha" DEV_ANCESTOR_MAIN=1 PUSH_REFUSE=1 run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::develop non alignee sur main"* ]] || false
    [[ "$output" == *"GH013: Repository rule violations"* ]] || false
    grep -q "develop non alignee sur main" "$GITHUB_STEP_SUMMARY"
    poussee
    ! force
}

@test "aligner-develop : fetch en echec -> code 0, avertissement, aucun push" {
    require python3
    faux_git
    faux_gh
    export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/summary"
    : >"$GITHUB_STEP_SUMMARY"
    FETCH_REFUSE=1 run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::develop non alignee sur main : fetch refuse"* ]] || false
    [[ "$output" == *"unable to access remote"* ]] || false
    grep -q "fetch refuse" "$GITHUB_STEP_SUMMARY"
    ! poussee
    ! force
}

@test "release-auto : job aligner-develop apres le job tag, jeton App, pas de --force" {
    local wf="$BATS_TEST_DIRNAME/../.github/workflows/release-auto.yml"
    run grep -q 'bash .repowarden-ci/ci/aligner-develop.sh' "$wf"
    [ "$status" -eq 0 ]
    # aligner-develop vient apres le job qui pose le tag (tag)
    awk '
        /^  tag:/ { t = NR }
        /^  aligner-develop:/ { a = NR }
        END { exit !(t && a && t < a) }
    ' "$wf"
    # le job utilise le jeton de l'App, ne force jamais, a le droit d'ecrire
    run grep -q 'create-github-app-token' "$wf"
    [ "$status" -eq 0 ]
    run grep -q '!cancelled()' "$wf"
    [ "$status" -eq 0 ]
    run grep -q 'contents: write' "$wf"
    [ "$status" -eq 0 ]
    # le script pousse la branche principale dans la branche d'integration, jamais --force
    run grep -q 'refs/heads/\$INTEGRATION' "$SCRIPT"
    [ "$status" -eq 0 ]
    ! grep -E -- 'git push.*--force' "$SCRIPT"
}
