#!/usr/bin/env bash
# Contenu propre à la branche principale (workflow release-auto, mode tag) :
# seuls la branche d'intégration (develop) et ses instantanés livraison/*
# doivent entrer dans main ; du contenu arrivé autrement n'est pas rapporté
# automatiquement dans develop (squash seul) : signalé ici, avant le tag, à
# reporter par une PR de travail (squashée).
#   ci/contenu-main.sh
# Comparaison des contenus, jamais des historiques : une livraison squashée
# puis réunie dans develop n'est pas du contenu propre. Deux temps :
# 1. un parent de HEAD est un ancêtre de origin/INTEGRATION et son arbre est
#    celui de HEAD : main vient d'un instantané de develop (livré pendant que
#    develop avance) — la seule comparaison de contenus le signalerait à tort ;
# 2. sinon, tout fichier différent de origin/INTEGRATION est du contenu propre
#    (liste en erreur).
# Environnement : GH_TOKEN (fetch d'un dépôt privé via gh), INTEGRATION
# (develop par défaut), MAIN (main par défaut, pour le message).
set -euo pipefail

INTEGRATION="${INTEGRATION-develop}"
MAIN="${MAIN-main}"

# Identifiants par le jeton de l'étape (GH_TOKEN, via gh) : un dépôt privé
# refuse le fetch anonyme (checkout sans identifiants persistés)
git -c credential.helper= -c 'credential.helper=!gh auth git-credential' fetch -q origin "$INTEGRATION"

# 1. Instantané livré : un parent de HEAD déjà dans develop, de même arbre
for parent in $(git rev-list --parents -n 1 HEAD | cut -d' ' -f2-); do
    if git merge-base --is-ancestor "$parent" "origin/$INTEGRATION" &&
        git diff --quiet "$parent" HEAD; then
        echo "$MAIN ne contient rien de propre : livraison d'un instantané de $INTEGRATION."
        exit 0
    fi
done

# 2. Contenus comparés, pas les historiques
fichiers="$(git diff --name-only "origin/$INTEGRATION" HEAD | paste -sd, - | sed 's/,/, /g')"
if [ -z "$fichiers" ]; then
    echo "$INTEGRATION contient déjà tout le contenu de $MAIN."
    exit 0
fi
echo "::error::$MAIN contient du contenu absent de $INTEGRATION ($fichiers) : seuls $INTEGRATION et ses instantanés livraison/* devraient y entrer. Le reporter dans $INTEGRATION par une PR de travail (squashée), et chercher comment il est arrivé sur $MAIN."
exit 1
