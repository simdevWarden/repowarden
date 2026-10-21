#!/usr/bin/env bats
# Commandes qui appellent gh, lancées pour de vrai contre un dépôt GitHub de
# test : les tests de test/*.bats simulent gh et ne voient pas un appel que
# GitHub refuse (404 de pr checks, run list sans argument, #427).
#
# Hors de « bats test/ » (sous-dossier) : lancé par integration-gh.yml, ou à
# la main avec un gh connecté :
#   REPOWARDEN_IT_REPO=propriétaire/nom bats test/gh/
# Le dépôt est remis à zéro à chaque passage (tickets et PR fermés, branches
# supprimées) : il doit porter le topic repowarden-it, sinon rien n'est fait.
# Les tests étiquetés defaut-427 échouent tant que #427 n'est pas fusionné.

LABEL=repowarden-it

# Ferme tickets et PR ouverts, supprime toute branche hors branche par défaut :
# chaque passage part du même état, quel qu'ait été la fin du précédent.
remise_a_zero() {
    local n b
    for n in $(gh issue list --repo "$IT_REPO" --state open --limit 200 --json number --jq '.[].number'); do
        gh issue close "$n" --repo "$IT_REPO" >/dev/null
    done
    for n in $(gh pr list --repo "$IT_REPO" --state open --limit 200 --json number --jq '.[].number'); do
        gh pr close "$n" --repo "$IT_REPO" >/dev/null
    done
    for b in $(gh api --paginate "repos/$IT_REPO/branches" --jq '.[].name'); do
        [ "$b" = "$IT_DEFAUT" ] || gh api -X DELETE "repos/$IT_REPO/git/refs/heads/$b" >/dev/null
    done
}

# Sans dépôt de test configuré (PR de fork, poste local) : tout est sauté,
# jamais en échec ; dépôt prêt : remise à zéro, PR de travail et clone.
setup_file() {
    [ -n "${REPOWARDEN_IT_REPO:-}" ] || skip "REPOWARDEN_IT_REPO absent : tests contre GitHub sautés"
    command -v gh >/dev/null || skip "gh absent"
    gh auth status >/dev/null 2>&1 || { echo "gh non connecté (GH_TOKEN ?)" >&2; return 1; }
    export IT_REPO="$REPOWARDEN_IT_REPO" GH_REPO="$REPOWARDEN_IT_REPO" REPOWARDEN_LANG=fr
    # Remise à zéro destructive : jamais sur un dépôt qui ne s'est pas déclaré dépôt de test
    if [[ " $(gh api "repos/$IT_REPO" --jq '.topics | join(" ")') " != *" $LABEL "* ]]; then
        echo "$IT_REPO sans le topic $LABEL : refusé (la remise à zéro y fermerait tout)" >&2
        return 1
    fi
    IT_DEFAUT="$(gh api "repos/$IT_REPO" --jq .default_branch)"
    export IT_DEFAUT RW="$BATS_TEST_DIRNAME/../../bin/repowarden"
    remise_a_zero
    touch "$BATS_FILE_TMPDIR/pret"
    gh label create "$LABEL" --repo "$IT_REPO" --force --color ededed --description "Tests d'intégration repowarden" >/dev/null

    # PR de travail pour pr checks / pr label : commit par l'API, aucun push
    local sha
    sha="$(gh api "repos/$IT_REPO/git/ref/heads/$IT_DEFAUT" --jq .object.sha)"
    gh api -X POST "repos/$IT_REPO/git/refs" -f ref=refs/heads/it/pr -f sha="$sha" >/dev/null
    gh api -X PUT "repos/$IT_REPO/contents/it-pr.txt" -f branch=it/pr \
        -f message="test: PR d'integration" -f content="$(date +%s | base64)" >/dev/null
    IT_PR="$(gh pr create --repo "$IT_REPO" --head it/pr --base "$IT_DEFAUT" \
        --title "test: PR d'integration" --body "Ouverte par test/gh/commandes.bats")"
    export IT_PR="${IT_PR##*/}"

    # Clone jetable : l'assistant d'identifiants gh est posé dans le clone seul
    # (git fetch des commandes ticket), et aucun hook global ne s'y mêle
    export CLONE="$BATS_FILE_TMPDIR/clone"
    gh repo clone "https://github.com/$IT_REPO" "$CLONE" -- -q
    mkdir -p "$BATS_FILE_TMPDIR/sans-hooks"
    git -C "$CLONE" config --local core.hooksPath "$BATS_FILE_TMPDIR/sans-hooks"
    git -C "$CLONE" config --local credential.helper ""
    git -C "$CLONE" config --local --add credential.helper "!gh auth git-credential"
}

# Ne laisse ni ticket ni branche derrière soi, même après un échec
teardown_file() {
    [ ! -f "$BATS_FILE_TMPDIR/pret" ] || remise_a_zero
}

# Chaque test part du clone, entrée standard fermée comme en CI
setup() {
    cd "$CLONE" || return 1
    exec </dev/null
}

