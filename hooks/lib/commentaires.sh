#!/usr/bin/env bash
# Fonctions ajoutées sans commentaire : chaque nouvelle fonction doit dire,
# juste au-dessus, ce qu'elle fait et pourquoi (docstring acceptée en Python).
# Comme pour le code mort, seul le code ajouté compte : une fonction dont le
# nom existait déjà dans le fichier n'est jamais signalée, même retouchée.
# Avertissement seulement (pre-commit et CI), désactivable par skip = comments.
# Langages : Shell (.sh, .bash, ou shebang sh/bash), Python, JavaScript/TypeScript.

# Une ligne « fichier:ligne<TAB>nom » par fonction ajoutée sans commentaire
# entre $1 (commit de base) et $2 (commit, ou vide pour le contenu stagé).
comments_missing() {
    local base="$1" new="$2" a b f old lang added tmp
    tmp="$(mktemp -d)"
    while IFS=$'\t' read -r _ a b; do
        [ -n "$a" ] || continue
        # Renommage ou copie : l'ancien chemin donne les fonctions existantes
        if [ -n "$b" ]; then old="$a" f="$b"; else old="$a" f="$a"; fi
        is_excluded "$f" && continue
        git show "$new:$f" >"$tmp/new" 2>/dev/null || continue
        comments_lang_r "$f" "$tmp/new"
        lang="$REPLY"
        [ -n "$lang" ] || continue
        git show "$base:$old" >"$tmp/base" 2>/dev/null || : >"$tmp/base"
        if [ -n "$new" ]; then
            git diff -U0 --no-color --no-ext-diff "$base" "$new" -- "$f"
        else
            git diff --cached -U0 --no-color --no-ext-diff "$base" -- "$f"
        fi 2>/dev/null >"$tmp/diff"
        # Numéros des lignes ajoutées ou modifiées, d'après les en-têtes @@
        added="$(awk '/^@@/ {
            split($3, a, ","); s = substr(a[1], 2); n = (a[2] == "" ? 1 : a[2])
            for (i = 0; i < n; i++) printf " %d", s + i
        }' "$tmp/diff") "
        [ "$added" != " " ] || continue
        awk -v lang="$lang" -v added="$added" -v f="$f" -v q="'" "$COMMENTS_AWK_LIB$COMMENTS_AWK" "$tmp/base" "$tmp/new"
    done < <(
        if [ -n "$new" ]; then
            git diff --name-status -M --diff-filter=ACMR "$base" "$new"
        else
            git diff --cached --name-status -M --diff-filter=ACMR "$base"
        fi 2>/dev/null
    )
    rm -rf "$tmp"
}

