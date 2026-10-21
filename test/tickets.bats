#!/usr/bin/env bats
# Suivi des tickets (ci/tickets.sh) : gh simulé, état des tickets en fichiers

load helpers

TICKETS="$BATS_TEST_DIRNAME/../ci/tickets.sh"

setup() {
    setup_repo
    F="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$F/bin" "$F/issues"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
# gh simulé : tickets dans $F/issues/<n>.labels, journal dans $F/log
F="$FAKE"
echo "$*" >>"$F/log"
etiquettes() { cat "$F/issues/$1.labels" 2>/dev/null || true; }
case "$1 $2" in
    "pr view")
        case "$*" in
            *"-q .body"*) cat "$F/pr_body.$3" 2>/dev/null || cat "$F/pr_body" 2>/dev/null || true ;;
            *"-q .title"*) echo "feat: panier" ;;
            *"-q .isDraft"*) echo "${FAKE_DRAFT:-true}" ;;
            *"-q .state"*) echo "${FAKE_PR_STATE:-OPEN}" ;;
            *commits*) cat "$F/pr_commits" 2>/dev/null || true ;;
        esac ;;
    "pr edit")
        echo "pr-editee $3" >>"$F/events"
        while [ $# -gt 0 ]; do [ "$1" = --body ] && printf '%s' "$2" >"$F/pr_body"; shift; done ;;
    "pr list")
        case "$*" in
            *--head*) printf '%s\n' "${FAKE_PR_HEAD:-}" ;;
            *"--state all"*) printf '%s\n' "${FAKE_PRS_ALL:-}" ;;
            *) printf '%s\n' "${FAKE_PRS:-}" ;;
        esac ;;
    "pr create")
        echo "pr-creee $*" >>"$F/events"
        while [ $# -gt 0 ]; do
            [ "$1" = --title ] && printf '%s' "$2" >"$F/pr_title"
            [ "$1" = --body ] && printf '%s' "$2" >"$F/pr_body"
            shift
        done
        echo "https://github.com/o/r/pull/9" ;;
    "pr close") [ -z "${FAKE_CLOSE_FAIL:-}" ] || exit 1; echo "pr-fermee $3" >>"$F/events" ;;
    "pr merge")
        case "$*" in
            *--disable-auto*) echo "merge-desarme $3" >>"$F/events" ;;
            *"--auto --squash"*) echo "merge-auto $3" >>"$F/events" ;;
        esac ;;
    "api graphql")
        case "$*" in *closer*) printf '%s\n' "${FAKE_CLOSER:-}"; exit 0 ;; esac
        for a in "$@"; do case "$a" in name=*) echo "branche-creee ${a#name=}" >>"$F/events" ;; esac; done ;;
    "api -X")
        echo "branche-supprimee ${4#repos/o/r/git/refs/heads/}" >>"$F/events" ;;
    "api repos/o/r/git/matching-refs/heads/") cat "$F/refs" 2>/dev/null || true ;;
    "api repos/o/r") echo R_1 ;;
    "api repos/o/r/git/ref/heads/develop") echo sha0 ;;
    "api repos/o/r/compare/"*)
        case "$*" in
            *"commits[0]"*) cat "$F/premier" 2>/dev/null || true ;;
            *commits*) cat "$F/commits" 2>/dev/null || true ;;
            *) echo "${FAKE_AHEAD:-1}" ;;
        esac ;;
    "issue create")
        n=42
        while [ $# -gt 0 ]; do [ "$1" = --label ] && echo "$2" >>"$F/issues/$n.labels"; shift; done
        echo "https://github.com/o/r/issues/$n" ;;
    "issue view")
        case "$*" in
            *"-q .title"*) cat "$F/issues/$3.title" 2>/dev/null || echo "Ajoute le panier" ;;
            *"-q .id"*) echo "I_$3" ;;
            # conception écrite par un mainteneur (sauf ticket marqué sans)
            *authorAssociation*) [ -e "$F/issues/$3.sansconception" ] || echo "## Conception retenue (avant code)" ;;
            *comments*) cat "$F/issues/$3.comments" 2>/dev/null || true ;;
            *assignees*) cat "$F/issues/$3.assignees" 2>/dev/null || true ;;
            *"-q .body"*) cat "$F/issues/$3.body" 2>/dev/null || true ;;
            *) etiquettes "$3" ;;
        esac ;;
    "issue edit")
        n="$3"; shift 3
        while [ $# -gt 0 ]; do
            case "$1" in
                --add-label) echo "$2" >>"$F/issues/$n.labels" ;;
                --remove-label) grep -vxF "$2" "$F/issues/$n.labels" >"$F/tmp" || true; mv "$F/tmp" "$F/issues/$n.labels" ;;
            esac
            shift
        done ;;
    "issue comment") echo "commentaire $3" >>"$F/events"; printf '%s\n' "$5" >>"$F/issues/$3.comments" ;;
    "issue close") echo "fermé $3" >>"$F/events" ;;
    "issue reopen") echo "rouvert $3" >>"$F/events" ;;
    "issue list")
        while [ $# -gt 0 ]; do [ "$1" = --label ] && l="$2"; shift; done
        for f in "$F"/issues/*.labels; do
            [ -e "$f" ] && grep -qxF "$l" "$f" && basename "$f" .labels
        done ;;
    "api repos/o/r/issues?"*) printf '%s\n' "${FAKE_ISSUES:-}" ;;
    "api repos/"*)
        for a in "$@"; do case "$a" in state=*) echo "statut-pr ${a#state=}" >>"$F/events" ;; esac; done ;;
esac
exit 0
GH
    chmod +x "$F/bin/gh"
    export PATH="$F/bin:$PATH" FAKE="$F" GH_REPO=o/r
    export PR=7 HEAD=feat/12-panier BASE=develop HEAD_SHA=abc AUTHOR=dev DRAFT=false MERGED=false
}

labels() { cat "$F/issues/$1.labels" 2>/dev/null; }
ticket() { printf '%s\n' "$@" >"$F/issues/$N.labels"; }

@test "tickets : references lues dans la description et la branche, sans doublon" {
    source "$TICKETS"
    pr_tickets_r $'Ajoute le panier.\n\nTickets : #3, #4\nCloses #7' feat/12-panier
    [ "$REPLY" = "3 4 7 12" ]
    pr_tickets_r "Ticket : #3" fix/3-bug
    [ "$REPLY" = 3 ]
    pr_tickets_r "rien" feat/panier
    [ -z "$REPLY" ]
}

@test "tickets : PR sans ticket -> ticket cree a valider, relie, PR bloquee (auto-create=true)" {
    printf 'Ajoute le panier.' >"$F/pr_body"
    HEAD=feat/panier ACTION=opened AUTO_CREATE=true run "$TICKETS" pr
    # bloquee par le statut « ticket », le job reste vert (pas une panne)
    [ "$status" -eq 0 ]
    grep -qxF "statut: à valider" "$F/issues/42.labels"
    grep -q "Ticket : #42" "$F/pr_body"
    grep -qx "statut-pr failure" "$F/events"
    [[ "$output" == *"#42 à valider"* ]] || false
}

@test "tickets : PR sans ticket -> echec verification avec marche a suivre (auto-create=false)" {
    printf 'Ajoute le panier.' >"$F/pr_body"
    HEAD=feat/panier ACTION=opened run "$TICKETS" pr
    # echec de la verification ticket, pas de ticket cree
    [ "$status" -eq 0 ]
    [ ! -f "$F/issues/42.labels" ]
    grep -qx "statut-pr failure" "$F/events"
}

@test "tickets : ticket valide -> en cours (brouillon), en relecture (prete), PR debloquee" {
    N=12 ticket "validé" "statut: backlog"
    printf 'Ticket : #12' >"$F/pr_body"
    ACTION=opened DRAFT=true run "$TICKETS" pr
    [ "$status" -eq 0 ]
    [ "$(labels 12 | grep statut)" = "statut: en cours" ]
    ACTION=ready_for_review DRAFT=false run "$TICKETS" pr
    [ "$(labels 12 | grep statut)" = "statut: en relecture" ]
    grep -qx "statut-pr success" "$F/events"
}

@test "tickets : etiquette valide -> backlog et PR en attente debloquee" {
    N=12 ticket "statut: à valider" "validé"
    printf 'Ticket : #12' >"$F/pr_body"
    FAKE_PRS=$'7\tfeat/12-panier\tabc' ISSUE=12 ACTION=labeled LABEL=validé run "$TICKETS" issue
    [ "$status" -eq 0 ]
    [ "$(labels 12 | grep statut)" = "statut: backlog" ]
    grep -qx "statut-pr success" "$F/events"
}

@test "tickets : ouvert par un mainteneur -> valide d'office, backlog, branche ; sinon a valider" {
    echo "Corrige le total à payer" >"$F/issues/12.title"
    N=12 ticket "type: fix"
    echo moi >"$F/issues/12.assignees"
    ISSUE=12 ACTION=opened ISSUE_ASSOCIATION=OWNER run "$TICKETS" issue
    [ "$status" -eq 0 ]
    grep -qxF "validé" "$F/issues/12.labels"
    [ "$(labels 12 | grep statut)" = "statut: backlog" ]
    grep -qx "branche-creee fix/12-corrige-le-total-a-payer" "$F/events"
    # PR deja ouverte pour ce ticket : debloquee, pas de seconde branche
    N=14 ticket "type: fix"
    printf 'Ticket : #14' >"$F/pr_body"
    : >"$F/events"
    FAKE_PRS=$'7\tfix/14-total\tabc' ISSUE=14 ACTION=opened ISSUE_ASSOCIATION=COLLABORATOR run "$TICKETS" issue
    grep -qx "statut-pr success" "$F/events"
    ! grep -q "branche-creee" "$F/events"
    # contributeur externe, ou validation automatique desactivee : a valider
    for cas in "ISSUE_ASSOCIATION=NONE" "ISSUE_ASSOCIATION=CONTRIBUTOR" "ISSUE_ASSOCIATION=OWNER AUTO_VALIDATE=never"; do
        N=13 ticket "type: feat"
        env $cas ISSUE=13 ACTION=opened "$TICKETS" issue
        ! grep -qxF "validé" "$F/issues/13.labels"
        [ "$(labels 13 | grep statut)" = "statut: à valider" ]
    done
}

@test "tickets : run opened annule -> labeled ou assigned rattrape la validation d'office" {
    # Ticket créé avec ses étiquettes : le run « opened » attendait et a été
    # annulé par GitHub (un seul run en attente par groupe de concurrence)
    N=72 ticket "statut: à valider" "type: feat"
    ISSUE=72 ACTION=labeled LABEL="type: feat" ISSUE_ASSOCIATION=OWNER run "$TICKETS" issue
    [ "$status" -eq 0 ]
    grep -qxF "validé" "$F/issues/72.labels"
    [ "$(labels 72 | grep statut)" = "statut: backlog" ]
    # run « opened » tardif, puis autre étiquette : rien n'est refait
    : >"$F/events"
    ISSUE=72 ACTION=opened ISSUE_ASSOCIATION=OWNER run "$TICKETS" issue
    ISSUE=72 ACTION=labeled LABEL="statut: à valider" ISSUE_ASSOCIATION=OWNER run "$TICKETS" issue
    [ "$(grep -cxF "validé" "$F/issues/72.labels")" -eq 1 ]
    ! grep -q "commentaire 72" "$F/events"
    # assigné avant tout autre run : validé, branche, en cours
    N=73 ticket "type: fix"
    echo moi >"$F/issues/73.assignees"
    ISSUE=73 ACTION=assigned ISSUE_ASSOCIATION=MEMBER run "$TICKETS" issue
    grep -qxF "validé" "$F/issues/73.labels"
    grep -q "branche-creee fix/73-" "$F/events"
    [ "$(labels 73 | grep statut)" = "statut: en cours" ]
    # pas de rattrapage : contributeur externe, auto-validate never, ticket
    # fermé, ou « validé » retiré à la main d'un ticket déjà rangé
    for cas in "ISSUE_ASSOCIATION=NONE" "ISSUE_ASSOCIATION=OWNER AUTO_VALIDATE=never" \
        "ISSUE_ASSOCIATION=OWNER ISSUE_STATE=closed"; do
        N=74 ticket "statut: à valider" "type: feat"
        env $cas ISSUE=74 ACTION=labeled LABEL="type: feat" "$TICKETS" issue
        ! grep -qxF "validé" "$F/issues/74.labels"
    done
    N=75 ticket "statut: backlog" "type: feat"
    ISSUE=75 ACTION=labeled LABEL="type: feat" ISSUE_ASSOCIATION=OWNER run "$TICKETS" issue
    ! grep -qxF "validé" "$F/issues/75.labels"
}

@test "tickets : PR mergee -> preprod ; release -> done et ferme ; preversion -> commentaire" {
    N=12 ticket "validé" "statut: en relecture"
    printf 'Ticket : #12' >"$F/pr_body"
    ACTION=closed MERGED=true run "$TICKETS" pr
    [ "$(labels 12 | grep statut)" = "statut: préprod" ]
    TAG=v3.6.0-next.2 run "$TICKETS" release
    ! grep -q "fermé 12" "$F/events"
    grep -q "commentaire 12" "$F/events"
    TAG=v3.6.0 run "$TICKETS" release
    [ "$(labels 12 | grep statut)" = "statut: done" ]
    grep -qx "fermé 12" "$F/events"
}

@test "tickets : livraison sur main sans nouvelle version -> preprod en done, ferme avec le commit" {
    N=12 ticket "validé" "statut: préprod"
    N=13 ticket "validé" "statut: en cours"
    DELIVERED_SHA=0123456789abcdef MAIN=main run "$TICKETS" release
    [ "$status" -eq 0 ]
    [ "$(labels 12 | grep statut)" = "statut: done" ]
    grep -qx "fermé 12" "$F/events"
    grep -q "issue close 12 --comment .*sans nouvelle version.*0123456" "$F/log"
    # ticket pas encore livre : intact
    [ "$(labels 13 | grep statut)" = "statut: en cours" ]
    ! grep -q "fermé 13" "$F/events"
    # ni tag ni commit livre : aucun ticket ferme
    : >"$F/events"
    N=12 ticket "validé" "statut: préprod"
    run "$TICKETS" release
    [ "$status" -ne 0 ]
    ! grep -q "fermé" "$F/events"
}

@test "tickets : bots et livraisons sans ticket exige" {
    ACTION=opened AUTHOR='dependabot[bot]' run "$TICKETS" pr
    [ "$status" -eq 0 ]
    ACTION=opened HEAD=develop run "$TICKETS" pr
    [ "$status" -eq 0 ]
    [ ! -e "$F/issues/42.labels" ]
    # instantane de livraison vers main : sans ticket
    : >"$F/events"
    ACTION=opened HEAD=livraison/v4.4.0 BASE=main run "$TICKETS" pr
    [ "$status" -eq 0 ]
    grep -qx "statut-pr success" "$F/events"
    [ ! -e "$F/issues/42.labels" ]
}

@test "tickets : valide sans personne -> attend d'etre pris ; assigne -> branche creee depuis develop, liee, une seule fois" {
    N=12 ticket "statut: à valider" "validé" "type: fix"
    echo "Corrige le total à payer" >"$F/issues/12.title"
    ISSUE=12 ACTION=labeled LABEL=validé run "$TICKETS" issue
    [ "$status" -eq 0 ]
    ! grep -q "branche-creee" "$F/events"
    grep -q "repowarden ticket 12" "$F/issues/12.comments"
    [ "$(labels 12 | grep statut)" = "statut: backlog" ]
    # pris : assigne -> sa branche, en cours
    : >"$F/events"
    echo moi >"$F/issues/12.assignees"
    ISSUE=12 ACTION=assigned run "$TICKETS" issue
    [ "$status" -eq 0 ]
    [ "$(labels 12 | grep statut)" = "statut: en cours" ]
    grep -qx "branche-creee fix/12-corrige-le-total-a-payer" "$F/events"
    # valide alors qu'il est deja assigne : branche tout de suite
    : >"$F/events"
    N=12 ticket "statut: à valider" "validé" "type: fix"
    ISSUE=12 ACTION=labeled LABEL=validé run "$TICKETS" issue
    grep -qx "branche-creee fix/12-corrige-le-total-a-payer" "$F/events"
    grep -q "commentaire 12" "$F/events"
    [ "$(labels 12 | grep statut)" = "statut: backlog" ]
    # Branche deja la : rien de plus
    : >"$F/events"
    echo "refs/heads/fix/12-corrige-le-total-a-payer" >"$F/refs"
    ISSUE=12 ACTION=labeled LABEL=validé run "$TICKETS" issue
    ! grep -q "branche-creee" "$F/events"
}

@test "tickets : premier push sur la branche du ticket -> PR brouillon, en cours" {
    N=12 ticket "validé" "statut: backlog" "type: feat"
    echo "Tickets : ajoute le panier" >"$F/issues/12.title"
    cat >"$F/issues/12.body" <<'EOF'
## Besoin
Ajouter un panier.

## Terminé quand…
- le panier s'ajoute au total
- un code promo s'applique
EOF
    printf -- '- abc1234 feat: ajoute le panier\n' >"$F/commits"
    PUSH_BRANCH=feat/12-panier SHA=def PUSHER=dev run "$TICKETS" push
    [ "$status" -eq 0 ]
    grep -q "pr-creee pr create --draft --base develop --head feat/12-panier --title feat(tickets): ajoute le panier" "$F/events"
    [ "$(cat "$F/pr_title")" = "feat(tickets): ajoute le panier" ]
    grep -q -- "- \[ \] le panier s'ajoute au total" "$F/pr_body"
    grep -q -- "- \[ \] un code promo s'applique" "$F/pr_body"
    grep -q -- "## Commits" "$F/pr_body"
    grep -q -- "abc1234 feat: ajoute le panier" "$F/pr_body"
    grep -q -- "Ticket : #12" "$F/pr_body"
    [ "$(labels 12 | grep statut)" = "statut: en cours" ]
    grep -qx "statut-pr success" "$F/events"
    # PR brouillon deja ouverte : titre et description mis a jour au push suivant
    : >"$F/events"
    FAKE_PR_HEAD=9 PUSH_BRANCH=feat/12-panier SHA=def run "$TICKETS" push
    grep -qx "pr-editee 9" "$F/events"
    # PR sortie du brouillon, branche sans ticket, ou rien de nouveau : aucune ecriture
    : >"$F/events"
    FAKE_PR_HEAD=9 FAKE_DRAFT=false PUSH_BRANCH=feat/12-panier SHA=def run "$TICKETS" push
    PUSH_BRANCH=feat/panier SHA=def run "$TICKETS" push
    FAKE_AHEAD=0 PUSH_BRANCH=feat/12-panier SHA=def run "$TICKETS" push
    ! grep -qE "pr-creee|pr-editee" "$F/events"
}

@test "tickets : nom de branche sans mot vide final, titre de PR type(portee)" {
    source "$TICKETS"
    ticket_branch_r 12 "Corrige le total de"
    [ "$REPLY" = "feat/12-corrige-le-total" ]
    ticket_branch_r 12 "Tickets : chaque ticket garde la trace de sa branche"
    [[ "$REPLY" != *-de && "$REPLY" != *- ]] || false
    # portee = prefixe du titre avant le premier « : », sujet = le reste
    ticket_pr_title_r feat "Tickets : ajoute le panier"
    [ "$REPLY" = "feat(tickets): ajoute le panier" ]
    ticket_pr_title_r fix "Corrige le total à payer"
    [ "$REPLY" = "fix: corrige le total à payer" ]
    # 72 caracteres au plus, coupe sur un mot entier (jamais de mot tronque)
    ticket_pr_title_r feat "Tickets : un titre vraiment très long qui doit être coupé sur un mot entier"
    t="$REPLY"
    authored_length "$t"
    [ "$REPLY" -le 72 ]
    [[ "$t" != *" " ]] || false
    [[ " un titre vraiment très long qui doit être coupé sur un mot entier " == *" ${t##* } "* ]] || false
}

@test "tickets : titre de PR brouillon = en-tete du premier commit, (#N) retire" {
    N=12 ticket "validé" "statut: backlog" "type: feat"
    echo "Tickets : ajoute le panier" >"$F/issues/12.title"
    printf 'fix(panier): total du README (#12)\ncorps du commit\n' >"$F/premier"
    PUSH_BRANCH=feat/12-panier SHA=def PUSHER=dev run "$TICKETS" push
    [ "$status" -eq 0 ]
    [ "$(cat "$F/pr_title")" = "fix(panier): total du README" ]
    # en-tete non conforme -> repli sur le titre du ticket, sigle conserve
    printf 'WIP panier\n' >"$F/premier"
    echo "Tickets : README et messages" >"$F/issues/12.title"
    PUSH_BRANCH=feat/12-panier SHA=def PUSHER=dev run "$TICKETS" push
    [ "$status" -eq 0 ]
    [ "$(cat "$F/pr_title")" = "feat(tickets): README et messages" ]
}

@test "tickets : titre de PR depuis le ticket, sigle conserve, aucun mot coupe" {
    source "$TICKETS"
    ticket_pr_title_r fix "GitHub facultatif : README et messages de démarrage"
    [ "$REPLY" = "fix(github-facultatif): README et messages de démarrage" ]
    ticket_pr_title_r feat "IA locale"
    [ "$REPLY" = "feat: IA locale" ]
    ticket_pr_title_r feat "Ajoute le panier"
    [ "$REPLY" = "feat: ajoute le panier" ]
    s="assistants IA et Kubernetes désactivés par défaut au premier démarrage du conteneur"
    ticket_pr_title_r feat "Modules à la demande : $s"
    t="$REPLY"
    authored_length "$t"
    [ "$REPLY" -le 72 ]
    [[ "$t" == "feat(modules-a-la-demande): assistants IA "* ]] || false
    [[ " $s " == *" ${t##* } "* ]] || false
    # un seul mot trop long : jamais tronque au caractere, titre vide (repli)
    ticket_pr_title_r feat "Tickets : $(printf 'mot%.0s' {1..30})"
    [ -z "$REPLY" ]
}

@test "tickets : assigne -> en cours ; corrections demandees -> en cours" {
    N=12 ticket "validé" "statut: backlog"
    ISSUE=12 ACTION=assigned run "$TICKETS" issue
    [ "$(labels 12 | grep statut)" = "statut: en cours" ]
    N=12 ticket "validé" "statut: en relecture"
    printf 'Ticket : #12' >"$F/pr_body"
    REVIEW_STATE=approved run "$TICKETS" revue
    [ "$(labels 12 | grep statut)" = "statut: en relecture" ]
    REVIEW_STATE=changes_requested run "$TICKETS" revue
    [ "$(labels 12 | grep statut)" = "statut: en cours" ]
}

@test "tickets : ticket abandonne -> PR fermee, branche supprimee" {
    echo "refs/heads/feat/12-panier" >"$F/refs"
    FAKE_PR_HEAD=9 ISSUE=12 ACTION=closed STATE_REASON=completed run "$TICKETS" issue
    ! grep -q "branche-supprimee" "$F/events" 2>/dev/null
    FAKE_PR_HEAD=9 ISSUE=12 ACTION=closed STATE_REASON=not_planned run "$TICKETS" issue
    [ "$status" -eq 0 ]
    grep -qx "pr-fermee 9" "$F/events"
    grep -qx "branche-supprimee feat/12-panier" "$F/events"
}

@test "tickets : registre -> branche creee, faite a la main ou seconde, inscrite une fois sur le ticket" {
    N=12 ticket "validé" "statut: backlog" "type: fix"
    echo "Corrige le total" >"$F/issues/12.title"
    echo moi >"$F/issues/12.assignees"
    ISSUE=12 ACTION=labeled LABEL=validé run "$TICKETS" issue
    grep -qF "<!-- repowarden:branche fix/12-corrige-le-total -->" "$F/issues/12.comments"
    # premier push de la branche creee : deja inscrite, rien de plus
    : >"$F/events"
    FAKE_PR_HEAD=9 PUSH_BRANCH=fix/12-corrige-le-total SHA=a run "$TICKETS" push
    ! grep -q "commentaire 12" "$F/events"
    # branche faite a la main pour le ticket 13 : inscrite au premier push, une fois
    N=13 ticket "validé" "statut: backlog"
    FAKE_PR_HEAD=9 PUSH_BRANCH=feat/13-a-la-main SHA=b run "$TICKETS" push
    FAKE_PR_HEAD=9 PUSH_BRANCH=feat/13-a-la-main SHA=c run "$TICKETS" push
    [ "$(grep -c "repowarden:branche feat/13-a-la-main" "$F/issues/13.comments")" -eq 1 ]
    # seconde branche pour le meme ticket : inscrite et signalee
    FAKE_PR_HEAD=9 PUSH_BRANCH=feat/13-autre SHA=d run "$TICKETS" push
    [[ "$output" == *"feat/13-autre"*"feat/13-a-la-main"* ]] || false
    grep -q "repowarden:branche feat/13-autre" "$F/issues/13.comments"
}

@test "tickets : mise en route -> tickets existants ranges, branches des PR inscrites, relancable" {
    N=20 ticket "validé"
    N=21 ticket "type: feat"
    N=22 ticket "type: fix"
    N=23 ticket "statut: en cours"
    printf 'Ticket : #21' >"$F/pr_body.5"
    printf 'Rien' >"$F/pr_body.6"
    printf 'Notes' >"$F/pr_body.8"
    export FAKE_ISSUES=$'20\tNONE\n21\tOWNER\n22\tNONE\n23\tNONE' \
        FAKE_PRS_ALL=$'5\tfeat/panier\n6\tfix/22-total\n8\tdevelop'
    run "$TICKETS" adopter
    [ "$status" -eq 0 ]
    [ "$(labels 20 | grep statut)" = "statut: backlog" ]
    grep -qxF "validé" "$F/issues/21.labels"
    [ "$(labels 21 | grep statut)" = "statut: backlog" ]
    [ "$(labels 22 | grep statut)" = "statut: à valider" ]
    [ "$(labels 23 | grep statut)" = "statut: en cours" ]
    grep -q "repowarden:branche feat/panier" "$F/issues/21.comments"
    grep -q "PR #5" "$F/issues/21.comments"
    grep -q "repowarden:branche fix/22-total" "$F/issues/22.comments"
    [[ "$output" == *"3"*"2"* ]] || false
    # relance : rien de nouveau
    : >"$F/events"
    run "$TICKETS" adopter
    ! grep -q "commentaire" "$F/events"
    # sans validation automatique : ticket d'un mainteneur a valider
    N=24 ticket "type: feat"
    FAKE_ISSUES=$'24\tOWNER' FAKE_PRS_ALL="" AUTO_VALIDATE=never run "$TICKETS" adopter
    [ "$(labels 24 | grep statut)" = "statut: à valider" ]
}

@test "tickets : PR sans objet depuis main ou develop -> fermee avec la marche a suivre ; retour utile garde" {
    ACTION=opened HEAD=develop BASE=feat/184-x run "$TICKETS" pr
    [ "$status" -eq 0 ]
    grep -qx "pr-fermee 7" "$F/events"
    [[ "$output" == *"git merge origin/develop"* ]] || false
    grep -qx "statut-pr success" "$F/events"
    # retour main -> develop sans contenu : ferme
    : >"$F/events"
    FAKE_AHEAD=0 ACTION=opened HEAD=main BASE=develop run "$TICKETS" pr
    grep -qx "pr-fermee 7" "$F/events"
    # retour avec contenu propre a main : garde, sans ticket exige
    : >"$F/events"
    FAKE_AHEAD=3 ACTION=opened HEAD=main BASE=develop run "$TICKETS" pr
    ! grep -q "pr-fermee" "$F/events"
    grep -qx "statut-pr success" "$F/events"
    # livraison develop -> main : inchangee
    : >"$F/events"
    ACTION=opened HEAD=develop BASE=main run "$TICKETS" pr
    ! grep -q "pr-fermee" "$F/events"
    # deja mergee pendant le run : rien a fermer, pas un echec
    FAKE_CLOSE_FAIL=1 FAKE_PR_STATE=MERGED FAKE_AHEAD=0 ACTION=opened HEAD=main BASE=develop run "$TICKETS" pr
    [ "$status" -eq 0 ]
    # encore ouverte et fermeture refusee : echec signale
    FAKE_CLOSE_FAIL=1 FAKE_PR_STATE=OPEN FAKE_AHEAD=0 ACTION=opened HEAD=main BASE=develop run "$TICKETS" pr
    [ "$status" -ne 0 ]
}

@test "tickets : livraison par le workflow -> PR develop vers main ouverte a la main fermee avec la marche a suivre" {
    # sans delivery-workflow : une livraison manuelle reste possible
    ACTION=opened HEAD=develop BASE=main AUTHOR=dev run "$TICKETS" pr
    ! grep -q "pr-fermee" "$F/events"
    # delivery-workflow : ouverte par une personne -> fermee, avec la marche a suivre
    : >"$F/events"
    DELIVERY_WORKFLOW=true ACTION=opened HEAD=develop BASE=main AUTHOR=dev run "$TICKETS" pr
    [ "$status" -eq 0 ]
    grep -qx "pr-fermee 7" "$F/events"
    [[ "$output" == *"Approve and deploy"* ]] || false
    # ouverte par le workflow (bot) ou instantane livraison/* : jamais fermee
    : >"$F/events"
    DELIVERY_WORKFLOW=true ACTION=opened HEAD=develop BASE=main AUTHOR='github-actions[bot]' run "$TICKETS" pr
    ! grep -q "pr-fermee" "$F/events"
    DELIVERY_WORKFLOW=true ACTION=opened HEAD=livraison/v4.7.0 BASE=main AUTHOR='github-actions[bot]' run "$TICKETS" pr
    ! grep -q "pr-fermee" "$F/events"
}

@test "tickets : ticket termine -> branche sans commit propre supprimee, sinon gardee et signalee" {
    N=12 ticket "validé" "statut: préprod"
    printf 'refs/heads/feat/12-panier\n' >"$F/refs"
    FAKE_AHEAD=0 TAG=v3.6.0 run "$TICKETS" release
    [ "$status" -eq 0 ]
    grep -qx "branche-supprimee feat/12-panier" "$F/events"
    # commits absents de develop : gardee, signalee sur le ticket
    : >"$F/events"
    N=12 ticket "validé" "statut: préprod"
    FAKE_AHEAD=2 TAG=v3.6.1 run "$TICKETS" release
    ! grep -q "branche-supprimee" "$F/events"
    grep -q "feat/12-panier" "$F/issues/12.comments"
    # PR ouverte depuis la branche : gardee
    : >"$F/events"
    N=12 ticket "validé" "statut: préprod"
    FAKE_AHEAD=0 FAKE_PR_HEAD=9 TAG=v3.6.2 run "$TICKETS" release
    ! grep -q "branche-supprimee" "$F/events"
    # ticket sans branche : rien
    : >"$F/events"; : >"$F/refs"
    N=12 ticket "validé" "statut: préprod"
    FAKE_AHEAD=0 TAG=v3.6.3 run "$TICKETS" release
    [ "$status" -eq 0 ]
    ! grep -q "branche-supprimee" "$F/events"
}

@test "tickets : PR brouillon du bot suivie ; ticket ferme par GitHub au merge dans develop -> rouvert en preprod" {
    # PR ouverte par le suivi des tickets (github-actions[bot]) : suivie, pas exemptee
    N=12 ticket "validé" "statut: en relecture"
    printf 'Ticket : #12' >"$F/pr_body"
    AUTHOR='github-actions[bot]' ACTION=closed MERGED=true run "$TICKETS" pr
    [ "$(labels 12 | grep statut)" = "statut: préprod" ]
    # ferme par GitHub au merge d'une PR liee dans develop : rouvert, preprod
    N=13 ticket "validé" "statut: en cours"
    FAKE_CLOSER="7 develop" ISSUE=13 ACTION=closed STATE_REASON=completed run "$TICKETS" issue
    [ "$status" -eq 0 ]
    grep -qx "rouvert 13" "$F/events"
    [ "$(labels 13 | grep statut)" = "statut: préprod" ]
    # ferme par la livraison sur main, a la main, ou deja done : respecte
    : >"$F/events"
    for cas in "FAKE_CLOSER=8 main" "FAKE_CLOSER="; do
        N=14 ticket "validé" "statut: préprod"
        env "$cas" ISSUE=14 ACTION=closed STATE_REASON=completed "$TICKETS" issue
    done
    N=15 ticket "validé" "statut: done"
    FAKE_CLOSER="9 develop" ISSUE=15 ACTION=closed STATE_REASON=completed run "$TICKETS" issue
    ! grep -q "rouvert" "$F/events"
}

@test "tickets : ticket deja livre (preprod, done) -> aucune branche recreee a l'assignation" {
    for st in "statut: préprod" "statut: done"; do
        N=12 ticket "validé" "$st"
        echo moi >"$F/issues/12.assignees"
        ISSUE=12 ACTION=assigned run "$TICKETS" issue
        [ "$status" -eq 0 ]
    done
    ! grep -q "branche-creee" "$F/events"
}

@test "tickets : PR editee apres son merge (run en retard) -> ticket reste en preprod, rien d'arme" {
    # cas #366 : PR #368 mergee, ticket rouvert en preprod et assigne ; l'evenement
    # « edited » de la PR, retarde par la file des runners, passe apres
    N=366 ticket "validé" "type: fix" "statut: préprod"
    echo moi >"$F/issues/366.assignees"
    printf 'Ticket : #366' >"$F/pr_body"
    for action in edited synchronize ready_for_review; do
        PR=368 HEAD=fix/366-bots-release ACTION=$action MERGED=true APP_TOKEN=true run "$TICKETS" pr
        [ "$status" -eq 0 ]
    done
    [ "$(labels 366 | grep statut)" = "statut: préprod" ]
    run grep -qs "merge-auto" "$F/events"
    [ "$status" -ne 0 ]
}

@test "tickets : statut monotone -> preprod et done ne regressent jamais" {
    # PR pas encore vue mergee (evenement anterieur au merge) : statut garde
    N=12 ticket "validé" "statut: préprod"
    printf 'Ticket : #12' >"$F/pr_body"
    ACTION=edited MERGED=false run "$TICKETS" pr
    [ "$status" -eq 0 ]
    [ "$(labels 12 | grep statut)" = "statut: préprod" ]
    [[ "$output" == *"#12"*"préprod"* ]] || false
    # assignation, revue, push : rien ne fait reculer un ticket livre
    N=12 ticket "validé" "statut: done"
    REVIEW_STATE=changes_requested run "$TICKETS" revue
    ISSUE=12 ACTION=assigned run "$TICKETS" issue
    [ "$(labels 12 | grep statut)" = "statut: done" ]
    source "$TICKETS"
    statut 12 "$S_PREPROD"
    [ "$(labels 12 | grep statut)" = "statut: done" ]
    # en avant : inchange
    N=12 ticket "validé" "statut: préprod"
    statut 12 "$S_DONE"
    [ "$(labels 12 | grep statut)" = "statut: done" ]
    N=12 ticket "validé" "statut: en relecture"
    statut 12 "$S_ENCOURS"
    [ "$(labels 12 | grep statut)" = "statut: en cours" ]
}

@test "tickets : merge automatique (squash) arme sur PR prete vers develop, ticket valide, avec l'App seulement" {
    N=12 ticket "validé" "statut: en cours"
    printf 'Ticket : #12' >"$F/pr_body"
    # prete, vers develop, ticket valide, jeton de l'App -> arme
    APP_TOKEN=true ACTION=ready_for_review DRAFT=false run "$TICKETS" pr
    [ "$status" -eq 0 ]
    grep -qx "merge-auto 7" "$F/events"
    [[ "$output" == *"merge automatique armé"* ]] || false
    # sans App : rien d'arme, explication
    : >"$F/events"
    APP_TOKEN=false ACTION=synchronize DRAFT=false run "$TICKETS" pr
    ! grep -q "merge-auto" "$F/events"
    [[ "$output" == *"pas de GitHub App"* ]] || false
    # repassee en brouillon -> desarme
    : >"$F/events"
    APP_TOKEN=true ACTION=converted_to_draft DRAFT=true run "$TICKETS" pr
    grep -qx "merge-desarme 7" "$F/events"
    ! grep -q "merge-auto" "$F/events"
    # autre cible que develop, ou merge automatique desactive : rien
    : >"$F/events"
    APP_TOKEN=true ACTION=synchronize BASE=release/2.0 run "$TICKETS" pr
    APP_TOKEN=true AUTO_MERGE=false ACTION=synchronize run "$TICKETS" pr
    ! grep -q "merge-" "$F/events"
    # ticket non valide : verification en echec, rien d'arme
    N=12 ticket "statut: à valider"
    APP_TOKEN=true ACTION=synchronize run "$TICKETS" pr
    ! grep -q "merge-auto" "$F/events"
}

@test "tickets : ticket valide plus tard -> merge automatique arme sur sa PR prete" {
    N=12 ticket "statut: à valider" "validé"
    printf 'Ticket : #12' >"$F/pr_body"
    FAKE_PRS=$'7\tfeat/12-panier\tabc\tdevelop\tfalse' APP_TOKEN=true ISSUE=12 ACTION=labeled LABEL=validé run "$TICKETS" issue
    [ "$status" -eq 0 ]
    grep -qx "merge-auto 7" "$F/events"
}

@test "tickets : controles (pas des consignes) -> conception, un seul ticket, branche du ticket, commits du meme ticket" {
    N=12 ticket "validé" "statut: en cours"
    printf 'Ticket : #12' >"$F/pr_body"
    # conception absente : refusee
    touch "$F/issues/12.sansconception"
    ACTION=synchronize run "$TICKETS" pr
    [[ "$output" == *"Conception absente sur #12"* ]] || false
    grep -qx "statut-pr failure" "$F/events"
    # reglage : conception non exigee
    : >"$F/events"
    REQUIRE_DESIGN=false ACTION=synchronize run "$TICKETS" pr
    grep -qx "statut-pr success" "$F/events"
    rm "$F/issues/12.sansconception"
    # plusieurs tickets (cas de #236 : #201 et #202 melanges)
    N=13 ticket "validé" "statut: en cours"
    printf 'Tickets : #12, #13' >"$F/pr_body"
    : >"$F/events"
    ACTION=synchronize run "$TICKETS" pr
    [[ "$output" == *"plusieurs tickets (#12, #13)"* ]] || false
    grep -qx "statut-pr failure" "$F/events"
    # branche hors convention (cas de feat/ticket201-test)
    printf 'Ticket : #12' >"$F/pr_body"
    : >"$F/events"
    HEAD=feat/ticket12-test ACTION=synchronize run "$TICKETS" pr
    [[ "$output" == *"doit porter le numéro du ticket"* ]] || false
    grep -qx "statut-pr failure" "$F/events"
    # commit qui cite un autre ticket
    printf 'fix: x\n\nTicket : #12\nfeat: y\n\nTicket : #13\n' >"$F/pr_commits"
    : >"$F/events"
    ACTION=synchronize run "$TICKETS" pr
    [[ "$output" == *"cite le ticket #13"* ]] || false
    grep -qx "statut-pr failure" "$F/events"
    # tout en regle
    printf 'fix: x\n\nTicket : #12\n' >"$F/pr_commits"
    : >"$F/events"
    ACTION=synchronize run "$TICKETS" pr
    grep -qx "statut-pr success" "$F/events"
}

@test "tickets : nom de branche du ticket (type, numero, titre sans accents, tronque)" {
    source "$BATS_TEST_DIRNAME/../hooks/lib/tickets.sh"
    ticket_branch_r 12 "Élargir l'accès à la façade : ÉTAPE 2" fix
    [ "$REPLY" = "fix/12-elargir-l-acces-a-la-facade-etape-2" ]
    ticket_branch_r 7 "Un titre vraiment très long qui dépasse largement la limite fixée"
    [ "$REPLY" = "feat/7-un-titre-vraiment-tres-long-qui-depasse" ]
    ticket_type_r $'statut: backlog\nbug'
    [ "$REPLY" = fix ]
}
