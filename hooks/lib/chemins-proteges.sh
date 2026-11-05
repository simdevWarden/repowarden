#!/usr/bin/env bash
# Chemins protégés contre les agents (agentsProtectedPaths, #541) : le
# mainteneur liste des motifs (jokers du shell, relatifs à la racine) que le
# garde-fou refuse à un agent, à l'écriture comme au commit. Chargé par bin/garde.

# PROTEGES = motifs du réglage agentsProtectedPaths : union de .repowarden.conf
# de l'arbre et de celui de HEAD, pour qu'en retirer un de l'arbre ne lève rien.
# Le git config est ignoré ici : un « git config … "" » suffirait sinon.
proteges_charger() {
    local blob lu
    [ -n "${CFG_LOADED:-}" ] || cfg_load
    PROTEGES=""
    if cfg_lookup agentsProtectedPaths "$CFG_FILE"; then PROTEGES="$REPLY"; fi
    for blob in HEAD:.repowarden.conf HEAD:.repogarde.conf; do
        lu="$(git config --blob "$blob" --get-regexp '^(repogarde|repowarden)\.' 2>/dev/null || true)"
        if cfg_lookup agentsProtectedPaths "$lu"; then PROTEGES="$PROTEGES $REPLY"; fi
    done
}

# Vrai si le chemin $1 (relatif à la racine) correspond à un motif de PROTEGES ;
# un motif fini par / protège tout son dossier
chemin_protege() {
    local c="${1#./}" m motifs=()
    [ -n "$c" ] || return 1
    read -ra motifs <<<"${PROTEGES:-}"
    for m in ${motifs[@]+"${motifs[@]}"}; do
        m="${m#./}"
        [ -n "$m" ] || continue
        # shellcheck disable=SC2053 # le motif est voulu : jokers du shell
        [[ "$c" == $m ]] && return 0
        case "$m" in */) [[ "$c" == "$m"* ]] && return 0 ;; esac
    done
    return 1
}

# REPLY = chemins (un par ligne) que commiterait « commit » avec les mots $@ :
# l'index, plus les fichiers suivis modifiés avec -a/--all ; avec des chemins
# donnés, seulement ceux-là (plus l'index avec -i/--include)
commit_chemins_r() {
    local mot suite="" fin="" tous="" inclure="" chemins=() g=(git -c core.quotepath=off)
    for mot in "$@"; do
        if [ -n "$suite" ]; then suite=""; continue; fi
        if [ -n "$fin" ]; then chemins+=("$mot"); continue; fi
        case "$mot" in
            --) fin=1 ;;
            --all) tous=1 ;;
            -i | --include) inclure=1 ;;
            # Options dont la valeur est le mot suivant (git commit et cc)
            --message | --file | --reuse-message | --reedit-message | --template | --author | \
                --date | --cleanup | --trailer | --fixup | --squash | --type | --scope | \
                --body | --refs | --breaking) suite=1 ;;
            --*) ;;
            -[!-]*)
                [[ "$mot" != *a* ]] || tous=1
                [[ "$mot" != *[mFCct] ]] || suite=1
                ;;
            *) chemins+=("$mot") ;;
        esac
    done
    REPLY=""
    if [ "${#chemins[@]}" -gt 0 ]; then
        REPLY="$("${g[@]}" diff --no-renames --name-only HEAD -- "${chemins[@]}" 2>/dev/null || true)"
        [ -z "$inclure" ] || REPLY="$REPLY"$'\n'"$("${g[@]}" diff --cached --no-renames --name-only 2>/dev/null || true)"
        return 0
    fi
    REPLY="$("${g[@]}" diff --cached --no-renames --name-only 2>/dev/null || true)"
    [ -z "$tous" ] || REPLY="$REPLY"$'\n'"$("${g[@]}" diff --no-renames --name-only 2>/dev/null || true)"
}

# Refuse (code 2) le commit de mots $@ si un changement commité touche un
# chemin protégé ; sans réglage, ne coûte rien
verifier_commit_chemins() {
    local c
    proteges_charger
    [ -n "${PROTEGES// /}" ] || return 0
    commit_chemins_r "$@"
    while IFS= read -r c; do
        [ -z "$c" ] || ! chemin_protege "$c" || refuser garde.chemin_protege "$c"
    done <<<"$REPLY"
}
