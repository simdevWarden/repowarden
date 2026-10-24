#!/usr/bin/env bash
# Carte du projet (repowarden carte) : quoi fait quoi et pourquoi, sans LLM ni
# réseau, pour qu'un agent (ou une personne) lise l'extrait utile au lieu
# d'explorer le dépôt. Fichier .repowarden/carte/carte.json, dossier ignoré
# par git ; clés triées, ni date ni chemin absolu : même dépôt, même fichier.
# Les fonctions et leur « pourquoi » viennent de la détection du contrôle
# « fonctions sans commentaire » (commentaires.sh) : pas de second analyseur.
# Demande commentaires.sh (via lang.sh) et common.sh ; lancé à la racine.

# shellcheck disable=SC2016 # programmes jq et awk entre apostrophes, rien à développer
CARTE_DIR=.repowarden/carte
CARTE_JSON="$CARTE_DIR/carte.json"

# jq sans retour chariot : sous Windows, jq finit ses lignes par CRLF, et un
# read garderait le CR collé à la dernière valeur lue
cjq() { jq "$@" | tr -d '\r'; }

# Fichiers lus par la carte, dans le dossier $1 : « shell » (fichiers
# cartographiés, hors repowarden.exclude) et « tests » (*.bats, tous)
carte_fichiers() {
    local f
    : >"$1/shell"
    : >"$1/tests"
    while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        case "$f" in *.bats) printf '%s\n' "$f" >>"$1/tests"; continue ;; esac
        is_excluded "$f" && continue
        comments_lang_r "$f" "$f"
        [ "$REPLY" != shell ] || printf '%s\n' "$f" >>"$1/shell"
    done < <(git ls-files -z -co --exclude-standard)
}