# REPLY = branche distante du ticket $1 (type/<n>-…), vide si aucune : preuve
# que la branche liée existe bien sur GitHub, pas seulement dans le clone.
branche_distante_r() {
    REPLY="$(git ls-remote --heads origin | sed -n "s#.*refs/heads/\([a-z]*/$1-.*\)#\1#p")"
}

# Numéro du ticket créé par « ticket nouveau », partagé avec les tests suivants
ticket_cree() { cat "$BATS_FILE_TMPDIR/ticket"; }

@test "ticket nouveau : ticket cree et sa branche liee poussee" {
    run "$RW" ticket nouveau "IT ticket nouveau $(date +%s)"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" =~ \#([0-9]+) ]] || false
    n="${BASH_REMATCH[1]}"
    echo "$n" >"$BATS_FILE_TMPDIR/ticket"
    [ "$(gh issue view "$n" --json state --jq .state)" = OPEN ]
    branche_distante_r "$n"
    [ -n "$REPLY" ]
    [ "$(git symbolic-ref --short HEAD)" = "$REPLY" ]
}

@test "ticket <n> : branche existante, bascule dessus" {
    n="$(ticket_cree)"
    git switch -q "$IT_DEFAUT"
    run "$RW" ticket "$n"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    branche_distante_r "$n"
    [ "$(git symbolic-ref --short HEAD)" = "$REPLY" ]
}

@test "ticket <n> : ticket sans branche, branche creee, liee et ticket assigne" {
    url="$(gh issue create --title "IT ticket sans branche" --body "test/gh")"
    n="${url##*/}"
    git switch -q "$IT_DEFAUT"
    run "$RW" ticket "$n"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    branche_distante_r "$n"
    [ -n "$REPLY" ]
    [ "$(git symbolic-ref --short HEAD)" = "$REPLY" ]
    [ -n "$(gh issue view "$n" --json assignees --jq '.assignees[].login')" ]
}

@test "tickets sync : branche locale creee pour un ticket assigne" {
    url="$(gh issue create --title "IT tickets sync" --body "test/gh" --assignee @me)"
    n="${url##*/}"
    git switch -q "$IT_DEFAUT"
    run "$RW" tickets sync
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    branche_distante_r "$n"
    [ -n "$REPLY" ]
    git show-ref -q --verify "refs/heads/$REPLY"
}

@test "ticket comment : commentaire lisible par l'API" {
    n="$(ticket_cree)"
    texte="IT commentaire $(date +%s)"
    run "$RW" ticket comment "$n" "$texte"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    run gh issue view "$n" --json comments --jq '.comments[].body'
    [[ "$output" == *"$texte"* ]] || false
}

@test "ticket label : label ajoute puis retire" {
    n="$(ticket_cree)"
    run "$RW" ticket label "$n" "$LABEL"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    run gh issue view "$n" --json labels --jq '.labels[].name'
    [[ $'\n'"$output"$'\n' == *$'\n'"$LABEL"$'\n'* ]] || false
    run "$RW" ticket label "$n" "$LABEL" --remove
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    run gh issue view "$n" --json labels --jq '.labels[].name'
    [[ $'\n'"$output"$'\n' != *$'\n'"$LABEL"$'\n'* ]] || false
}

@test "pr label : label ajoute puis retire" {
    run "$RW" pr label "$IT_PR" "$LABEL"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    run gh pr view "$IT_PR" --json labels --jq '.labels[].name'
    [[ $'\n'"$output"$'\n' == *$'\n'"$LABEL"$'\n'* ]] || false
    run "$RW" pr label "$IT_PR" "$LABEL" --remove
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    run gh pr view "$IT_PR" --json labels --jq '.labels[].name'
    [[ $'\n'"$output"$'\n' != *$'\n'"$LABEL"$'\n'* ]] || false
}

# bats test_tags=defaut-427
@test "pr checks <n> (#427) : appel accepte par GitHub" {
    run "$RW" pr checks "$IT_PR"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"Not Found"* ]] || false
}

# bats test_tags=defaut-427
@test "run list sans argument (#427) : liste sans erreur" {
    run "$RW" run list
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# bats test_tags=defaut-427
@test "run list --limit (#427) : identifiants de run entiers" {
    run "$RW" run list --limit 5
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    lignes="$(grep -E $'^[^\t]+\t' <<<"$output" || true)"
    [ -n "$lignes" ] || skip "aucun run dans $IT_REPO (y ajouter un workflow, voir CONTRIBUTING.md)"
    # Notation scientifique (3.96e+10) : inutilisable par run rerun <id>
    run grep -vE $'^[0-9]+\t' <<<"$lignes"
    [ -z "$output" ] || { echo "Identifiants non entiers :"; echo "$output"; return 1; }
}

@test "run rerun --failed : appel accepte, sans run echoue message propre" {
    run "$RW" run rerun --failed
    echo "$output"
    [[ "$output" != *"HTTP "* && "$output" != *"Not Found"* ]] || false
    [[ "$status" -eq 0 || "$output" == *"Aucun run échoué"* ]] || false
}
