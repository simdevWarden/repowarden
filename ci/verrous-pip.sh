#!/usr/bin/env bash
# Régénère les verrous pip touchés par une PR Dependabot (workflow verrous-pip) :
# Dependabot les recompile sans les options de leur en-tête (--universal,
# --python-version…), les marqueurs disparaissent et --require-hashes échoue.
# Chaque verrou *.txt modifié depuis la base dont l'en-tête est
# « uv pip compile … » est recompilé avec cette commande, puis, s'il a changé,
# commité au nom du bot et poussé sur la branche de la PR. Verrou conforme :
# aucun commit.
#
# Variables : BASE_SHA (base de la PR), HEAD_REF (branche à pousser ; vide :
# pas de push), REPOWARDEN_BOT_NAME / REPOWARDEN_BOT_EMAIL (auteur du commit)
set -euo pipefail

REPOWARDEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../hooks/lib/common.sh
source "$REPOWARDEN_DIR/hooks/lib/common.sh"
cd "$(git rev-parse --show-toplevel)"

: "${BASE_SHA:?BASE_SHA requis (base de la PR)}"

# Arguments de la commande uv inscrite en en-tête du verrou $1, dans CMD.
# Retour 1 : pas un verrou uv ; 2 : sortie autre que ce verrou, refusée car
# l'en-tête vient de la PR et ne doit rien écrire d'autre.
uv_header_r() {
    local file="$1" line="" sortie="" prec="" mot
    CMD=()
    { IFS= read -r line && IFS= read -r line; } <"$file" || return 1
    case "$line" in "#    uv pip compile "*) ;; *) return 1 ;; esac
    read -ra CMD <<<"${line#\#}"
    for mot in "${CMD[@]}"; do
        case "$prec" in -o | --output-file) sortie="$mot" ;; esac
        case "$mot" in --output-file=*) sortie="${mot#--output-file=}" ;; esac
        prec="$mot"
    done
    [ "$sortie" = "$file" ] || return 2
}

regeneres=()
while IFS= read -r verrou; do
    [ -f "$verrou" ] || continue
    code=0
    uv_header_r "$verrou" || code=$?
    [ "$code" -ne 2 ] || attention_t ci.verrous_pip.refused "$verrou"
    [ "$code" -eq 0 ] || continue
    info_t ci.verrous_pip.compile "$verrou"
    "${CMD[@]}"
    git diff --quiet -- "$verrou" || regeneres+=("$verrou")
done < <(git diff --name-only --diff-filter=AM "$BASE_SHA...HEAD" -- '*.txt')

if [ "${#regeneres[@]}" -eq 0 ]; then
    ok_t ci.verrous_pip.compliant
    exit 0
fi

git add -- "${regeneres[@]}"
nom="${REPOWARDEN_BOT_NAME:-$(git config user.name || true)}"
courriel="${REPOWARDEN_BOT_EMAIL:-$(git config user.email || true)}"
git -c user.name="$nom" -c user.email="$courriel" commit -q \
    -m "build(deps): verrous pip régénérés avec uv" \
    -m "Dependabot recompile sans les options de l'en-tête (--universal, --python-version) : commande de l'en-tête relancée pour ${regeneres[*]}."
ok_t ci.verrous_pip.committed "${regeneres[*]}"
if [ -n "${HEAD_REF:-}" ]; then
    git push -q origin "HEAD:refs/heads/$HEAD_REF"
    ok_t ci.verrous_pip.pushed "$HEAD_REF"
fi
