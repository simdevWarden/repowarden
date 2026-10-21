# shellcheck shell=bash
# Suivi des tickets, branche du ticket : registre des branches (repère dans
# les commentaires du bot), branche existante, création liée au ticket.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# Registre (REPERE, repere, branches_inscrites_r) : hooks/lib/tickets.sh,
# partagé avec repowarden ticket.

# Inscrit la branche $2 sur le ticket $1, une seule fois ($3 : origine, ex. PR #7).
# Une seconde branche pour le même ticket est inscrite et signalée.
INSCRITES=0

inscrire_branche() {
    local n="$1" b="$2" origine="${3:-}"
    branches_inscrites_r "$n"
    [[ " $REPLY " != *" $b "* ]] || return 0
    if [ -n "$REPLY" ]; then
        _tr tk.branch_second "$b" "${REPLY// /, }"
        notice "$_T"
    else
        _tr tk.branch_registered "$b"
    fi
    [ -z "$origine" ] || _T="$_T ($origine)"
    commenter "$n" "$_T"$'\n\n'"$(repere "$b")"
    INSCRITES=$((INSCRITES + 1))
}

# REPLY = branche du dépôt portant le ticket $1 (type/<n>-…), vide si aucune
branche_du_ticket_r() {
    local ref
    REPLY=""
    while IFS= read -r ref; do
        ref="${ref#refs/heads/}"
        branch_ticket_r "$ref"
        if [ "$REPLY" = "$1" ]; then REPLY="$ref"; return 0; fi
        REPLY=""
    done < <(gh api "repos/$GH_REPO/git/matching-refs/heads/" --paginate -q '.[].ref' 2>/dev/null || true)
}

# Ticket $1 terminé : sa branche, si elle existe encore (travail passé par une
# autre branche), est supprimée quand elle n'apporte rien à la branche
# d'intégration et qu'aucune PR ouverte n'en part ; sinon gardée et signalée
nettoyer_branche() {
    local n="$1" branche avance prs
    branche_du_ticket_r "$n"
    branche="$REPLY"
    [ -n "$branche" ] || return 0
    prs="$(gh pr list --state open --head "$branche" --json number -q 'map("#\(.number)") | join(" ")')"
    avance="$(gh api "repos/$GH_REPO/compare/${INTEGRATION:-develop}...$branche" -q .ahead_by 2>/dev/null || true)"
    if [ -z "$prs" ] && [ "$avance" = 0 ]; then
        gh api -X DELETE "repos/$GH_REPO/git/refs/heads/$branche" >/dev/null
        notice_t tk.branch_deleted "$branche" "$n"
    else
        _tr tk.branch_kept "$branche" "${avance:-?}" "${prs:--}"
        commenter "$n" "$_T"
    fi
}

# Ticket $1 validé : sa branche naît de la branche d'intégration, liée au
# ticket (panneau « Development »). Rien si une PR ouverte cite déjà le ticket
# (travail commencé hors de sa branche) ; si elle existe déjà, jamais recréée :
# faite avant la validation, elle n'est pas liée et son lien est inscrit.
creer_branche() {
    local n="$1" titre labels branche pr head body
    # Travail déjà mergé ou en production : plus de branche à (re)créer
    travail_termine "$(etiquettes "$n")" && return 0
    branche_du_ticket_r "$n"
    if [ -n "$REPLY" ]; then
        ticket_note_unlinked_branch "$n" "$REPLY" || true
        return 0
    fi
    while IFS=$'\t' read -r pr head; do
        [ -n "$pr" ] || continue
        body="$(gh pr view "$pr" --json body -q .body)"
        pr_tickets_r "$body" "$head"
        [[ " $REPLY " != *" $n "* ]] || return 0
    done < <(gh pr list --state open --json number,headRefName -q '.[] | [.number, .headRefName] | @tsv')
    titre="$(gh issue view "$n" --json title -q .title)"
    labels="$(etiquettes "$n")"
    ticket_type_r "$labels"
    ticket_branch_r "$n" "$titre" "$REPLY"
    branche="$REPLY"
    # shellcheck disable=SC2016 # variables GraphQL, pas du shell
    gh api graphql -f query='mutation($issue: ID!, $repo: ID!, $oid: GitObjectID!, $name: String!) {
  createLinkedBranch(input: {issueId: $issue, repositoryId: $repo, oid: $oid, name: $name}) { linkedBranch { id } }
}' -f issue="$(gh issue view "$n" --json id -q .id)" \
        -f repo="$(gh api "repos/$GH_REPO" -q .node_id)" \
        -f oid="$(gh api "repos/$GH_REPO/git/ref/heads/$INTEGRATION" -q .object.sha)" \
        -f name="$branche" >/dev/null
    _tr tk.branch_created "$branche" "$INTEGRATION" "$n" "$branche"
    commenter "$n" "$_T"$'\n\n'"$(repere "$branche")"
    notice_t tk.branch_notice "$branche" "$n"
}
