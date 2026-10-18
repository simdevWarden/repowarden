#!/usr/bin/env bash
# Détection de code mort : seul le NOUVEAU code mort compte (lignes ajoutées ou
# modifiées depuis la base), pour que la dette ne grossisse plus sans noyer un
# projet existant sous son historique.
#
# Chaque plugin de langage peut fournir <plugin>_deadcode, lancé à la racine du
# projet, qui écrit une ligne par élément :
#   niveau<TAB>fichier<TAB>ligne<TAB>message
#   niveau : prouve   (inaccessible, inutilisé dans sa portée : sûr à 100 %)
#            candidat (non référencé dans le projet : appel dynamique possible)
#   ligne  : 0 si l'élément concerne tout le fichier (fichier, dépendance)
#
# Réglages : deadcode = block (défaut : le prouvé bloque, les candidats avertissent)
#            | warn (rien ne bloque) | strict (tout bloque)
#            deadcodeIgnore = chemins ignorés (motifs, comme exclude)

# Code mort introduit depuis $1 (base) dans les fichiers lus sur stdin.
# Retour : 1 si un élément bloque selon le réglage deadcode.
deadcode_projects() {
    local base="$1" changed added found partial dir p plugins niveau f l msg path proven=0 cand=0 mode ignore pat code var
    local ran="" file tmp partiel=0
    # Un dossier temporaire unique : les fichiers de l'analyse, dont le
    # fichier témoin de l'analyse partielle (voir deadcode_partial)
    tmp="$(mktemp -d)"
    changed="$tmp/changed"
    added="$tmp/added"
    found="$tmp/found"
    partial="$tmp/partial"
    : >"$partial"
    DEADCODE_PARTIAL_FILE="$partial"
    export DEADCODE_PARTIAL_FILE
    cat >"$changed"

    # Lignes ajoutées ou modifiées (fichier:ligne), du commit de base à
    # l'arbre de travail (en CI, identique au commit vérifié)
    git diff -U0 --no-color --no-ext-diff "$base" -- 2>/dev/null | awk '
        /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); next }
        /^@@/ {
            split($3, a, ","); s = substr(a[1], 2); n = (a[2] == "" ? 1 : a[2])
            for (i = 0; i < n; i++) print f ":" (s + i)
        }' >"$added"
    # Fichiers pas encore suivis (analyse locale) : toutes leurs lignes sont nouvelles
    { git ls-files --others --exclude-standard 2>/dev/null | grep -xFf "$changed" || true; } |
        while IFS= read -r f; do
            awk -v f="$f" '{ print f ":" NR }' "$f"
        done >>"$added"

    cfg_r deadcodeIgnore ""
    ignore="$REPLY"
    # Projets touchés (fichier marqueur : pom.xml, package.json…), puis
    # fichiers isolés d'un langage autonome (script Python sans projet…),
    # analysés depuis la racine
    while IFS= read -r dir; do
        plugins=""
        active_plugins_init
        if [ "${dir#\*}" != "$dir" ]; then
            plugins="${dir#\*}"
            dir=.
            # Fichiers isolés (hors projet) : analyse seulement si du code de ce
            # langage a changé ; des .md ou .yml rattachés à node pour le
            # formatage ne justifient pas une analyse JavaScript
            plugin_get "$plugins" EXT
            code="$REPLY"
            var="$(printf '%s' "$plugins" | tr '[:lower:]' '[:upper:]')_CODE_EXT"
            [ -z "${!var:-}" ] || code="${!var}"
            grep -qE "$code" "$changed" || continue
        else
            for p in $ACTIVE_PLUGINS; do
                has_marker "$dir" "$p" && declare -F "${p}_deadcode" >/dev/null && plugins="$plugins $p"
            done
        fi
        for p in $plugins; do
            [[ " $ran " == *" $dir:$p "* ]] && continue
            ran="$ran $dir:$p"
            # Un outil d'analyse renvoie souvent un code d'erreur quand il trouve
            # quelque chose : seule sa sortie compte
            { (cd "$dir" && "${p}_deadcode") </dev/null || true; } |
                while IFS=$'\t' read -r niveau f l msg; do
                    [ -n "$f" ] || continue
                    f="${f#"$PWD/$dir/"}"
                    f="${f#./}"
                    if [ "$dir" = . ]; then path="$f"; else path="$dir/$f"; fi
                    if [ "${l:-0}" = 0 ]; then
                        grep -qxF "$path" "$changed" || continue
                    else
                        grep -qxF "$path:$l" "$added" || continue
                    fi
                    set -f
                    for pat in $ignore; do
                        # shellcheck disable=SC2254
                        case "$path" in $pat) set +f; continue 2 ;; esac
                    done
                    set +f
                    printf '%s\t%s\t%s\n' "$niveau" "$path${l:+:$l}" "$msg"
                done >>"$found"
        done
    done < <(
        projects_for_files <"$changed" || true # aucun projet : pas une erreur
        while IFS= read -r file; do
            plugins_for_file_r "$file"
            for p in $REPLY; do
                plugin_has_flag "$p" standalone && declare -F "${p}_deadcode" >/dev/null && echo "*$p"
            done
        done <"$changed" | sort -u
    )

    while IFS=$'\t' read -r niveau path msg; do
        path="${path%:0}"
        if [ "$niveau" = prouve ]; then
            proven=$((proven + 1))
            if declare -F ci_error_t >/dev/null; then ci_error_t dc.proven "$path" "$msg"
            else err_t dc.proven "$path" "$msg"
            fi
        else
            cand=$((cand + 1))
            attention_t dc.candidate "$path" "$msg"
        fi
    done <"$found"
    # Une analyse partielle (outil absent) interdit tout feu vert sans réserve
    [ ! -s "$partial" ] || partiel=1
    rm -rf "$tmp"

    if [ -z "$ran" ]; then
        info_t dc.nothing
        return 0
    fi
    if [ "$proven" = 0 ] && [ "$cand" = 0 ]; then
        if [ "$partiel" = 1 ]; then attention_t dc.none_partial
        else ok_t dc.none
        fi
        return 0
    fi
    [ "$cand" = 0 ] || info_t dc.summary_candidates "$cand"
    cfg_r deadcode block
    mode="$REPLY"
    case "$mode" in
        warn) return 0 ;;
        strict)
            err_t dc.summary_strict "$((proven + cand))"
            return 1
            ;;
        *)
            [ "$proven" = 0 ] && return 0
            err_t dc.summary_proven "$proven"
            return 1
            ;;
    esac
}

