#!/usr/bin/env bats
# Tickets côté poste : branche sans ticket prévenue (jamais bloquée), création
# proposée seulement si repowarden gère les tickets du projet ; repowarden ticket

load helpers

TICKET="$BATS_TEST_DIRNAME/../bin/ticket"
CC="$BATS_TEST_DIRNAME/../bin/commit"

setup() {
    setup_repo
    initial_commit
    F="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$F/bin"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
# gh simulé : journal dans $FAKE/log
echo "$*" >>"$FAKE/log"
case "$1 $2" in
    "issue create") echo "https://github.com/o/r/issues/42" ;;
    "issue view")
        case "$*" in
            *assignees*) printf '%s\n' "${FAKE_OWNER:-}" ;;
            *) printf '%s\n' "${FAKE_ISSUE:-$(printf 'OPEN\tAjoute le panier\tvalidé')}" ;;
        esac ;;
    "issue develop")
        # --checkout : branche locale ; sinon (sync) branche créée sur origin
        case "$*" in
            *--checkout*) while [ $# -gt 0 ]; do [ "$1" = --name ] && git switch -q -c "$2"; shift; done ;;
            *) while [ $# -gt 0 ]; do [ "$1" = --name ] && git push -q --no-verify origin "main:refs/heads/$2"; shift; done ;;
        esac ;;
    "issue list") printf '%s\n' "${FAKE_ASSIGNED:-}" ;;
    "auth status") exit "${FAKE_GH_AUTH_RC:-0}" ;;
esac
exit 0
GH
    chmod +x "$F/bin/gh"
    export FAKE="$F"
}

# Projet dont repowarden gère les tickets (workflow qui appelle tickets.yml)
gere() {
    mkdir -p .github/workflows
    printf 'jobs:\n  t:\n    uses: o/repowarden/.github/workflows/tickets.yml@v4\n' >.github/workflows/tickets.yml
}

@test "ticket cli : branche sans ticket -> prevenu, comment le faire taire (suivi non gere)" {
    run git switch -c feat/panier
    [ "$status" -eq 0 ]
    [[ "$output" == *"Branche feat/panier sans ticket"* ]] || false
    # ce qu'est un ticket ici, avec le lien vers la doc
    [[ "$output" == *"https://simdevwarden.github.io/repowarden/tickets/"* ]] || false
    [[ "$output" == *"repowarden.skip tickets"* ]] || false
    [[ "$output" != *"ticket nouveau"* ]] || false
}

@test "ticket cli : suivi non gere -> prevenu une seule fois par branche" {
    run git switch -c feat/panier
    [[ "$output" == *"sans ticket"* ]] || false
    echo a >a.txt && git add a.txt
    run "$CC" -m "ajoute le panier"
    [ "$status" -eq 0 ]
    [[ "$output" != *"sans ticket"* ]] || false
    git switch -q main
    run git switch feat/panier
    [[ "$output" != *"sans ticket"* ]] || false
    # une autre branche est prévenue, une fois
    run git switch -c feat/autre
    [[ "$output" == *"Branche feat/autre sans ticket"* ]] || false
    # rien de versionné : la mémoire est dans la config locale du clone
    [ -z "$(git status --porcelain)" ]
}

@test "ticket cli : suivi gere -> prevenu a chaque passage sur la branche" {
    gere
    git add .github && git commit -q --no-verify -m "ci: tickets"
    PATH="$F/bin:$PATH" run git switch -c feat/panier
    [[ "$output" == *"sans ticket"* ]] || false
    git switch -q main
    PATH="$F/bin:$PATH" run git switch feat/panier
    [[ "$output" == *"sans ticket"* ]] || false
}

@test "ticket cli : suivi gere par repowarden -> creation du ticket proposee" {
    gere
    PATH="$F/bin:$PATH" run git switch -c feat/panier
    [[ "$output" == *"sans ticket"* ]] || false
    [[ "$output" == *"repowarden ticket nouveau"* ]] || false
}

@test "ticket cli : branche avec ticket, main ou skip tickets -> aucun avertissement" {
    run git switch -c feat/12-panier
    [[ "$output" != *"sans ticket"* ]] || false
    git config repowarden.skip "secrets tickets"
    run git switch -c feat/autre
    [[ "$output" != *"sans ticket"* ]] || false
    run git switch main
    [[ "$output" != *"sans ticket"* ]] || false
}