# Écrit la carte (remplacement atomique : une lecture concurrente voit
# l'ancienne ou la nouvelle) ; le dossier s'ignore lui-même pour git
carte_generer() {
    local d f
    local -a shell=() tests=()
    mkdir -p "$CARTE_DIR"
    [ -f "$CARTE_DIR/.gitignore" ] || printf '*\n' >"$CARTE_DIR/.gitignore"
    d="$(mktemp -d)"
    carte_fichiers "$d"
    while IFS= read -r f; do shell+=("$f"); done <"$d/shell"
    while IFS= read -r f; do tests+=("$f"); done <"$d/tests"
    : >"$d/fonctions"
    : >"$d/liens"
    if [ ${#shell[@]} -gt 0 ]; then
        # « fichier<TAB>ligne<TAB>nom<TAB>pourquoi » par fonction
        awk -v lang=shell -v q="'" "$COMMENTS_AWK_LIB$CARTE_AWK" "${shell[@]}" >"$d/fonctions"
        # « fichier<TAB>test » par test qui le couvre
        [ ${#tests[@]} -eq 0 ] ||
            awk "$CARTE_TESTS_AWK" "$d/shell" "${tests[@]}" >"$d/liens"
    fi
    jq -n -S --rawfile s "$d/shell" --rawfile fo "$d/fonctions" --rawfile li "$d/liens" '
        def lignes($x): $x | split("\n") | map(select(length > 0) | split("\t"));
        (lignes($fo) | group_by(.[0]) | map({key: .[0][0], value:
            map({nom: .[2], ligne: (.[1] | tonumber), pourquoi: (.[3] // "")})
            | sort_by(.ligne)}) | from_entries) as $fn
        | (lignes($li) | group_by(.[0])
            | map({key: .[0][0], value: (map(.[1]) | unique)}) | from_entries) as $te
        | {version: 1, fichiers: (lignes($s) | map(.[0])
            | map({key: ., value: {fonctions: ($fn[.] // []), tests: ($te[.] // [])}})
            | from_entries)}' >"$d/carte.json"
    mv -f "$d/carte.json" "$CARTE_JSON"
    rm -rf "$d"
}

# Vrai si la carte existe et qu'aucun fichier du dépôt (suivi, ou nouveau non
# ignoré) ni l'index git n'est plus récent : sinon elle ne dit plus le code
carte_a_jour() {
    local f
    [ -f "$CARTE_JSON" ] || return 1
    f="$(git rev-parse --git-path index)"
    [ ! "$f" -nt "$CARTE_JSON" ] || return 1
    while IFS= read -r -d '' f; do
        [ ! "$f" -nt "$CARTE_JSON" ] || return 1
    done < <(git ls-files -z -co --exclude-standard)
    return 0
}

# Fonctions du fichier $1 (chemin depuis la racine) : une ligne chacune,
# « ligne  nom — pourquoi », puis ses tests ; JSON de son entrée si $2 = json
carte_fichier() {
    local f="$1" ligne nom pourquoi tests n=0
    if [ "${2:-}" = json ]; then
        jq --arg f "$f" '{fichier: $f} + (.fichiers[$f] // {fonctions: []})' "$CARTE_JSON"
        return 0
    fi
    printf '%s%s%s\n' "$UI_B" "$f" "$UI_N"
    while IFS=$'\t' read -r ligne nom pourquoi; do
        n=$((n + 1))
        if [ -n "$pourquoi" ]; then
            printf '  %s  %s — %s\n' "$ligne" "$nom" "$pourquoi"
        else
            t carte.no_comment
            printf '  %s  %s %s\n' "$ligne" "$nom" "$REPLY"
        fi
    done < <(cjq -r --arg f "$f" '(.fichiers[$f].fonctions // [])[] | "\(.ligne)\t\(.nom)\t\(.pourquoi)"' "$CARTE_JSON")
    [ "$n" -gt 0 ] || info_t carte.file_empty "$f"
    # Tests liés : ceux à écrire d'abord, puis à relancer
    jq -e --arg f "$f" '.fichiers | has($f)' "$CARTE_JSON" >/dev/null || return 0
    tests="$(cjq -r --arg f "$f" '.fichiers[$f].tests // [] | join(" ")' "$CARTE_JSON")"
    if [ -n "$tests" ]; then
        echo_t carte.tests "$tests"
        echo_t carte.tests_run "bats $tests"
    else
        info_t carte.no_tests "$f"
    fi
}

# Définitions de la fonction $1 : « nom  fichier:ligne » puis son pourquoi ;
# JSON (liste) si $2 = json. Code 1 si la carte ne la connaît pas
carte_fonction() {
    local nom="$1" f ligne pourquoi n=0
    if [ "${2:-}" = json ]; then
        jq -e --arg n "$nom" '[.fichiers | to_entries[] | .key as $f
            | .value.fonctions[]? | select(.nom == $n) | {fichier: $f} + .]
            | if length > 0 then . else empty end' "$CARTE_JSON" && return 0
        err_t carte.unknown "$nom"
        return 1
    fi
    while IFS=$'\t' read -r f ligne pourquoi; do
        n=$((n + 1))
        printf '%s%s%s  %s:%s\n' "$UI_B" "$nom" "$UI_N" "$f" "$ligne"
        if [ -n "$pourquoi" ]; then
            printf '  %s\n' "$pourquoi"
        else
            t carte.no_comment
            printf '  %s\n' "$REPLY"
        fi
    done < <(cjq -r --arg n "$nom" '.fichiers | to_entries[] | .key as $f
        | .value.fonctions[]? | select(.nom == $n) | "\($f)\t\(.ligne)\t\(.pourquoi)"' "$CARTE_JSON")
    [ "$n" -gt 0 ] && return 0
    err_t carte.unknown "$nom"
    return 1
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
# Fichier en CRLF (extraction Windows) : le CR ne fait pas partie du texte
{ sub(/\r$/, ""); L[FNR] = $0; N = FNR }
END { if (NR > 0) sortie() }'


# Programme awk des tests liés : lit la liste des fichiers cartographiés, puis
# chaque test ; relie un fichier à un test par le nommage (même nom sans
# extension), par son chemin cité, ou par « repowarden <commande> » (bin/…)
# shellcheck disable=SC2016 # programme awk, rien à développer
CARTE_TESTS_AWK='
# Nom sans dossier ni extension : bin/garde, test/garde.bats → garde
function base(p) { sub(/^.*\//, "", p); sub(/\.[^.\/]*$/, "", p); return p }
# Vrai si le texte x cite le chemin p, sans autre caractère de nom collé
function cite(x, p,   k, av, ap) {
    while ((k = index(x, p)) > 0) {
        av = (k > 1) ? substr(x, k - 1, 1) : ""
        ap = substr(x, k + length(p), 1)
        if (av !~ /[A-Za-z0-9_-]/ && ap !~ /[A-Za-z0-9_.-]/) return 1
        x = substr(x, k + 1)
    }
    return 0
}
# Liens du test t (texte complet x) vers les fichiers cartographiés
function liens(   i, bt, r, c, cmd) {
    bt = base(t)
    split("", cmd)
    r = x
    while (match(r, /repowarden[ \t]+[a-z][a-z0-9-]*/)) {
        c = substr(r, RSTART, RLENGTH); sub(/^repowarden[ \t]+/, "", c)
        cmd["bin/" c] = 1
        r = substr(r, RSTART + RLENGTH)
    }
    for (i = 1; i <= nf; i++)
        if (base(F[i]) == bt || (F[i] in cmd) || cite(x, F[i])) print F[i] "\t" t
}
FILENAME == ARGV[1] { F[++nf] = $0; next }
FNR == 1 { if (t != "") liens(); t = FILENAME; x = "" }
{ sub(/\r$/, ""); x = x "\n" $0 }
END { if (t != "") liens() }'