# REPLY = langage du fichier $1 pour la détection des fonctions (shell, py,
# js), vide sinon ; $2 = son contenu, dont le shebang décide sans extension.
# Partagé par le contrôle et la carte (repowarden carte) : une seule détection.
comments_lang_r() {
    local l=""
    case "${1##*/}" in
        *.sh | *.bash) REPLY=shell; return 0 ;;
        *.py) REPLY=py; return 0 ;;
        *.js | *.jsx | *.mjs | *.cjs | *.ts | *.tsx) REPLY=js; return 0 ;;
        *.*) REPLY=""; return 0 ;;
    esac
    # Script sans extension (bin/…) : seul un shebang sh ou bash compte
    IFS= read -r l <"$2" 2>/dev/null || true
    if [[ "$l" =~ ^#!.*[/\ ](ba)?sh([[:space:]]|$) ]]; then REPLY=shell; else REPLY=""; fi
}

# Avertit des fonctions ajoutées sans commentaire, sans jamais bloquer : le
# commentaire aide la relecture, son absence n'est pas une faute. REPLY = nombre.
comments_check() {
    local loc name n=0
    while IFS=$'\t' read -r loc name; do
        [ -n "$loc" ] || continue
        n=$((n + 1))
        attention_t cm.missing "$loc" "$name"
    done < <(comments_missing "$1" "$2")
    [ "$n" = 0 ] || info_t cm.summary "$n"
    REPLY="$n"
}

# Bibliothèque awk commune au contrôle et à la carte : déclarations de
# fonctions et commentaire au-dessus (variables lang et q)
# shellcheck disable=SC2016 # programme awk, rien à développer
COMMENTS_AWK_LIB='
# Nom de la fonction déclarée par la ligne l (vide sinon), selon le langage
function nom(l) {
    if (lang == "shell") {
        if (l ~ /^[ \t]*function[ \t]+[A-Za-z_]/) {
            sub(/^[ \t]*function[ \t]+/, "", l); sub(/[ \t(){}].*$/, "", l); return l
        }
        if (l ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_:.@-]*[ \t]*\(\)/) {
            sub(/^[ \t]*/, "", l); sub(/[ \t]*\(\).*$/, "", l); return l
        }
    } else if (lang == "py") {
        if (l ~ /^[ \t]*(async[ \t]+)?def[ \t]+[A-Za-z_]/) {
            sub(/^[ \t]*(async[ \t]+)?def[ \t]+/, "", l); sub(/[^A-Za-z0-9_].*$/, "", l); return l
        }
    } else {
        if (l ~ /^[ \t]*(export[ \t]+(default[ \t]+)?)?(async[ \t]+)?function[ \t]*\*?[ \t]*[A-Za-z_$]/) {
            sub(/^[ \t]*(export[ \t]+(default[ \t]+)?)?(async[ \t]+)?function[ \t]*\*?[ \t]*/, "", l)
            sub(/[^A-Za-z0-9_$].*$/, "", l); return l
        }
        if (l ~ /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*(:[^=]*)?=[ \t]*(async[ \t]+)?(function[^A-Za-z0-9_$]|function$|\([^)]*\)[^=]*=>|[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=>)/) {
            sub(/^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+/, "", l); sub(/[^A-Za-z0-9_$].*$/, "", l); return l
        }
    }
    return ""
}
# Directive d outil (shellcheck, eslint, noqa…) : n explique rien, on regarde au-dessus
function directive(l) {
    return l ~ /^[ \t]*(#|\/\/)[ \t]*(shellcheck|noqa|type:|pylint:|eslint|@ts-|prettier-)/
}
# Commentaire juste au-dessus de la ligne i (décorateurs et directives sautés),
# ou docstring en tête du corps pour Python
function commentee(i,   j, s) {
    for (j = i - 1; j > 0 && (L[j] ~ /^[ \t]*@/ || directive(L[j])); j--) ;
    if (j > 0 && L[j] !~ /^#!/ && L[j] ~ /^[ \t]*(#|\/\/|\/\*|\*)/) return 1
    if (lang != "py") return 0
    # Fin de la signature (deux-points en fin de ligne), puis première ligne non vide
    for (j = i; j <= N && j < i + 20 && L[j] !~ /:[ \t]*(#.*)?$/; j++) ;
    for (j++; j <= N && L[j] ~ /^[ \t]*$/; j++) ;
    s = "^[ \t]*[rRuUbBfF]*[\"" q "]"
    return j <= N && L[j] ~ s
}
# Texte des lignes de commentaire contiguës juste au-dessus de la ligne i,
# jointes par une espace (décorateurs et directives sautés), vide sinon
function commentaire(i,   j, s, t) {
    s = ""
    for (j = i - 1; j > 0 && L[j] !~ /^#!/ && (L[j] ~ /^[ \t]*@/ || L[j] ~ /^[ \t]*(#|\/\/|\/\*|\*)/); j--) {
        if (L[j] ~ /^[ \t]*@/ || directive(L[j])) continue
        t = L[j]
        sub(/^[ \t]*(#+|\/\/+|\/\*+|\*+)[ \t]*/, "", t); sub(/[ \t]*\*\/[ \t]*$/, "", t)
        gsub(/\t/, " ", t); sub(/[ \t]+$/, "", t)
        if (t != "") s = (s == "" ? t : t " " s)
    }
    return s
}
'

# Programme awk de comments_missing : lit le fichier de base (noms des
# fonctions existantes) puis le nouveau, et signale les fonctions nouvelles
# dont aucune ligne de commentaire ne précède la déclaration
# shellcheck disable=SC2016 # programme awk, rien à développer
COMMENTS_AWK='
FILENAME == ARGV[1] { n = nom($0); if (n != "") ancien[n] = 1; next }
{ L[FNR] = $0; N = FNR }
END {
    for (i = 1; i <= N; i++) {
        if (index(added, " " i " ") == 0) continue
        n = nom(L[i])
        if (n == "" || (n in ancien) || commentee(i)) continue
        print f ":" i "\t" n
    }
}'
