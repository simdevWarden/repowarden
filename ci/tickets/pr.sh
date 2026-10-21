# shellcheck shell=bash
# Suivi des tickets, événements de PR (ci/tickets.sh pr) : ticket créé s'il
# manque, statuts, PR sans objet depuis main ou develop, vérification.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

cmd_pr() {
    local body tickets n url
    : "${PR:?}" "${HEAD:?}" "${HEAD_SHA:?}" "${ACTION:?}"
    # PR partant d'une branche persistante : seules la livraison (develop →
    # main) et le retour (main → develop, si main a un contenu propre) ont un
    # sens ; les autres sont fermées, avec la marche à suivre
    if [[ "$HEAD" == "${INTEGRATION:-develop}" || "$HEAD" == "${MAIN:-main}" ]] &&
        [[ "$ACTION" == opened || "$ACTION" == reopened ]]; then
        if [[ "$HEAD" == "${INTEGRATION:-develop}" && "${BASE:-}" != "${MAIN:-main}" ]] ||
            [[ "$HEAD" == "${MAIN:-main}" && "${BASE:-}" != "${INTEGRATION:-develop}" ]]; then
            _tr tk.pr_inverted "$HEAD" "${BASE:-}" "${INTEGRATION:-develop}"
            fermer_pr "$PR" "$_T"
            notice "$_T"
        elif [ "$HEAD" = "${MAIN:-main}" ] &&
            [ "$(gh api "repos/$GH_REPO/compare/$BASE...$HEAD" -q '.files | length')" = 0 ]; then
            _tr tk.pr_backmerge_empty "$HEAD" "$BASE"
            fermer_pr "$PR" "$_T"
            notice "$_T"
        # Livraison ouverte par le workflow de release : celle d'une personne
        # n'aurait jamais d'approbation de déploiement, elle resterait bloquée
        elif [ "$HEAD" = "${INTEGRATION:-develop}" ] && [ "${DELIVERY_WORKFLOW:-false}" = true ] &&
            [[ "${AUTHOR:-}" != *"[bot]" ]]; then
            _tr tk.pr_delivery_manual "$HEAD" "$BASE" "$HEAD" "$HEAD"
            fermer_pr "$PR" "$_T"
            notice "$_T"
            return 0
        fi
    fi
    # Bots de dépendances, PR de release, livraisons et retours : pas de ticket
    # exigé. Les PR ouvertes par le suivi des tickets lui-même (jeton des
    # Actions, github-actions[bot]) citent leur ticket : suivies normalement.
    if [[ "${AUTHOR:-}" =~ ^(dependabot|renovate)(\[bot\])?$ || "$HEAD" == release-please--* || "$HEAD" == livraison/* ||
        "$HEAD" == "${INTEGRATION:-develop}" || "$HEAD" == "${MAIN:-main}" ]]; then
        gh api "repos/$GH_REPO/statuses/$HEAD_SHA" -f state=success -f context=ticket \
            -f description="Sans ticket (bot, release ou livraison)" >/dev/null
        return 0
    fi
    body="$(gh pr view "$PR" --json body -q .body)"
    pr_tickets_r "$body" "$HEAD"
    tickets="$REPLY"

    if [ "$ACTION" = closed ]; then
        [ "${MERGED:-false}" = true ] || return 0
        for n in $tickets; do
            statut "$n" "$S_PREPROD"
            _tr tk.merged "$PR" "$BASE"
            commenter "$n" "$_T"
        done
        return 0
    fi
    # PR déjà mergée, événement en retard (edited, synchronize…) : le ticket est
    # livré, ni statut, ni vérification, ni merge automatique
    [ "${MERGED:-false}" != true ] || return 0

    # Aucun ticket : si auto-create activé, créé à partir de la PR, à valider,
    # et relié à la PR ; sinon, échec de la vérification avec la marche à suivre.
    if [ -z "$tickets" ]; then
        if [ "${AUTO_CREATE:-false}" = true ]; then
            _tr tk.created_body "$PR"
            url="$(gh issue create --title "$(gh pr view "$PR" --json title -q .title)" \
                --body "$_T" --label "$S_AVALIDER")"
            tickets="${url##*/}"
            gh pr edit "$PR" --body "$(printf '%s\n\nTicket : #%s\n' "$body" "$tickets")" >/dev/null
            notice_t tk.created "$tickets" "$PR"
        else
            _tr tk.created_body "$PR"
            gh api "repos/$GH_REPO/statuses/$HEAD_SHA" -f state=failure -f context=ticket \
                -f description="PR sans ticket : créez-en un avec 'repowarden ticket nouveau \"<titre>\"' ou citez 'Ticket : #N' dans la description" >/dev/null
            return 0
        fi
    fi

    # Statut du travail (seulement pour un ticket validé)
    for n in $tickets; do
        est_valide "$n" || continue
        if [ "${DRAFT:-false}" = true ]; then statut "$n" "$S_ENCOURS"; else statut "$n" "$S_RELECTURE"; fi
    done
    # Le blocage est porté par le statut « ticket » (exigé par la protection) :
    # le job reste vert, un rouge signale une vraie panne
    if verifier "$PR" "$HEAD_SHA" "$tickets" "$HEAD"; then
        merge_auto "$PR" "${BASE:-}" "${DRAFT:-false}"
    fi
}
