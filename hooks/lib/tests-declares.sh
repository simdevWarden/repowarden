#!/usr/bin/env bash
# Où chercher la déclaration « Tests retirés : <raison> » (#545).
# Fonctions de lecture seule : aucune n'écrit ni n'échoue (set -e sûr).

# Motif ERE de la ligne de déclaration (fr et en)
TESTS_DECL_MOTIF='^Tests (retirés|removed) *: .'

# REPLY = descriptions des PR GitHub qui ont produit les commits de $1..HEAD,
# pour que le push qui suit une fusion et la PR de livraison retrouvent la
# déclaration écrite dans une PR déjà fusionnée. Sans gh, jeton ou dépôt :
# REPLY vide. Au plus 50 appels, une PR n'est lue qu'une fois.
tests_prs_fusionnees_r() {
    REPLY=""
    command -v gh >/dev/null 2>&1 || return 0
    [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] || return 0
    local sha n appels=0 vus=" " corps texte=""
    while IFS= read -r sha; do
        [ -n "$sha" ] || continue
        [ "$appels" -lt 50 ] || break
        appels=$((appels + 1))
        while IFS= read -r n; do
            [[ "$n" =~ ^[0-9]+$ ]] || continue
            [[ "$vus" != *" $n "* ]] || continue
            vus="$vus$n "
            [ "$appels" -lt 50 ] || break
            appels=$((appels + 1))
            corps="$(GH_TOKEN="$GITHUB_TOKEN" gh api "repos/$GITHUB_REPOSITORY/pulls/$n" --jq '.body // ""' 2>/dev/null || true)"
            texte="$texte$corps"$'\n'
            # Déclaration trouvée : inutile de lire la suite
            if grep -qE "$TESTS_DECL_MOTIF" <<<"$corps"; then
                REPLY="$texte"
                return 0
            fi
        done < <(GH_TOKEN="$GITHUB_TOKEN" gh api "repos/$GITHUB_REPOSITORY/commits/$sha/pulls" --jq '.[].number' 2>/dev/null || true)
    done < <(git rev-list --first-parent "$1..HEAD")
    REPLY="$texte"
}

# Succès si la plage $1..HEAD porte une déclaration de tests retirés : dans la
# description de la PR courante, dans un message de commit de la plage, ou
# (GitHub) dans la description d'une PR fusionnée qui a produit ces commits
tests_declares_r() {
    grep -qE "$TESTS_DECL_MOTIF" <<<"${REPOWARDEN_PR_BODY:-${CI_MERGE_REQUEST_DESCRIPTION:-}}" && return 0
    grep -qE "$TESTS_DECL_MOTIF" <<<"$(git log --format=%B "$1..HEAD")" && return 0
    tests_prs_fusionnees_r "$1"
    grep -qE "$TESTS_DECL_MOTIF" <<<"$REPLY"
}
