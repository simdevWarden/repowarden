#!/usr/bin/env bash
# Aligner la branche d'integration (develop) sur la branche principale (main)
# apres une livraison (workflow release-auto, mode tag) : develop avance jusqu'a
# main, jamais l'inverse. Le premier passage rattrape le retard.
#   ci/aligner-develop.sh
# Sortie : « alignee », « deja alignee » ou « non alignee » (develop a avance :
# aucun push, jamais --force) ou avertissement (push refuse). Toujours un code
# de retour nul : l'alignement ne doit jamais bloquer la publication npm.
# Environnement : GH_TOKEN (push de l'App, via gh), INTEGRATION (develop par
# defaut), MAIN (main par defaut).
set -euo pipefail

INTEGRATION="${INTEGRATION-develop}"
MAIN="${MAIN-main}"

# Git authentifie par le jeton de l'etape (GH_TOKEN, via gh) : un depot prive
# refuse le fetch et le push anonymes (checkout sans identifiants persistes).
git_app() {
    git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"
}

# Avertissement (annotation + resume) : l'alignement ne doit jamais faire
# echouer la release, donc la publication npm. $1 : la raison.
avertir() {
    local raison
    raison="$(tr '\n' ' ' <<<"$1")"
    echo "::warning::$INTEGRATION non alignee sur $MAIN : $raison. Lancer repowarden proteger (bypass de l'App sur chaque ruleset de $INTEGRATION)."
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        echo "- $INTEGRATION non alignee sur $MAIN : $raison" >>"$GITHUB_STEP_SUMMARY"
    fi
}

# Fetch refuse (reseau, droits) : avertissement, jamais un echec
if ! sortie="$(git_app fetch -q origin "$MAIN" "$INTEGRATION" 2>&1)"; then
    avertir "fetch refuse ($sortie)"
    exit 0
fi

# Reference absente apres le fetch : meme traitement
if ! sha_dev="$(git rev-parse "origin/$INTEGRATION" 2>&1)" ||
    ! sha_main="$(git rev-parse "origin/$MAIN" 2>&1)"; then
    avertir "reference introuvable (${sha_dev:-} ${sha_main:-})"
    exit 0
fi

# develop est incluse dans main : rien (deja alignee) ou un rattrapage ;
# merge-base sort 1 si develop a avance, plus si la reference est inutilisable
rc=0
git merge-base --is-ancestor "origin/$INTEGRATION" "origin/$MAIN" || rc=$?
if [ "$rc" -gt 1 ]; then
    avertir "merge-base en erreur (code $rc)"
    exit 0
fi
if [ "$rc" -eq 0 ]; then
    if [ "$sha_dev" = "$sha_main" ]; then
        echo "$INTEGRATION est deja alignee sur $MAIN."
        exit 0
    fi
    # Push rapide (fast-forward) : jamais --force. Refus (ruleset sans bypass de
    # l'App, protection) : avertissement avec la raison de git, jamais un echec
    if sortie="$(git_app push origin "origin/$MAIN:refs/heads/$INTEGRATION" 2>&1)"; then
        echo "$INTEGRATION alignee sur $MAIN."
    else
        avertir "push refuse ($sortie)"
    fi
else
    # develop a avance sur main : la pousser a main effacerait ses commits
    echo "$INTEGRATION a avance sur $MAIN : aucun rattrapage automatique (jamais --force)."
fi