@test "ticket cli : git cc sans ticket -> commit fait, prevenu (jamais bloque)" {
    # branche créée sans le hook : git cc est la première occasion de prévenir
    git -c repowarden.skip=post-checkout switch -q -c feat/panier
    echo a >a.txt && git add a.txt
    run "$CC" -m "ajoute le panier"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sans ticket"* ]] || false
    [ "$(subject)" = "feat(panier): ajoute le panier" ]
}

@test "ticket cli : git cc, suivi gere -> ticket cree sur demande et cite" {
    gere
    git config repowarden.ticketAutoCreate true
    git add .github && git commit -q --no-verify -m "ci: tickets"
    git switch -q -c feat/panier
    echo a >a.txt && git add a.txt
    PATH="$F/bin:$PATH" run bash -c "printf '%s\n' '' '' '' 'ajoute le panier' '' 'o' '' '' | '$CC'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ticket #42 créé"* ]] || false
    git log -1 --format=%B | grep -qx 'Ticket : #42'
    grep -q 'issue create --title ajoute le panier' "$F/log"
}

@test "ticket cli : repowarden ticket <n> -> branche existante du ticket" {
    git switch -q -c feat/12-panier
    git push -q --no-verify origin feat/12-panier
    git switch -q main
    git branch -q -D feat/12-panier
    PATH="$F/bin:$PATH" run "$TICKET" 12
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = feat/12-panier ]
    [[ "$output" == *"Sur la branche feat/12-panier (ticket #12)"* ]] || false
}

@test "ticket cli : repowarden ticket <n> sans branche -> creee et liee, sauf ticket a valider" {
    git config repowarden.integrationBranch main
    PATH="$F/bin:$PATH" run "$TICKET" 12
    [ "$status" -eq 0 ]
    grep -q "issue develop 12 --name feat/12-ajoute-le-panier --base main --checkout" "$F/log"
    [ "$(git branch --show-current)" = feat/12-ajoute-le-panier ]
    git switch -q main
    gere
    FAKE_ISSUE="$(printf 'OPEN\tAutre\tstatut: à valider')" PATH="$F/bin:$PATH" run "$TICKET" 13
    [ "$status" -ne 0 ]
    [[ "$output" == *"pas encore validé"* ]] || false
}

@test "ticket cli : repowarden ticket nouveau -> a valider si le suivi est gere" {
    gere
    PATH="$F/bin:$PATH" run "$TICKET" nouveau "Ajoute le panier" --type fix
    [ "$status" -eq 0 ]
    grep -q -- "--label statut: à valider --label type: fix" "$F/log"
    [[ "$output" == *"Ticket #42 créé, à valider"* ]] || false
}

@test "ticket cli : ticket nouveau --type inconnu -> refuse avant gh, types listes" {
    gere
    PATH="$F/bin:$PATH" run "$TICKET" nouveau "Ajoute le panier" --type ci
    [ "$status" -ne 0 ]
    [[ "$output" == *"ci"*"feat, fix, docs, refactor, chore"* ]] || false
    [[ ! -e "$F/log" ]] || false
}

@test "ticket cli : repowarden ticket <n> -> le ticket est pris (assigne a soi)" {
    git config repowarden.integrationBranch main
    PATH="$F/bin:$PATH" run "$TICKET" 12
    [ "$status" -eq 0 ]
    grep -q "issue edit 12 --add-assignee @me" "$F/log"
}

@test "tickets sync : branches locales des tickets assignes, branche courante inchangee" {
    gere
    git push -q --no-verify origin main
    git push -q --no-verify origin "main:refs/heads/fix/12-total"
    export FAKE_ASSIGNED="$(printf '12\tTotal\tvalidé\n13\tAjoute le panier\tvalidé\\ntype: feat\n14\tPas encore\tstatut: à valider')"
    PATH="$F/bin:$PATH" run "$BATS_TEST_DIRNAME/../bin/tickets" sync
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = main ]
    # branche distante existante : suivie en local
    [ "$(git rev-parse --abbrev-ref fix/12-total@{upstream})" = origin/fix/12-total ]
    # pas de branche : creee et liee au ticket, puis suivie
    grep -q "issue develop 13 --name feat/13-ajoute-le-panier --base main" "$F/log"
    [ "$(git rev-parse --abbrev-ref feat/13-ajoute-le-panier@{upstream})" = origin/feat/13-ajoute-le-panier ]
    # pas valide : aucune branche
    [[ "$output" == *"#14"*"pas encore validé"* ]] || false
    ! git show-ref -q --verify refs/heads/feat/14-pas-encore
    [[ "$output" == *"#12 assigné : branche locale fix/12-total prête"* ]] || false
    # relance : rien de nouveau
    PATH="$F/bin:$PATH" run "$BATS_TEST_DIRNAME/../bin/tickets" sync
    [[ "$output" != *"prête"* ]] || false
}

