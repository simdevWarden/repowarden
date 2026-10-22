# shellcheck shell=bash
# Suivi des tickets, préversion, release ou livraison sans nouvelle version
# (ci/tickets.sh release) : tickets prévenus, ou passés en done et fermés.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# TAG : release (vX.Y.Z) ou préversion (vX.Y.Z-next.N) ; sans TAG,
# DELIVERED_SHA : commit livré sur la branche principale sans nouvelle version
# (livraison sans fix ni feat), les tickets livrés sont fermés tout de même
cmd_release() {
    local n tag="${TAG:-}" sha="${DELIVERED_SHA:-}"
    if [ -n "$tag" ]; then
        if [[ "$tag" == *-* ]]; then _tr tk.prerelease "$tag"; else _tr tk.released "$tag"; fi
    elif [ -n "$sha" ]; then
        _tr tk.delivered "${MAIN:-main}" "${sha:0:7}"
    else
        echo "ci/tickets.sh release : TAG ou DELIVERED_SHA requis" >&2
        return 2
    fi
    local msg="$_T"
    while IFS= read -r n; do
        [ -n "$n" ] || continue
        if [[ "$tag" == *-* ]]; then
            commenter "$n" "$msg"
        else
            statut "$n" "$S_DONE"
            pied_r "$msg"
            gh issue close "$n" --comment "$REPLY" >/dev/null
            nettoyer_branche "$n"
        fi
    done < <(gh issue list --state open --label "$S_PREPROD" --limit 500 --json number -q '.[].number')
}
