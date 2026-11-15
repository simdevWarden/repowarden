#!/usr/bin/env bash
# Tag de version à publier sur npm : le dernier tag vX.Y.Z joignable depuis HEAD.
# Les préversions (vX.Y.Z-next.N) et les tags courts (vX.Y) ne comptent pas.
# git describe suit l'historique de HEAD : un tag posé sur une autre branche
# n'est pas retenu.
set -euo pipefail

if ! tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' 2>/dev/null)"; then
    echo "release-tag : aucun tag vX.Y.Z joignable depuis HEAD" >&2
    exit 1
fi
echo "$tag"
