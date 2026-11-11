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

git_app fetch -q origin "$MAIN" "$INTEGRATION"

# develop est incluse dans main : rien (deja alignee) ou un rattrapage
if git merge-base --is-ancestor "origin/$INTEGRATION" "origin/$MAIN"; then
    if [ "$(git rev-parse "origin/$INTEGRATION")" = "$(git rev-parse "origin/$MAIN")" ]; then
        echo "$INTEGRATION est deja alignee sur $MAIN."
        exit 0
    fi
    # Push rapide (fast-forward) : jamais --force. Refus (ruleset sans bypass de
    # l'App, protection) : avertissement avec la raison de git, jamais un echec
    if sortie="$(git_app push origin "origin/$MAIN:refs/heads/$INTEGRATION" 2>&1)"; then
        echo "$INTEGRATION alignee sur $MAIN."
    else
        sortie="$(tr '\n' ' ' <<<"$sortie")"
        echo "::warning::$INTEGRATION non alignee sur $MAIN : push refuse ($sortie). Lancer repowarden proteger (bypass de l'App sur chaque ruleset de $INTEGRATION)."
        if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
            echo "- $INTEGRATION non alignee sur $MAIN : push refuse ($sortie)" >>"$GITHUB_STEP_SUMMARY"
        fi
    fi
else
    # develop a avance sur main : la pousser a main effacerait ses commits
    echo "$INTEGRATION a avance sur $MAIN : aucun rattrapage automatique (jamais --force)."
fi
