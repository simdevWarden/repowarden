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
# cartographiés), « tous » (fichiers du dépôt, rattachables à des tickets),
# tous deux hors repowarden.exclude, et « tests » (*.bats, tous)
carte_fichiers() {
    local f
    : >"$1/shell"
    : >"$1/tests"
    : >"$1/tous"
    while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        case "$f" in *.bats) printf '%s\n' "$f" >>"$1/tests" ;; esac
        is_excluded "$f" && continue
        printf '%s\n' "$f" >>"$1/tous"
        case "$f" in *.bats) continue ;; esac
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
    # « fichier<TAB>ticket » par fichier modifié par un ticket (git seul)
    git -c core.quotePath=false log --no-color --diff-merges=first-parent --name-only \
        --format='%x1e%s%n%b%x1f' 2>/dev/null |
        awk -v D=$'\x1e' -v F=$'\x1f' "$CARTE_HIST_AWK" >"$d/historique" || true
    if [ ${#shell[@]} -gt 0 ]; then
        # « fichier<TAB>ligne<TAB>nom<TAB>pourquoi » par fonction
        awk -v lang=shell -v q="'" "$COMMENTS_AWK_LIB$CARTE_AWK" "${shell[@]}" >"$d/fonctions"
        # « fichier<TAB>test » par test qui le couvre
        [ ${#tests[@]} -eq 0 ] ||
            awk "$CARTE_TESTS_AWK" "$d/shell" "${tests[@]}" >"$d/liens"
    fi
    jq -n -S --rawfile s "$d/shell" --rawfile fo "$d/fonctions" --rawfile li "$d/liens" \
        --rawfile to "$d/tous" --rawfile hi "$d/historique" '
        def lignes($x): $x | split("\n") | map(select(length > 0) | split("\t"));
        (lignes($fo) | group_by(.[0]) | map({key: .[0][0], value:
            map({nom: .[2], ligne: (.[1] | tonumber), pourquoi: (.[3] // "")})
            | sort_by(.ligne)}) | from_entries) as $fn
        | (lignes($li) | group_by(.[0])
            | map({key: .[0][0], value: (map(.[1]) | unique)}) | from_entries) as $te
        | (lignes($to) | map({key: .[0], value: 1}) | from_entries) as $ok
        | (lignes($hi) | map(select($ok[.[0]] != null))) as $h
        | ($h | group_by(.[0])
            | map({key: .[0][0], value: (map(.[1] | tonumber) | unique)}) | from_entries) as $tf
        | {version: 1,
           fichiers: (($tf | map_values({tickets: .})) + (lignes($s) | map(.[0])
            | map({key: ., value: {fonctions: ($fn[.] // []), tests: ($te[.] // []),
                tickets: ($tf[.] // [])}})
            | from_entries)),
           tickets: ($h | group_by(.[1])
            | map({key: .[0][1], value: {fichiers: (map(.[0]) | unique)}}) | from_entries)}' >"$d/carte.json"
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
# « ligne  nom — pourquoi », puis ses tests et tickets ; JSON si $2 = json
carte_fichier() {
    local f="$1" ligne nom pourquoi tests tickets n=0
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
    # Tests liés (fichiers cartographiés) : ceux à écrire d'abord, puis à relancer
    if jq -e --arg f "$f" '.fichiers[$f] | has("tests")' "$CARTE_JSON" >/dev/null 2>&1; then
        tests="$(cjq -r --arg f "$f" '.fichiers[$f].tests | join(" ")' "$CARTE_JSON")"
        if [ -n "$tests" ]; then
            echo_t carte.tests "$tests"
            echo_t carte.tests_run "bats $tests"
        else
            info_t carte.no_tests "$f"
        fi
    fi
    # Tickets qui l'ont modifié : le pourquoi de son histoire
    tickets="$(cjq -r --arg f "$f" '(.fichiers[$f].tickets // []) | map("#\(.)") | join(" ")' "$CARTE_JSON")"
    [ -z "$tickets" ] || echo_t carte.tickets "$tickets"
}

# Fichiers modifiés par le ticket $1 (numéro, sans #) ; JSON si $2 = json.
# Code 1 si l'historique git ne le cite pas
carte_ticket() {
    local n="$1" f c=0
    if [ "${2:-}" = json ]; then
        jq -e -S --arg n "$n" '.tickets[$n] // empty | {ticket: ($n | tonumber)} + .' "$CARTE_JSON" && return 0
        err_t carte.ticket_unknown "$n" "$n" "$n"
        return 1
    fi
    while IFS= read -r f; do
        c=$((c + 1))
        [ "$c" -gt 1 ] || { t carte.ticket_title "$n"; printf '%s%s%s\n' "$UI_B" "$REPLY" "$UI_N"; }
        printf '  %s\n' "$f"
    done < <(cjq -r --arg n "$n" '(.tickets[$n].fichiers // [])[]' "$CARTE_JSON")
    [ "$c" -gt 0 ] && return 0
    err_t carte.ticket_unknown "$n" "$n" "$n"
    return 1
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

# Programme awk de l'historique : lit « git log --name-only » (en-tête de
# commit précédé de D, fin du message marquée par F) et écrit
# « fichier<TAB>ticket » pour chaque ticket du commit (pieds « Ticket : #n »,
# branche type/<n>-sujet d'une fusion) et chaque fichier modifié
# shellcheck disable=SC2016 # programme awk, rien à développer
CARTE_HIST_AWK='
# Tickets cités par la ligne l, si c est un pied « Ticket(s) : #n »
function pied(l) {
    if (l !~ /^[ \t]*[Tt][Ii][Cc][Kk][Ee][Tt][Ss]?[ \t]*:[ \t]*#[0-9]/) return
    while (match(l, /#[0-9]+/)) {
        T[substr(l, RSTART + 1, RLENGTH - 1) + 0] = 1
        l = substr(l, RSTART + RLENGTH)
    }
}
index($0, D) == 1 {
    split("", T); msg = 1; $0 = substr($0, 2)
    if ($0 ~ /^Merge / && match($0, /[A-Za-z]+\/[0-9]+-/)) {
        b = substr($0, RSTART, RLENGTH); sub(/^[A-Za-z]+\//, "", b); T[b + 0] = 1
    }
}
msg {
    k = index($0, F)
    if (k > 0) { pied(substr($0, 1, k - 1)); msg = 0 } else pied($0)
    next
}
{ sub(/\r$/, "") }
$0 != "" { for (n in T) print $0 "\t" n }'