# Outil d'analyse absent : signalé, sans faire échouer le mode strict
# (la détection de code mort reste une aide, pas un prérequis du projet).
# Un outil totalement absent compte comme une analyse partielle.
deadcode_tool_missing() {
    attention_t dc.tool_missing "$1" "$2"
    deadcode_partial_note "$1"
}

# Analyse partielle : $1 langage, $2 outil absent, $3 ce qui n'est pas analysé
# (déjà traduit, clé dc.scope.*), $4 installation à donner.
# Un des outils du langage manque : ce qu'il couvre n'est pas analysé, et la
# fin de l'analyse ne dira pas que tout va bien (voir deadcode_projects).
deadcode_partial() {
    attention_t dc.partial "$1" "$2" "$3" "$4"
    deadcode_partial_note "$1"
}

# Note l'analyse partielle : les plugins tournent dans un sous-shell de tube
# ({ … } |), une variable ne reviendrait pas — le signal passe par un fichier
# témoin sous le dossier temporaire de l'analyse
deadcode_partial_note() {
    [ -n "${DEADCODE_PARTIAL_FILE:-}" ] || return 0
    printf '%s\n' "$1" >>"$DEADCODE_PARTIAL_FILE"
}

# Java (Maven, Gradle) : règles PMD dont le résultat est prouvé — import,
# champ, méthode ou variable privés jamais utilisés dans leur portée
JAVA_DEADCODE_RULES="category/java/bestpractices.xml/UnusedPrivateMethod,category/java/bestpractices.xml/UnusedPrivateField,category/java/bestpractices.xml/UnusedLocalVariable,category/java/bestpractices.xml/UnusedFormalParameter,category/java/codestyle.xml/UnnecessaryImport"
java_deadcode() {
    has pmd || { deadcode_tool_missing Java pmd; return 0; }
    [ -d src ] || return 0
    # « src/a/A.java:3:<TAB>Règle:<TAB>message »
    # code de sortie 4 = violations trouvées : attendu
    { pmd check --no-progress --no-cache -d src -f text -R "$JAVA_DEADCODE_RULES" 2>/dev/null || true; } |
        awk -F'\t' 'NF >= 3 { n = split($1, a, ":"); print "prouve\t" a[1] "\t" a[2] "\t" $3 }'
}
