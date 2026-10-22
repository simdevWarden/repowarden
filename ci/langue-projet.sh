#!/usr/bin/env bash
# Langue du projet pour un workflow qui ne récupère pas son dépôt (suivi des
# tickets) : sans elle, i18n_init ne trouve aucun .repowarden.conf et la CI
# retombe sur l'anglais.
#   ci/langue-projet.sh     affiche la langue (fr, en…), ou rien
# Priorité : LANG_INPUT (entrée lang du workflow), sinon lang du
# .repowarden.conf de la branche par défaut (API, sans récupérer le dépôt),
# sinon de l'ancien .repogarde.conf. Fichier absent ou API en échec : rien
# (code 0), la CI garde alors l'anglais.
# Variables : GH_REPO (propriétaire/nom), LANG_INPUT.
set -euo pipefail

# Lit lang dans un fichier de réglages du projet, par l'API : le contenu brut
# suffit, et git config le lit comme cfg_load (clés repowarden.* et repogarde.*)
lang_du_fichier() {
    local tmp lang=""
    tmp="$(mktemp)"
    if gh api -H 'Accept: application/vnd.github.raw' "repos/$GH_REPO/contents/$1" >"$tmp" 2>/dev/null; then
        lang="$(git config -f "$tmp" --get repowarden.lang 2>/dev/null ||
            git config -f "$tmp" --get repogarde.lang 2>/dev/null || true)"
    fi
    rm -f "$tmp"
    printf '%s' "$lang"
}

# Langue retenue : l'entrée du workflow, puis le nouveau nom de fichier avant
# l'ancien (comme cfg_load, le nouveau l'emporte)
langue_projet() {
    local lang="${LANG_INPUT:-}"
    GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"
    if [ -z "$lang" ] && [ -n "$GH_REPO" ]; then
        lang="$(lang_du_fichier .repowarden.conf)"
        [ -n "$lang" ] || lang="$(lang_du_fichier .repogarde.conf)"
    fi
    [ -z "$lang" ] || printf '%s\n' "$lang"
}

langue_projet
