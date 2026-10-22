#!/usr/bin/env bash
# Charte visuelle de repowarden : mêmes symboles et couleurs partout (hooks,
# CI, assistant, installation). Couleurs dans un terminal ou si FORCE_COLOR
# est défini (logs de CI) ; jamais avec NO_COLOR, TERM=dumb ou une sortie
# redirigée (fichiers, tubes, tests). Compatible bash 3.2.
# shellcheck disable=SC2034 # couleurs utilisées par les scripts qui sourcent ce fichier

# Anciens noms (REPOGARDE_*) : lus avant tout le reste
# shellcheck source=compat.sh
source "$(dirname "${BASH_SOURCE[0]}")/compat.sh"

if [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ] &&
    { [ -n "${FORCE_COLOR:-}" ] || [ -t 2 ]; }; then
    UI_B=$'\033[1m' UI_D=$'\033[2m' UI_N=$'\033[0m'
    UI_G=$'\033[32m' UI_R=$'\033[31m' UI_Y=$'\033[33m' UI_BL=$'\033[34m' UI_C=$'\033[36m'
else
    UI_B="" UI_D="" UI_N="" UI_G="" UI_R="" UI_Y="" UI_BL="" UI_C=""
fi

ok() { echo "${UI_G}✔${UI_N} $*"; }
info() { echo "${UI_BL}ℹ${UI_N} $*"; }
step() { echo "${UI_C}▶${UI_N} ${UI_B}$*${UI_N}"; }
err() { echo "${UI_R}✖${UI_N} ${UI_B}$*${UI_N}" >&2; }
# Avertissement affiché seulement (warn, dans common.sh, compte aussi pour le mode strict)
attention() { echo "${UI_Y}⚠${UI_N} $*" >&2; }
# Texte secondaire (aides, détails)
dim() { echo "${UI_D}$*${UI_N}"; }
# REPLY = version de l'installation repowarden $1 : paquet npm (package.json,
# écrit à la publication) ; clone (dépôt git) : dernier tag vX.Y.Z atteint
repowarden_version_r() {
    local tag=""
    REPLY="$(sed -n 's/^  "version": *"\([^"]*\)".*/\1/p' "$1/package.json" 2>/dev/null | sed -n 1p)"
    if [ -e "$1/.git" ]; then
        # Sous-shell sans les variables que git exporte aux hooks (worktree) :
        # elles l'emportent sur -C, ce seraient les tags du projet. Tag le plus
        # proche de HEAD (git describe), remplacé par un tag de release dont le
        # commit mergé est au moins aussi proche : la release est taguée sur le
        # merge de la livraison dans main, invisible depuis develop pour
        # describe ; à égalité, la version stable l'emporte sur la préversion
        tag="$(
            unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
            best="$(git -C "$1" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
            dist=""
            [ -z "$best" ] || dist="$(git -C "$1" rev-list --count "$best..HEAD")"
            while IFS= read -r t; do
                git -C "$1" merge-base --is-ancestor "$t^2" HEAD 2>/dev/null || continue
                d="$(git -C "$1" rev-list --count "$t^2..HEAD")"
                if [ -z "$best" ] || [ "$d" -lt "$dist" ] ||
                    { [ "$d" -eq "$dist" ] && [[ "$t" != *-* && "$best" == *-* ]]; }; then
                    best="$t" dist="$d"
                fi
            done < <(git -C "$1" tag --no-merged HEAD --list 'v[0-9]*' 2>/dev/null)
            echo "$best"
        )"
        [ -z "$tag" ] || REPLY="${tag#v}"
    fi
}

# REPLY = version majeure dont le tag flottant (vN) est publié, pour la
# version $1 de repowarden : sa majeure ; préversion d'une nouvelle majeure
# (X.0.0-next) : X-1, vX n'existant pas encore ; 0.0.0-dev (clone sans
# tags) : vide. REPOWARDEN_MAJEURE l'impose (tests, clone sans tags).
repowarden_majeure_r() {
    if [ -n "${REPOWARDEN_MAJEURE:-}" ]; then REPLY="$REPOWARDEN_MAJEURE"; return; fi
    if [ -z "$1" ] || [ "$1" = 0.0.0-dev ]; then REPLY=""; return; fi
    REPLY="${1%%.*}"
    REPLY="${REPLY%%-*}"
    [[ "$1" != *.0.0-* ]] || REPLY=$((REPLY - 1))
}

# En-tête de marque
brand() { echo "${UI_C}${UI_B}◆ repowarden${UI_N}${UI_D}${1:+ · $1}${UI_N}"; }
