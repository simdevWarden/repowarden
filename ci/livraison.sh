#!/usr/bin/env bash
# Statut « livraison » de la tête de la branche d'intégration, donc de la PR de
# livraison qui en part : la livraison ne peut aboutir que si la protection du
# flux develop est en place (sinon un merge en squash supprimerait develop) et
# si la version annoncée existe en préversion (sinon la release la refuse).
#   ci/livraison.sh             « success|failure<TAB>description »
#   ci/livraison.sh poster SHA  idem, posté en statut « livraison » du commit SHA
#   ci/livraison.sh en-attente  numéro de la PR de livraison ouverte vers MAIN,
#                               rien s'il n'y en a pas
#   ci/livraison.sh commit-livre
#                               commit livré par HEAD : second parent d'un merge
#                               de livraison, sinon HEAD
# Variables : GH_REPO, INTEGRATION, ID (identifiant des préversions, vide :
# aucune), OBLIGATOIRE (true : préversion exigée), PREVERSION_CREEE (tag publié
# dans le même run), INITIAL_VERSION, MAIN (en-attente).
set -euo pipefail

REPOWARDEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../hooks/lib/common.sh
source "$REPOWARDEN_DIR/hooks/lib/common.sh"

: "${GH_REPO:?}" "${INTEGRATION:=develop}"

# REPLY = « état<TAB>description »
etat_r() {
    local regles reglages version reponse
    # 1. Protection du flux develop (rulesets lisibles avec le jeton des Actions ;
    # réglages du dépôt : vérifiés seulement si l'API les renvoie)
    regles="$(gh api "repos/$GH_REPO/rules/branches/$INTEGRATION" --jq '[.[].type] | join(" ")' 2>/dev/null || echo "?")"
    # Rulesets indisponibles (dépôt privé d'un compte gratuit : 403) : aucune
    # règle ne peut interdire la suppression, seuls les réglages comptent
    if ! reponse="$(gh api "repos/$GH_REPO/rulesets" 2>&1)" && [[ "$reponse" == *"403"* ]]; then
        regles="?"
    fi
    reglages="$(gh api "repos/$GH_REPO" --jq '"\(.allow_merge_commit) \(.delete_branch_on_merge)"' 2>/dev/null || echo "? ?")"
    if { [ "$regles" != "?" ] && [[ " $regles " != *" deletion "* ]]; } ||
        [ "${reglages% *}" = false ] || [ "${reglages#* }" = true ]; then
        t ci.livraison.protection "$INTEGRATION"
        REPLY="failure	$REPLY"
        return
    fi
    # 2. Préversion de la version annoncée
    version="$(bash "$REPOWARDEN_DIR/ci/version.sh" next HEAD 2>/dev/null)"
    if [ -z "$version" ]; then
        t ci.livraison.maintenance
        REPLY="success	$REPLY"
    elif [ "${OBLIGATOIRE:-true}" != true ] || [ -z "${ID:-}" ]; then
        t ci.livraison.non_exigee "v$version"
        REPLY="success	$REPLY"
    elif [ -n "${PREVERSION_CREEE:-}" ] || [ -n "$(git tag --contains HEAD --list "v$version-$ID.*")" ]; then
        t ci.livraison.ok "v$version"
        REPLY="success	$REPLY"
    else
        t ci.livraison.preversion "v$version" "v$version-$ID.N" "$INTEGRATION"
        REPLY="failure	$REPLY"
    fi
}

# Première demande de livraison ouverte vers MAIN (une seule à la fois) : sa
# tête est un instantané livraison/*. Les PR de tête develop sont ignorées.
en_attente() {
    gh pr list --base "${MAIN:?}" --state open --json number,headRefName \
        --jq '[.[] | select(.headRefName | startswith("livraison/")) | .number][0] // empty'
}

# Commit livré par HEAD : sur la branche principale, HEAD est le merge commit
# de la livraison, qu'aucune préversion ne contient ; le commit livré est son
# second parent. Sur la branche d'intégration (ou hors merge), c'est HEAD.
commit_livre() {
    git rev-parse --verify -q 'HEAD^2' || git rev-parse HEAD
}

case "${1:-}" in
    en-attente) en_attente ;;
    commit-livre) commit_livre ;;
    *)
        etat_r
        etat="${REPLY%%	*}"
        description="${REPLY#*	}"
        if [ "${1:-}" = poster ]; then
            gh api "repos/$GH_REPO/statuses/${2:?SHA}" -f state="$etat" -f context=livraison \
                -f description="${description:0:140}" >/dev/null
            if [ "$etat" = success ]; then
                echo "::notice::livraison : $description"
            else
                echo "::warning::livraison : $description"
            fi
        else
            printf '%s\t%s\n' "$etat" "$description"
        fi
        ;;
esac
