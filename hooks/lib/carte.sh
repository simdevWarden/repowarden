#!/usr/bin/env bash
# Carte du projet (repowarden carte) : quoi fait quoi et pourquoi, sans LLM ni
# réseau, pour qu'un agent (ou une personne) lise l'extrait utile au lieu
# d'explorer le dépôt. Fichier .repowarden/carte/carte.json, dossier ignoré
# par git ; clés triées, ni date ni chemin absolu : même dépôt, même fichier.
# Les fonctions et leur « pourquoi » viennent de la détection du contrôle
# « fonctions sans commentaire » (commentaires.sh) : pas de second analyseur.
# Demande commentaires.sh (via lang.sh) et common.sh ; lancé à la racine.

CARTE_DIR=.repowarden/carte
CARTE_JSON="$CARTE_DIR/carte.json"

# Une ligne « fichier<TAB>ligne<TAB>nom<TAB>pourquoi » par fonction des
# fichiers du dépôt (suivis, ou nouveaux non ignorés) ; shell seulement
carte_fonctions() {
    local f
    local -a fichiers=()
    while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        is_excluded "$f" && continue
        comments_lang_r "$f" "$f"
        [ "$REPLY" != shell ] || fichiers+=("$f")
    done < <(git ls-files -z -co --exclude-standard)
    [ ${#fichiers[@]} -gt 0 ] || return 0
    awk -v lang=shell -v q="'" "$COMMENTS_AWK_LIB$CARTE_AWK" "${fichiers[@]}"
}

# Écrit la carte (remplacement atomique : une lecture concurrente voit
# l'ancienne ou la nouvelle) ; le dossier s'ignore lui-même pour git
carte_generer() {
    local tmp
    mkdir -p "$CARTE_DIR"
    [ -f "$CARTE_DIR/.gitignore" ] || printf '*\n' >"$CARTE_DIR/.gitignore"
    tmp="$CARTE_JSON.$$"
    carte_fonctions | jq -R -s -S '
        split("\n") | map(select(length > 0) | split("\t"))
        | group_by(.[0])
        | map({key: .[0][0], value: {fonctions:
            map({nom: .[2], ligne: (.[1] | tonumber), pourquoi: (.[3] // "")})
            | sort_by(.ligne)}})
        | {version: 1, fichiers: from_entries}' >"$tmp"
    mv -f "$tmp" "$CARTE_JSON"
}

# Programme awk de la carte : chaque fonction de chaque fichier lu, avec sa
# ligne et le texte de son commentaire (vide s'il n'y en a pas)
# shellcheck disable=SC2016 # programme awk, rien à développer
CARTE_AWK='
# Fonctions du fichier f (lignes L[1..N])
function sortie(   i, n) {
    for (i = 1; i <= N; i++) {
        n = nom(L[i])
        if (n != "") printf "%s\t%d\t%s\t%s\n", f, i, n, commentaire(i)
    }
}
FNR == 1 { if (NR > 1) sortie(); f = FILENAME; N = 0 }
{ L[FNR] = $0; N = FNR }
END { if (NR > 0) sortie() }'
