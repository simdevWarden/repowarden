#!/usr/bin/env bash
# Aligner la branche d'integration (develop) sur la branche principale (main)
# apres une livraison (workflow release-auto, mode tag) : develop avance jusqu'a
# main, jamais l'inverse. Le premier passage rattrape le retard.
#   ci/aligner-develop.sh
# Sortie : « alignee », « deja alignee » ou « non alignee » (develop a avance :
# aucun push, jamais --force). Toujours un code de retour nul (informations).
# Environnement : GH_TOKEN (push de l'App, via gh), INTEGRATION (develop par
# defaut), MAIN (main par defaut).
set -euo pipefail

INTEGRATION="${INTEGRATION-develop}"
MAIN="${MAIN-main}"

# Identifiants par le jeton de l'etape (GH_TOKEN, via gh) : un depot prive
# refuse le fetch anonyme (checkout sans identifiants persistes)
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
    fetch -q origin "$MAIN" "$INTEGRATION"

# develop est incluse dans main : rien (deja alignee) ou un rattrapage
if git merge-base --is-ancestor "origin/$INTEGRATION" "origin/$MAIN"; then
    if [ "$(git rev-parse "origin/$INTEGRATION")" = "$(git rev-parse "origin/$MAIN")" ]; then
        echo "$INTEGRATION est deja alignee sur $MAIN."
        exit 0
    fi
    # Push rapide (fast-forward) : jamais --force
    git push origin "origin/$MAIN:refs/heads/$INTEGRATION"
    echo "$INTEGRATION alignee sur $MAIN."
else
    # develop a avance sur main : la pousser a main effacerait ses commits
    echo "$INTEGRATION a avance sur $MAIN : aucun rattrapage automatique (jamais --force)."
fi
