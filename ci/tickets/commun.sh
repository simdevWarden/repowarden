# shellcheck shell=bash
# Suivi des tickets, outils communs : étiquettes et assignés d'un ticket,
# changement de statut, ticket validé, mainteneur, tickets cités par une PR,
# PR qui a fermé un ticket, notices.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# Ligne de description lue comme référence de ticket (« Ticket : #12 », mot-clé
# de fermeture) : partagée avec la PR brouillon, qui cite ces lignes reprises
REF_TICKET_RE='^[[:space:]]*(Tickets?|Refs?|Closes|Fixes|Resolves)[[:space:]]*:?[[:space:]]*(.*)$'

# REPLY = numéros de tickets (uniques) cités par la description $1 (« Ticket : #12 »,
# « Tickets : #3, #4 », ou un mot-clé de fermeture) et la branche $2 (type/12-sujet)
pr_tickets_r() {
    local body="$1" branch="$2" found="" n line
    while IFS= read -r line; do
        if [[ "$line" =~ $REF_TICKET_RE ]]; then
            for n in $(grep -oE '#[0-9]+' <<<"${BASH_REMATCH[2]}" | tr -d '#'); do
                [[ " $found " == *" $n "* ]] || found="$found $n"
            done
        fi
    done <<<"$body"
    branch_ticket_r "$branch"
    n="$REPLY"
    if [ -n "$n" ]; then
        [[ " $found " == *" $n "* ]] || found="$found $n"
    fi
    REPLY="${found# }"
}

# Rang d'un statut dans le cycle (REPLY) : à valider 0 … done 5, -1 sinon
rang_statut_r() {
    case "$1" in
        "$S_AVALIDER") REPLY=0 ;; "$S_BACKLOG") REPLY=1 ;; "$S_ENCOURS") REPLY=2 ;;
        "$S_RELECTURE") REPLY=3 ;; "$S_PREPROD") REPLY=4 ;; "$S_DONE") REPLY=5 ;;
        *) REPLY=-1 ;;
    esac
}

# Statut $2 sur le ticket $1 : remplace les autres étiquettes « statut: ».
# Monotone pour un travail livré : un ticket en préprod ou done ne recule
# jamais (événement en retard, branche réapparue, réassignation…), signalé.
statut() {
    local n="$1" s="$2" l retirer=() cible
    rang_statut_r "$s"
    cible="$REPLY"
    while IFS= read -r l; do
        [[ "$l" == "statut: "* && "$l" != "$s" ]] || continue
        rang_statut_r "$l"
        if [ "$REPLY" -ge 4 ] && [ "$REPLY" -gt "$cible" ]; then
            notice_t tk.status_kept "$n" "${l#statut: }" "${s#statut: }"
            return 0
        fi
        retirer+=(--remove-label "$l")
    done < <(gh issue view "$n" --json labels -q '.labels[].name' 2>/dev/null || true)
    # ${a[@]+…} : tableau vide accepté sous set -u par le bash 3.2 de macOS
    gh issue edit "$n" --add-label "$s" ${retirer[@]+"${retirer[@]}"} >/dev/null
}

# Ferme la PR $1 avec le commentaire $2 ; déjà fermée ou mergée entre-temps
# (merge pendant le run) : rien à faire, pas un échec
fermer_pr() {
    gh pr close "$1" --comment "$2" >/dev/null 2>&1 && return 0
    [ "$(gh pr view "$1" --json state -q .state 2>/dev/null)" != OPEN ]
}

etiquettes() { gh issue view "$1" --json labels -q '.labels[].name' 2>/dev/null || true; }

# REPLY = « <n° de PR> <branche cible> » de la PR dont le merge a fermé le
# ticket $1, vide si le ticket a été fermé autrement (à la main, release…)
fermee_par_pr_r() {
    # shellcheck disable=SC2016 # variables GraphQL, pas du shell
    REPLY="$(gh api graphql -f query='query($o: String!, $r: String!, $n: Int!) {
  repository(owner: $o, name: $r) { issue(number: $n) {
    timelineItems(last: 1, itemTypes: CLOSED_EVENT) { nodes { ... on ClosedEvent {
      closer { ... on PullRequest { number baseRefName } } } } } } } }' \
        -f o="${GH_REPO%%/*}" -f r="${GH_REPO#*/}" -F n="$1" \
        -q '.data.repository.issue.timelineItems.nodes[0].closer // empty | "\(.number) \(.baseRefName)"' \
        2>/dev/null || true)"
}

# Personnes assignées au ticket $1 (une par ligne)
assignes() { gh issue view "$1" --json assignees -q '.assignees[].login' 2>/dev/null || true; }

est_mainteneur() { [[ "${1:-}" =~ ^(OWNER|MEMBER|COLLABORATOR)$ ]]; }

est_valide() { grep -qxF "$VALIDE" <<<"$(etiquettes "$1")"; }

notice() { echo "::notice title=repowarden::$*"; }

notice_t() { _tr "$@"; notice "$_T"; }

# Chargé par les tests (source) : fonctions seulement
