# shellcheck shell=bash
# Suivi des tickets, mise en route sur un dépôt existant (ci/tickets.sh
# adopter, appelé par repowarden tickets init).
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# Mise en route sur un dépôt existant (tickets init, relançable) : tickets
# ouverts sans statut rangés (validé ou ouvert par un mainteneur → backlog,
# sinon, ou « à décider », à valider) ; branches des PR ouvertes et mergées inscrites sur les
# tickets qu'elles citent. Aucune branche créée en masse : elle naît quand le
# ticket est pris (repowarden ticket N).
cmd_adopter() {
    local n assoc labels pr head ranges=0 t
    while IFS=$'\t' read -r n assoc; do
        [ -n "$n" ] || continue
        labels="$(etiquettes "$n")"
        ! grep -q '^statut: ' <<<"$labels" || continue
        if grep -qxF "$VALIDE" <<<"$labels"; then
            statut "$n" "$S_BACKLOG"
        elif [ "${AUTO_VALIDATE:-maintainers}" = maintainers ] && est_mainteneur "$assoc" \
            && ! grep -qxF "$A_DECIDER" <<<"$labels"; then
            gh issue edit "$n" --add-label "$VALIDE" >/dev/null
            statut "$n" "$S_BACKLOG"
        else
            statut "$n" "$S_AVALIDER"
        fi
        ranges=$((ranges + 1))
    done < <(gh api "repos/$GH_REPO/issues?state=open&per_page=100" --paginate \
        -q '.[] | select(.pull_request | not) | [.number, .author_association] | @tsv')
    while IFS=$'\t' read -r pr head; do
        [ -n "$pr" ] || continue
        [[ "$head" != "${INTEGRATION:-develop}" && "$head" != release-please--* ]] || continue
        pr_tickets_r "$(gh pr view "$pr" --json body -q .body)" "$head"
        for t in $REPLY; do inscrire_branche "$t" "$head" "PR #$pr"; done
    done < <(gh pr list --state all --limit 1000 --json number,headRefName,state \
        -q '.[] | select(.state != "CLOSED") | [.number, .headRefName] | @tsv')
    _tr tk.adopted "$ranges" "$INSCRITES"
    echo "$_T"
}
