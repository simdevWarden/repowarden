#!/usr/bin/env bash
# Suivi des tickets (issues GitHub) : chaque PR est reliée à un ticket validé,
# et le ticket suit le travail jusqu'à la production.
#
#   ci/tickets.sh pr        événement pull_request : ticket créé s'il manque,
#                           statut du ticket, vérification « ticket » de la PR
#   ci/tickets.sh issue     événement issues : nouveau ticket à valider ;
#                           étiquette « validé » → backlog, branche du ticket
#                           créée (liée au ticket), PR débloquées ; assigné →
#                           en cours ; fermé « not planned » → PR et branche
#                           fermées
#   ci/tickets.sh push      premier push sur la branche d'un ticket : PR
#                           brouillon ouverte, ticket en cours
#   ci/tickets.sh revue     corrections demandées en revue → en cours
#   ci/tickets.sh release   release publiée, ou livraison sur la branche
#                           principale sans nouvelle version : tickets en
#                           préprod → done (fermés) ; ou prévenus de la préversion
#   ci/tickets.sh adopter   mise en route (tickets init) : tickets existants
#                           rangés, branches des PR inscrites sur leurs tickets
#
# Le ticket d'abord, la branche en découle : à valider → (validé : branche
# type/12-titre) backlog → en cours → en relecture → préprod → done. Seul un
# mainteneur pose « validé » (droits GitHub).
# Lien PR → ticket : « Ticket : #12 » dans la description, ou une branche
# feat/12-sujet. « Closes #12 » fermerait le ticket dès le merge dans develop :
# c'est la release qui le ferme.
#
# Variables : GH_TOKEN, GH_REPO, INTEGRATION ; pr : PR, ACTION, MERGED, DRAFT,
# HEAD, BASE, HEAD_SHA, AUTHOR ; issue : ISSUE, ACTION, LABEL, STATE_REASON ;
# push : PUSH_BRANCH, DELETED, PUSHER, SHA ; revue : PR, HEAD, REVIEW_STATE ;
# release : TAG, ou DELIVERED_SHA et MAIN (livraison sans nouvelle version)
set -euo pipefail

REPOWARDEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../hooks/lib/common.sh
source "$REPOWARDEN_DIR/hooks/lib/common.sh"
# shellcheck source=../hooks/lib/tickets.sh
source "$REPOWARDEN_DIR/hooks/lib/tickets.sh"
INTEGRATION="${INTEGRATION:-develop}"

# Modules (un rôle chacun, voir leur en-tête)
# shellcheck source=tickets/commun.sh
source "$REPOWARDEN_DIR/ci/tickets/commun.sh"
# shellcheck source=tickets/registre.sh
source "$REPOWARDEN_DIR/ci/tickets/registre.sh"
# shellcheck source=tickets/verification.sh
source "$REPOWARDEN_DIR/ci/tickets/verification.sh"
# shellcheck source=tickets/pr.sh
source "$REPOWARDEN_DIR/ci/tickets/pr.sh"
# shellcheck source=tickets/issue.sh
source "$REPOWARDEN_DIR/ci/tickets/issue.sh"
# shellcheck source=tickets/push.sh
source "$REPOWARDEN_DIR/ci/tickets/push.sh"
# shellcheck source=tickets/release.sh
source "$REPOWARDEN_DIR/ci/tickets/release.sh"
# shellcheck source=tickets/adopter.sh
source "$REPOWARDEN_DIR/ci/tickets/adopter.sh"

[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

case "${1:-}" in
    pr) cmd_pr ;;
    issue) cmd_issue ;;
    push) cmd_push ;;
    revue) cmd_revue ;;
    release) cmd_release ;;
    adopter) cmd_adopter ;;
    *) echo "usage : ci/tickets.sh pr|issue|push|revue|release|adopter" >&2; exit 2 ;;
esac