@test "tickets sync : ticket reassigne -> signale, branche locale conservee" {
    gere
    git push -q --no-verify origin main
    git branch -q feat/20-ancien
    FAKE_ASSIGNED="" FAKE_OWNER="$(printf 'OPEN\talice')" PATH="$F/bin:$PATH" \
        run "$BATS_TEST_DIRNAME/../bin/tickets" sync
    [[ "$output" == *"#20 n'est plus assigné à toi (maintenant : alice)"* ]] || false
    git show-ref -q --verify refs/heads/feat/20-ancien
}

@test "tickets sync : automatique dans les hooks, au plus une fois par periode ; off -> rien" {
    gere
    git config repowarden.ticketSync auto
    git push -q --no-verify origin main
    PATH="$F/bin:$PATH" git switch -q -c feat/1-a
    [ "$(grep -c "^issue list" "$F/log")" -eq 1 ]
    PATH="$F/bin:$PATH" git switch -q main
    [ "$(grep -c "^issue list" "$F/log")" -eq 1 ]
    rm -f "$(git rev-parse --git-common-dir)/repowarden-ticket-sync"
    git config repowarden.ticketSync off
    PATH="$F/bin:$PATH" git switch -q feat/1-a
    [ "$(grep -c "^issue list" "$F/log")" -eq 1 ]
}

@test "tickets sync : ticket assigne deja livre (preprod, done) -> aucune branche recreee" {
    gere
    git push -q --no-verify origin main
    export FAKE_ASSIGNED="$(printf '184\tLivre\tvalidé\\nstatut: préprod\n185\tEn prod\tvalidé\\nstatut: done')"
    PATH="$F/bin:$PATH" run "$BATS_TEST_DIRNAME/../bin/tickets" sync
    [ "$status" -eq 0 ]
    ! grep -q "issue develop" "$F/log"
    [ -z "$(git branch --list 'feat/18*')" ]
}

@test "tickets sync : clonage -> aucun appel a GitHub, aucune branche (cas #366)" {
    gere
    git add -A && git commit -q --no-verify -m "chore: suivi des tickets"
    git push -q --no-verify origin main
    git push -q --no-verify origin "main:refs/heads/fix/366-bots-release"
    # ticket mergé dont le statut a regressé a tort : assigne, ouvert
    export FAKE_ASSIGNED="$(printf '366\tBots release\tvalidé\\ntype: fix\\nstatut: en relecture')"
    # hooks repowarden du poste (core.hooksPath) : le clone les execute, meme en auto
    PATH="$F/bin:$PATH" run git -c core.hooksPath="$HOOKS" -c repowarden.ticketSync=auto clone -q "$REMOTE" "$BATS_TEST_TMPDIR/clone"
    [ "$status" -eq 0 ]
    [[ "$output" != *"#366"* ]] || false
    [ ! -s "$F/log" ]
    [ -z "$(git -C "$BATS_TEST_TMPDIR/clone" branch --list 'fix/366*')" ]
}

@test "tickets sync : git pull sans reglage (defaut manual) -> aucun appel a GitHub, aucune branche" {
    gere
    git add -A && git commit -q --no-verify -m "chore: suivi des tickets"
    git push -q --no-verify origin main
    git push -q --no-verify origin "main:refs/heads/fix/384-clonage" "main:refs/heads/fix/383-depot"
    export FAKE_ASSIGNED="$(printf '384\tClonage\tvalidé\\nstatut: en cours\n383\tDepot\tvalidé\\nstatut: en cours')"
    PATH="$F/bin:$PATH" run git pull -q origin main
    [ "$status" -eq 0 ]
    PATH="$F/bin:$PATH" run git switch -q -c feat/1-a
    [[ "$output" != *"prête"* ]] || false
    [ ! -s "$F/log" ]
    [ -z "$(git branch --list 'fix/38*')" ]
    # volontaire : la commande garde son comportement
    PATH="$F/bin:$PATH" run "$BATS_TEST_DIRNAME/../bin/tickets" sync
    [[ "$output" == *"#384 assigné : branche locale fix/384-clonage prête"* ]] || false
}

@test "tickets sync : en relecture sans branche distante (PR mergee) -> branche pas recreee" {
    gere
    git push -q --no-verify origin main
    export FAKE_ASSIGNED="$(printf '366\tBots release\tvalidé\\nstatut: en relecture\n13\tPanier\tvalidé\\nstatut: en cours')"
    PATH="$F/bin:$PATH" run "$BATS_TEST_DIRNAME/../bin/tickets" sync
    [ "$status" -eq 0 ]
    [ "$(grep -c "issue develop 366" "$F/log")" -eq 0 ]
    [ -z "$(git branch --list 'feat/366*')" ]
    # ticket reellement en cours : comportement inchange
    grep -q "issue develop 13 " "$F/log"
}

