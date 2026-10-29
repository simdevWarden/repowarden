# shellcheck shell=bash
# Suivi des tickets, vérification « ticket » d'une PR (statut de commit
# exigé par la protection) et merge automatique des PR de travail.
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# Vrai si le ticket $1 porte une conception écrite par un mainteneur (commentaire
# « Conception retenue ») : le code suit une conception relue, pas l'inverse
conception_ecrite() {
    local corps
    corps="$(gh issue view "$1" --json comments -q '.comments[]
        | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR")
        | .body' 2>/dev/null || true)"
    grep -qi "conception retenue" <<<"$corps"
}

# REPLY = premier autre ticket que $2 cité par un commit de la PR $1 (« Ticket : #M »)
autre_ticket_r() {
    local cites n
    cites="$(gh pr view "$1" --json commits -q '.commits[].messageBody' 2>/dev/null || true)"
    REPLY=""
    for n in $(grep -oiE '^[[:space:]]*tickets?[[:space:]]*:[[:space:]]*#[0-9]+' <<<"$cites" | grep -oE '[0-9]+' || true); do
        if [ "$n" != "$2" ]; then REPLY="$n"; return 0; fi
    done
    return 1
}

# Vérification « ticket » (statut de commit) de la PR $1, commit $2, tickets
# $3, branche $4. Contrôles (pas des consignes) : un seul ticket, validé,
# porté par la branche (type/N-sujet), avec sa conception écrite ; aucun
# commit d'un autre ticket.
verifier() {
    local pr="$1" sha="$2" tickets="$3" head="${4:-}" n attente="" liste
    for n in $tickets; do est_valide "$n" || attente="$attente #$n"; done
    [ -z "$head" ] || branch_ticket_r "$head"
    if [ -z "$tickets" ]; then
        _tr tk.none; etat=failure
    elif [ "$(wc -w <<<"$tickets")" -gt 1 ]; then
        _tr tk.multi "#${tickets// /, #}"; etat=failure
    elif [ -n "$attente" ]; then
        _tr tk.waiting "${attente# }" "$VALIDE"; etat=failure
    elif [ -n "$head" ] && [ -z "$REPLY" ]; then
        _tr tk.bad_branch "$head" "$tickets"; etat=failure
    elif [ "${REQUIRE_DESIGN:-true}" = true ] && ! conception_ecrite "$tickets"; then
        _tr tk.no_design "$tickets"; etat=failure
    elif autre_ticket_r "$pr" "$tickets"; then
        _tr tk.other_ticket "$REPLY" "$tickets"; etat=failure
    else
        liste=""
        for n in $tickets; do liste="$liste #$n"; done
        _tr tk.ok "${liste# }"; etat=success
    fi
    echo "$_T"
    gh api "repos/$GH_REPO/statuses/$sha" -f state="$etat" -f context=ticket \
        -f description="${_T:0:140}" >/dev/null
    [ "$etat" = success ]
}

# Merge automatique (squash) de la PR de travail $1, cible $2, brouillon $3 :
# armé quand elle est prête, vise la branche d'intégration et que son ticket
# est validé (appelé après une vérification réussie) ; désarmé en brouillon.
# Seulement avec le jeton de l'App : un merge fait avec le jeton des Actions ne
# déclencherait aucun workflow (préversion, livraison, tickets).
merge_auto() {
    local pr="$1" base="$2" brouillon="$3"
    local expected online online_ok missing _rest _one
    [ "${AUTO_MERGE:-true}" = true ] && [ "$base" = "${INTEGRATION:-develop}" ] || return 0
    if [ "$brouillon" = true ]; then
        gh pr merge "$pr" --disable-auto >/dev/null 2>&1 || true
        return 0
    fi
    if [ "${APP_TOKEN:-false}" != true ]; then
        notice_t tk.automerge_no_app "$pr"
        return 0
    fi
    # Vérifications attendues (requiredChecks) vs règles en ligne : si une
    # vérification attendue manque en ligne, l'auto-merge n'est pas armé, on
    # signale et on commente la PR une seule fois (repère regles-perimees).
    # Absence de requiredChecks : rien à comparer, comportement historique.
    # Échec de lecture des règles (droits, réseau) : on arme comme avant.
    cfg_r requiredChecks ""
    expected="$REPLY"
    if [ -n "$expected" ]; then
        online_ok=0
        online="$(gh api "repos/$GH_REPO/rules/branches/$base" \
            --jq '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' \
            2>/dev/null)" && online_ok=1 || online_ok=0
        if [ "$online_ok" = 1 ]; then
            missing=""
            # Parcours des vérifications attendues (virgule), espaces possibles
            _rest="$expected"
            while [ -n "$_rest" ]; do
                case "$_rest" in
                    *,*) _one="${_rest%%,*}"; _rest="${_rest#*,}" ;;
                    *) _one="$_rest"; _rest="" ;;
                esac
                # suppression des espaces de bord
                _one="${_one#"${_one%%[![:space:]]*}"}"
                _one="${_one%"${_one##*[![:space:]]}"}"
                [ -z "$_one" ] && continue
                if ! grep -Fxq "$_one" <<<"$online"; then
                    if [ -z "$missing" ]; then missing="$_one"; else missing="$missing, $_one"; fi
                fi
            done
            if [ -n "$missing" ]; then
                notice_t tk.automerge_rules_stale "$pr" "$missing" "$expected"
                if ! gh pr view "$pr" --json comments -q '.comments[].body' 2>/dev/null \
                        | grep -qF '<!-- repowarden:regles-perimees -->'; then
                    _tr tk.automerge_rules_stale "$pr" "$missing" "$expected"
                    gh pr comment "$pr" --body "$_T"$'\n\n''<!-- repowarden:regles-perimees -->' \
                        >/dev/null 2>&1 || true
                fi
                return 0
            fi
        else
            notice_t tk.automerge_rules_unread "$pr"
        fi
    fi
    if gh pr merge "$pr" --auto --squash >/dev/null 2>&1; then
        notice_t tk.automerge_armed "$pr"
    else
        notice_t tk.automerge_failed "$pr"
    fi
}
