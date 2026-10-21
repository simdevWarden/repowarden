# shellcheck shell=bash
# Suivi des tickets, événements de ticket (ci/tickets.sh issue) : validation
# (d'office pour un mainteneur), assignation, fermeture.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# Ticket $1 validé : backlog s'il attendait la validation, sa branche, et
# vérification relancée sur les PR ouvertes qui l'attendaient
accepter() {
    local n="$1" pr head sha body base brouillon labels
    labels="$(etiquettes "$n")"
    if grep -qxF "$S_AVALIDER" <<<"$labels"; then
        statut "$n" "$S_BACKLOG"
    fi
    # Décision prise : « à décider » n'a plus lieu d'être
    if grep -qxF "$A_DECIDER" <<<"$labels"; then
        gh issue edit "$n" --remove-label "$A_DECIDER" >/dev/null
    fi
    # La branche naît quand le ticket est pris (assigné) : un ticket validé
    # pour plus tard n'a pas de branche qui vieillit en attendant. Une branche
    # déjà faite à son nom (avant la validation) est reprise, jamais recréée.
    branche_du_ticket_r "$n"
    if [ -n "$REPLY" ] || [ -n "$(assignes "$n")" ]; then
        creer_branche "$n"
    else
        _tr tk.validated_waiting "$n"
        commenter "$n" "$_T"
    fi
    while IFS=$'\t' read -r pr head sha base brouillon; do
        [ -n "$pr" ] || continue
        body="$(gh pr view "$pr" --json body -q .body)"
        pr_tickets_r "$body" "$head"
        [[ " $REPLY " == *" $n "* ]] || continue
        if verifier "$pr" "$sha" "$REPLY" "$head"; then
            merge_auto "$pr" "$base" "$brouillon"
        fi
    done < <(gh pr list --state open --json number,headRefName,headRefOid,baseRefName,isDraft \
        -q '.[] | [.number, .headRefName, .headRefOid, .baseRefName, .isDraft] | @tsv')
}

# Ticket ouvert par un mainteneur (droits d'écriture) : c'est déjà sa
# décision, validé d'office. Vérifié par tout événement du ticket (idempotent) :
# GitHub ne garde qu'un run en attente par groupe de concurrence, le run
# « opened » peut être annulé par ceux des étiquettes posées à la création.
# Non si déjà validé, ou (hors ouverture) rangé au-delà de « à valider »
# (« validé » retiré à la main : décision respectée), ou proposé à décider
# (étiquette « à décider » : le mainteneur pose « validé »). Test seul : appelé dans un « if », où set -e
# ne s'applique pas.
a_valider_d_office() {
    local labels l
    [ "${AUTO_VALIDATE:-maintainers}" = maintainers ] || return 1
    est_mainteneur "${ISSUE_ASSOCIATION:-}" || return 1
    [ "${ISSUE_STATE:-open}" = open ] || return 1
    labels="$(etiquettes "$ISSUE")"
    ! grep -qxF "$VALIDE" <<<"$labels" || return 1
    ! grep -qxF "$A_DECIDER" <<<"$labels" || return 1
    [ "$ACTION" != opened ] || return 0
    while IFS= read -r l; do
        [[ "$l" == "statut: "* && "$l" != "$S_AVALIDER" ]] && return 1
    done <<<"$labels"
    return 0
}

valider_d_office() {
    gh issue edit "$ISSUE" --add-label "$VALIDE" >/dev/null
    statut "$ISSUE" "$S_AVALIDER"
    accepter "$ISSUE"
}

cmd_issue() {
    local pr sha head body
    case "$ACTION" in
        opened)
            est_valide "$ISSUE" && return 0
            # Validé d'office, sinon un mainteneur pose « validé »
            if a_valider_d_office; then
                valider_d_office
            else
                statut "$ISSUE" "$S_AVALIDER"
            fi
            ;;
        labeled)
            if [ "${LABEL:-}" = "$VALIDE" ]; then
                accepter "$ISSUE"
            elif a_valider_d_office; then
                valider_d_office
            fi
            ;;
        assigned)
            if a_valider_d_office; then
                valider_d_office
            fi
            # Pris en charge : sa branche (s'il est validé), en cours s'il est
            # validé ET assigné (quelle que soit la présence du label backlog,
            # pour gérer la race validation+assignation quasi simultanée).
            # Ne passe en cours que s'il n'est pas déjà plus loin (relecture, préprod, done).
            if est_valide "$ISSUE"; then
                creer_branche "$ISSUE"
                local labels
                labels="$(etiquettes "$ISSUE")"
                if grep -qxF "$S_AVALIDER" <<<"$labels" || grep -qxF "$S_BACKLOG" <<<"$labels"; then
                    # Pas de label plus avancé (relecture, préprod, done) ?
                    grep -qxF "$S_RELECTURE" <<<"$labels" && return 0
                    grep -qxF "$S_PREPROD" <<<"$labels" && return 0
                    grep -qxF "$S_DONE" <<<"$labels" && return 0
                    statut "$ISSUE" "$S_ENCOURS"
                fi
            fi
            return 0
            ;;
        closed)
            # Fermé par GitHub au merge d'une PR liée dans la branche par défaut
            # (develop) : pas encore en production, rouvert en préprod. Une
            # fermeture à la main (sans PR) est respectée.
            if [ "${STATE_REASON:-}" = completed ] && ! grep -qxF "$S_DONE" <<<"$(etiquettes "$ISSUE")"; then
                fermee_par_pr_r "$ISSUE"
                local fpr="${REPLY%% *}" fbase="${REPLY#* }"
                if [ -n "$fpr" ] && [ "$fbase" != "${MAIN:-main}" ]; then
                    gh issue reopen "$ISSUE" >/dev/null
                    statut "$ISSUE" "$S_PREPROD"
                    _tr tk.reopened "$fpr" "$fbase"
                    commenter "$ISSUE" "$_T"
                    notice "$_T"
                    return 0
                fi
                # Terminé à la main ou en production : branche restante nettoyée
                nettoyer_branche "$ISSUE"
                return 0
            fi
            # Abandonné : PR fermées, branche supprimée (un ticket terminé est
            # fermé par la release, sa branche est déjà supprimée au merge)
            [ "${STATE_REASON:-}" = not_planned ] || return 0
            branche_du_ticket_r "$ISSUE"
            [ -n "$REPLY" ] || return 0
            local branche="$REPLY"
            while IFS= read -r pr; do
                [ -n "$pr" ] || continue
                _tr tk.abandoned "$ISSUE"
                fermer_pr "$pr" "$_T"
            done < <(gh pr list --state open --head "$branche" --json number -q '.[].number')
            gh api -X DELETE "repos/$GH_REPO/git/refs/heads/$branche" >/dev/null
            notice_t tk.branch_deleted "$branche" "$ISSUE"
            ;;
    esac
}