@test "tickets init : etiquettes, fichiers du modele, fin sans erreur" {
    gere
    PATH="$F/bin:$PATH" run "$BATS_TEST_DIRNAME/../bin/tickets" init --repo o/r
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"command not found"* ]] || false
    [[ "$output" == *"Création auto de ticket : DÉSACTIVÉE"*"Suivi des tickets prêt."* ]] || false
    grep -q '^label create type: feat --repo o/r' "$FAKE/log"
    [ -f .github/ISSUE_TEMPLATE/ticket.yml ]
    # workflow existant : laissé tel quel
    grep -q "uses: o/repowarden/.github/workflows/tickets.yml@v4" .github/workflows/tickets.yml
}

@test "ticket cli : gh installe mais non connecte -> message repowarden et code 1" {
    FAKE_GH_AUTH_RC=1 PATH="$F/bin:$PATH" run "$TICKET" 12
    [ "$status" -eq 1 ]
    [[ "$output" == *"gh non connecté"* ]] || false
    [[ "$output" == *"gh auth login -s workflow"* ]] || false
    [[ "$output" != *"command not found"* ]] || false
    # rien n'est tenté : ni branche, ni appel au ticket
    [ "$(git branch --show-current)" = main ]
    ! grep -q "issue develop" "$F/log"
}

@test "tickets init : gh installe mais non connecte -> message repowarden et code 1" {
    FAKE_GH_AUTH_RC=1 PATH="$F/bin:$PATH" run "$BATS_TEST_DIRNAME/../bin/tickets" init --repo o/r
    [ "$status" -eq 1 ]
    [[ "$output" == *"gh non connecté"* ]] || false
    [[ "$output" == *"gh auth login -s workflow"* ]] || false
}

@test "ticket cli : refspec ajoutee une fois en clone mono-branche, jamais en clone normal" {
    git push -q --no-verify origin main
    git switch -q -c feat/12-panier
    git push -q --no-verify origin feat/12-panier
    git switch -q main
    # clone mono-branche : la ref du ticket existe sans etre suivie
    git clone -q --single-branch "$REMOTE" "$BATS_TEST_TMPDIR/mono"
    git -C "$BATS_TEST_TMPDIR/mono" fetch -q origin "+refs/heads/feat/12-panier:refs/remotes/origin/feat/12-panier"
    cd "$BATS_TEST_TMPDIR/mono"
    PATH="$F/bin:$PATH" run "$TICKET" 12
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    # deuxieme appel, sans branche locale : la refspec n'est pas ajoutee en double
    git switch -q main
    git branch -q -D feat/12-panier
    PATH="$F/bin:$PATH" run "$TICKET" 12
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(git config --get-all remote.origin.fetch | grep -c 'refs/heads/feat/12-panier')" -eq 1 ]
    # clone normal : la refspec generale couvre deja la branche, rien n'est ajoute
    git clone -q "$REMOTE" "$BATS_TEST_TMPDIR/full"
    cd "$BATS_TEST_TMPDIR/full"
    PATH="$F/bin:$PATH" run "$TICKET" 12
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(git config --get-all remote.origin.fetch | wc -l | tr -d ' ')" -eq 1 ]
    [ "$(git config --get remote.origin.fetch)" = "+refs/heads/*:refs/remotes/origin/*" ]
}

@test "ticket cli : clone mono-branche -> ticket <n> bascule sur la branche distante" {
    git push -q --no-verify origin main
    git switch -q -c feat/12-panier
    git push -q --no-verify origin feat/12-panier
    git switch -q main
    git clone -q --single-branch "$REMOTE" "$BATS_TEST_TMPDIR/clone"
    # Le clone ne suit qu'une branche : la ref du ticket existe sans être suivie
    git -C "$BATS_TEST_TMPDIR/clone" fetch -q origin "+refs/heads/feat/12-panier:refs/remotes/origin/feat/12-panier"
    cd "$BATS_TEST_TMPDIR/clone"
    PATH="$F/bin:$PATH" run "$TICKET" 12
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(git branch --show-current)" = feat/12-panier ]
    [ "$(git rev-parse --abbrev-ref feat/12-panier@{upstream})" = origin/feat/12-panier ]
    [[ "$output" == *"Sur la branche feat/12-panier (ticket #12)"* ]] || false
}
