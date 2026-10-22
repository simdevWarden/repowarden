#!/usr/bin/env bash
# Fonctions communes à tous les hooks : désactivation par projet et chaînage
# des hooks propres au projet. Compatible bash 3.2 (macOS).
# shellcheck disable=SC2034 # variables utilisées par les hooks qui sourcent ce fichier

HOOK_NAME="$(basename "$0")"
HOOKS_DIR="$(cd "$(dirname "$0")" && pwd -P)"

# shellcheck source=ui.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
# Traduction (langue provisoire jusqu'à la lecture de la configuration)
# shellcheck source=i18n.sh
source "$(dirname "${BASH_SOURCE[0]}")/i18n.sh"

# Avertissement ; si REPOWARDEN_WARN_FILE est défini (CI), il est aussi journalisé
# pour le mode strict (outil manquant = échec)
warn() {
    echo "${UI_Y}⚠${UI_N} $*" >&2
    if [ -n "${REPOWARDEN_WARN_FILE:-}" ]; then echo "$*" >>"$REPOWARDEN_WARN_FILE"; fi
}
has() { command -v "$1" >/dev/null 2>&1; }

# Config repowarden.* chargée UNE fois par processus : chaque appel git coûte cher
# (20 à 50 ms sous Windows), et un hook lit la config des dizaines de fois.
# Priorité : git config (local puis global), puis .repowarden.conf versionné.
# Anciens noms (repogarde.*, .repogarde.conf) lus aussi, le nouveau l'emporte.
CFG_GIT=""
CFG_FILE=""
CFG_LOADED=""
# Racine du dépôt, calculée une fois et réutilisée par les hooks
GIT_TOPLEVEL=""

cfg_load() {
    local file=""
    GIT_TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    # Anciennes clés d'abord : cfg_lookup garde la dernière valeur trouvée
    CFG_GIT="$(git config --get-regexp '^(repogarde|repowarden)\.' 2>/dev/null || true)"
    case "$CFG_GIT" in repogarde.* | *$'\n'repogarde.*) compat_note 'repogarde.*' ;; esac
    CFG_FILE=""
    if [ -n "$GIT_TOPLEVEL" ]; then
        for file in "$GIT_TOPLEVEL/.repogarde.conf" "$GIT_TOPLEVEL/.repowarden.conf"; do
            [ -f "$file" ] || continue
            [ "${file##*/}" = .repogarde.conf ] && compat_note .repogarde.conf
            CFG_FILE="$CFG_FILE${CFG_FILE:+$'\n'}$(git config -f "$file" --get-regexp '^(repogarde|repowarden)\.' 2>/dev/null || true)"
        done
    fi
    CFG_LOADED=1
}

# REPLY = dernière valeur de repowarden.<$1> dans $2 (sortie de --get-regexp, où git
# met les noms en minuscules : comparaison insensible à la casse). Échec si absente.
cfg_lookup() {
    local line found="" nocase=""
    REPLY=""
    shopt -q nocasematch && nocase=1
    shopt -s nocasematch
    while IFS= read -r line; do
        if [[ "$line" == "repowarden.$1 "* || "$line" == "repogarde.$1 "* ]]; then
            REPLY="${line#* }"
            found=1
        elif [[ "$line" == "repowarden.$1" || "$line" == "repogarde.$1" ]]; then
            REPLY=true # clé sans valeur
            found=1
        fi
    done <<<"$2"
    [ -n "$nocase" ] || shopt -u nocasematch
    [ -n "$found" ]
}

# REPLY = réglage repowarden.<$1>, ou $2 par défaut (sans sous-processus)
cfg_r() {
    [ -n "$CFG_LOADED" ] || cfg_load
    cfg_lookup "$1" "$CFG_GIT" || cfg_lookup "$1" "$CFG_FILE" || REPLY="${2-}"
    return 0
}

# Lit un réglage : cfg allowedBranches "main master" (2e argument = défaut)
cfg() {
    cfg_r "$@"
    [ -z "$REPLY" ] || printf '%s\n' "$REPLY"
}

# Conventional Commits (partagé par commit-msg et prepare-commit-msg)
CC_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
CC_PATTERN="^($CC_TYPES)(\([a-z0-9._-]+\))?!?: .+"

# Type le plus proche d'un type inconnu : alias courants, puis préfixe commun
# (doc → docs, feature → feat, Feat → feat) ; vide si aucun
type_proche_r() {
    local t="$1" c
    case "$t" in
        feature | features) REPLY="feat"; return ;;
        doc | documentation) REPLY="docs"; return ;;
        fixe | fixed | fixes | bugfix | hotfix) REPLY="fix"; return ;;
        tests) REPLY="test"; return ;;
        refacto | refactoring) REPLY="refactor"; return ;;
    esac
    REPLY=""
    for c in ${CC_TYPES//|/ }; do
        if [[ "$c" == "$t"* || "$t" == "$c"* ]]; then REPLY="$c"; return; fi
    done
}

# REPLY = longueur de la première ligne écrite par l'auteur : le suffixe
# « (#123) » ajouté par GitHub lors d'un merge squash n'est pas compté.
authored_length() {
    local subject="$1" continuation
    if [[ "$subject" =~ ^(.*)\ \(\#[0-9]+\)$ ]]; then subject="${BASH_REMATCH[1]}"; fi
    # Caractères et non octets, quelle que soit la locale (Git Bash sous Windows
    # est en locale C : « é » compterait double). En UTF-8, on retire du nombre
    # d'octets les octets de continuation (0x80 à 0xBF).
    local LC_ALL=C
    continuation="${subject//[^$'\x80'-$'\xbf']/}"
    REPLY=$((${#subject} - ${#continuation}))
}

# Nommage des branches : <type>/<sujet>
BRANCH_ALIASES="feature|bugfix|hotfix"
BRANCH_PATTERN="^($CC_TYPES|$BRANCH_ALIASES)/[a-z0-9._-]+(/[a-z0-9._-]+)*$"
# Branches des bots (release-please, Dependabot, Renovate) : nommées par eux
DEFAULT_ALLOWED_BRANCHES="main master develop release/* release-please--* dependabot/* renovate/*"

# Liste des types avec leur rôle (affichée dans les messages d'aide)
types_help() {
    local tp desc
    for tp in feat fix docs style refactor perf test build ci chore revert; do
        _tr "cc.type.$tp"
        desc="$_T"
        case "$tp" in
            feat | fix) _tr "help.alias.$tp"; desc="$(printf '%-32s %s' "$desc" "$_T")" ;;
        esac
        printf '  %-9s %s\n' "$tp" "$desc" >&2
    done
}

# Vrai si la branche respecte la convention ou fait partie des exceptions
branch_name_valid() {
    local branch="$1" allowed pat
    [ -z "$branch" ] && return 0 # HEAD détachée
    # Instantané de develop créé par la demande de livraison : toujours admis
    [[ "$branch" != livraison/* ]] || return 0
    cfg_r allowedBranches "$DEFAULT_ALLOWED_BRANCHES"
    allowed="$REPLY"
    set -f # pas d'expansion de "release/*" sur le disque
    for pat in $allowed; do
        # shellcheck disable=SC2254
        case "$branch" in $pat) set +f; return 0 ;; esac
    done
    set +f
    [[ "$branch" =~ $BRANCH_PATTERN ]]
}

# Flux avec branche d'intégration (réglage integrationBranch, ex. develop) :
# REPLY = branches cibles autorisées pour une PR depuis la branche $1, vide si
# aucun flux n'est configuré (PR libres, en pratique vers main).
#   travail (feat/…, fix/…, bots) → intégration
#   intégration, PR de release-please → principale (mainBranch, défaut main)
#   release/…, hotfix/…           → principale ou intégration
pr_targets_r() {
    local integration
    cfg_r integrationBranch ""
    integration="$REPLY"
    [ -n "$integration" ] || return 0
    cfg_r mainBranch main
    # Seule la branche d'intégration entre dans la branche principale (ou son
    # instantané livraison/vX.Y.Z, figé à la demande de livraison) : tout le
    # reste (correctifs urgents compris) passe par elle et ses préversions
    case "$1" in
        "$integration" | livraison/* | release-please--*) ;;
        *) REPLY="$integration" ;;
    esac
}

# Nature d'une PR partant d'une branche persistante (flux integrationBranch),
# source $1, cible $2 : REPLY = livraison (intégration → principale), retour
# (principale → intégration), inversee (persistante vers autre chose : sans
# objet), ou vide (PR de travail, ou hors PR)
persistent_pr_r() {
    local integration main
    cfg_r integrationBranch ""
    integration="$REPLY"
    cfg_r mainBranch main
    main="$REPLY"
    REPLY=""
    [ -n "$integration" ] && [ -n "$2" ] || return 0
    case "$1" in
        "$integration") if [ "$2" = "$main" ]; then REPLY=livraison; else REPLY=inversee; fi ;;
        "$main") if [ "$2" = "$integration" ]; then REPLY=retour; else REPLY=inversee; fi ;;
    esac
}

# Agents IA (code écrit pour quelqu'un) : ni auteur ni committer d'un commit,
# ni signature dans un message (Co-Authored-By, « Generated with »). Les bots
# d'automatisation (github-actions, App repowarden, Dependabot) ne sont pas
# concernés. Réglage allowAgentSignatures = true pour les autoriser.
AGENT_EMAIL_RE='^(noreply@anthropic\.com|[0-9]+\+[Cc]opilot@users\.noreply\.github\.com|cursoragent@cursor\.com|devin-ai-integration\[bot\]@users\.noreply\.github\.com)$'
AGENT_NAME_RE='^(Claude|Claude Code|Copilot|Cursor Agent|Devin AI)$'
# Lignes de signature (grep -iE, insensible à la casse)
# (locale C : un emoji en tête de ligne, comme « 🤖 Generated with », reste
# des octets quelconques, y compris sous Windows ; motifs en ASCII)
AGENT_LINE_ERE='(^[[:space:]]*co-authored-by:.*(anthropic\.com|copilot@users\.noreply\.github\.com|cursor\.com|devin-ai-integration))|(generated (with|by) \[?(claude|github copilot|copilot|cursor|devin))'

# Vrai si les signatures d'agents sont refusées (défaut)
agents_refused() { cfg_r allowAgentSignatures false; [ "$REPLY" != true ]; }

# Vrai si l'identité $1 (nom) / $2 (e-mail) est celle d'un agent IA
agent_identity() { [[ "$2" =~ $AGENT_EMAIL_RE || "$1" =~ $AGENT_NAME_RE ]]; }

# REPLY = premières lignes de signature d'agent du texte $1 (vide si aucune)
agent_lines_r() {
    REPLY="$(LC_ALL=C grep -aiE "$AGENT_LINE_ERE" <<<"$1" || true)"
}

# Vrai si $1 est un en-tête conforme (format et 72 caractères)
header_valid() {
    [[ "$1" =~ $CC_PATTERN ]] || return 1
    authored_length "$1"
    [ "$REPLY" -le 72 ]
}

# Bots de mise à jour des dépendances : leurs titres (« bump <paquet> from X
# to Y ») dépassent souvent 72 caractères ; seul leur format est exigé.
BOTS='^[0-9]*\+?(dependabot|renovate)\[bot\]@'

# Règle des en-têtes de commit, commune au pre-push et à la CI : même verdict,
# même message, que le commit soit vu avant le push ou après.
# REPLY = clé du message de refus de l'en-tête $1 (e-mail de l'auteur $2),
# vide si l'en-tête est admis
commit_subject_problem_r() {
    if [[ "$1" =~ ^(fixup|squash|amend)! ]]; then
        REPLY=ci.check.3
    elif [[ "$1" =~ ^(Merge|Revert) ]]; then
        REPLY=""
    elif ! [[ "$1" =~ $CC_PATTERN ]]; then
        REPLY=ci.check.4
    elif [[ "$2" =~ $BOTS ]]; then
        REPLY=""
    elif authored_length "$1" && [ "$REPLY" -gt 72 ]; then
        REPLY=ci.check.5
    else
        REPLY=""
    fi
}

# REPLY = titre de PR conforme déduit de la branche $1 :
#   feat/ajout-panier → « feat: ajout panier », hotfix/crash → « fix: crash »,
#   release/1.2.0 → « chore(release): 1.2.0 », develop → livraison sur main
suggest_pr_title_r() {
    local branch="$1" type rest
    cfg_r integrationBranch ""
    if [ -n "$REPLY" ] && [ "$branch" = "$REPLY" ]; then
        local integration="$REPLY"
        cfg_r mainBranch main
        REPLY="chore(release): livrer $integration sur $REPLY"
        return 0
    fi
    type="${branch%%/*}"
    rest="${branch#*/}"
    [ "$rest" != "$branch" ] || { type=chore; rest="$branch"; }
    case "$type" in
        feature) type=feat ;;
        bugfix | hotfix) type=fix ;;
        release) REPLY="chore(release): $rest"; return 0 ;;
    esac
    [[ "$type" =~ ^($CC_TYPES)$ ]] || type=chore
    rest="${rest//[\/_-]/ }"
    REPLY="$type: $rest"
    # 72 caractères au plus (coupe sur un mot)
    authored_length "$REPLY"
    while [ "$REPLY" -gt 72 ]; do
        if [[ "$rest" == *" "* ]]; then rest="${rest% *}"; else rest="${rest%?}"; fi
        authored_length "$type: $rest"
    done
    REPLY="$type: $rest"
}

# Propose un nom valide à partir d'un nom invalide (Feat/Mon Truc → feat/mon-truc)
suggest_branch_name() {
    local b type rest
    b="$(echo "$1" | tr '[:upper:] _' '[:lower:]--' | tr -cd 'a-z0-9._/-' |
        sed -e 's#//*#/#g' -e 's#^[/.-]*##' -e 's#[/.-]*$##')"
    if [[ "$b" != */* ]]; then
        echo "feat/${b:-ma-feature}"
        return
    fi
    type="${b%%/*}"
    rest="${b#*/}"
    case "$type" in
        bug | bugs) type=fix ;;
        doc) type=docs ;;
        features) type=feat ;;
        tests) type="test" ;;
        refacto) type=refactor ;;
    esac
    [[ "$type" =~ ^($CC_TYPES|$BRANCH_ALIASES)$ ]] || type=feat
    echo "$type/$rest"
}

# Message d'aide complet pour une branche invalide
# Aide courte (création de la branche, non bloquant) : le problème, la commande
# pour renommer, et où trouver le détail. L'aide complète vient au commit refusé.
branch_hint() {
    local branch="$1" suggested
    suggested="$(suggest_branch_name "$branch")"
    attention_t hook.branch_hint.1 "$branch" >&2
    printf '  %s%s%s\n' "$UI_B" "git branch -m $suggested" "$UI_N" >&2
    dim_t hook.branch_hint.2 >&2
}

# Aide complète (commit ou push refusé) : la commande pour renommer d'abord,
# puis le format attendu, les types et les exceptions
branch_help() {
    local branch="$1" suggested allowed
    suggested="$(suggest_branch_name "$branch")"
    allowed="$(cfg allowedBranches "$DEFAULT_ALLOWED_BRANCHES")"
    if [ "${REPOWARDEN_LANG:-}" = en ]; then
        cat >&2 <<EOF

Invalid branch name: "$branch"

👉 Rename the current branch:
     ${UI_B}git branch -m $suggested${UI_N}
   Already pushed? Rename the remote one too:
     git push origin -u $suggested && git push origin --delete $branch

Expected format: <type>/<topic>
  topic: lowercase letters, digits, . _ - (and / to split further)
  e.g.:  feat/signup, fix/user/login, hotfix/db-timeout

Types:
EOF
        types_help
        cat >&2 <<EOF

Allowed exceptions: $allowed
  (change: git config repowarden.allowedBranches "main develop release/*")
EOF
    else
        cat >&2 <<EOF

Nom de branche invalide : "$branch"

👉 Renommer la branche courante :
     ${UI_B}git branch -m $suggested${UI_N}
   Déjà poussée ? Renomme aussi le distant :
     git push origin -u $suggested && git push origin --delete $branch

Format attendu : <type>/<sujet>
  sujet : minuscules, chiffres, . _ - (et / pour sous-découper)
  ex.   : feat/inscription, fix/user/login, hotfix/timeout-db

Types :
EOF
        types_help
        cat >&2 <<EOF

Exceptions autorisées : $allowed
  (modifier : git config repowarden.allowedBranches "main develop release/*")
EOF
    fi
}

# Vrai si l'élément est désactivé (repowarden.skip, git config ou .repowarden.conf).
# Valeurs : true|all, ou liste séparée par espaces/virgules parmi
# pre-commit prepare-commit-msg commit-msg pre-push post-checkout
# branch-name protect-branch secrets sensitive-files format tests, ou un langage (node, python…)
skipped() {
    local v
    cfg_r skip
    v="$REPLY"
    [ "$v" = true ] || [ "$v" = all ] && return 0
    case " ${v//,/ } " in *" $1 "*) return 0 ;; esac
    return 1
}

# Le hook entier est-il désactivé ? (à appeler en tête de hook)
exit_if_skipped() {
    if skipped "$HOOK_NAME"; then
        info_t hook.common.3 "$HOOK_NAME"
        exit 0
    fi
}

# Version minimale de repowarden demandée par le projet (repowarden.version,
# ex. 3.1.4 ou 3) : le poste prévenu s'il est en retard, avec la commande de
# mise à jour. Avertissement seulement : la CI, à sa propre version, fait foi.
check_version() {
    local wanted installed root w i n
    cfg_r version ""
    wanted="${REPLY#v}"
    [ -n "$wanted" ] || return 0
    root="${HOOKS_DIR%/hooks}"
    repowarden_version_r "$root"
    installed="$REPLY"
    # 0.0.0-dev : version inconnue (clone sans tags, git clone --depth) ;
    # aucune comparaison possible, pas de fausse alerte à chaque commit
    [ -n "$installed" ] && [ "$installed" != 0.0.0-dev ] || return 0
    local IFS=.
    # shellcheck disable=SC2206 # découpage voulu sur les points
    w=($wanted) i=($installed)
    for n in 0 1 2; do
        [ "${i[$n]:-0}" -gt "${w[$n]:-0}" ] 2>/dev/null && return 0
        [ "${i[$n]:-0}" -lt "${w[$n]:-0}" ] 2>/dev/null && break
        [ "$n" = 2 ] && return 0
    done
    unset IFS
    if [[ "$root" == */node_modules/* ]]; then REPLY="npm update -g repowarden"
    elif [ -d "$root/.git" ]; then REPLY="git -C $root pull"
    else REPLY="$root"
    fi
    attention_t hook.version_old "$wanted" "$installed" "$REPLY" >&2
}

# Exécute les hooks propres au projet (.repowarden/<hook> ou .git/hooks/<hook>),
# ignorés par git dès que core.hooksPath pointe ici.
run_local_hook() {
    local candidate real
    for candidate in ".repowarden/$HOOK_NAME" ".repogarde/$HOOK_NAME" "$(git rev-parse --git-common-dir)/hooks/$HOOK_NAME"; do
        [ -x "$candidate" ] || continue
        # Ancien dossier (.repogarde/) : lancé seulement sans le nouveau
        if [ "$candidate" = ".repogarde/$HOOK_NAME" ]; then
            [ -x ".repowarden/$HOOK_NAME" ] && continue
            compat_note .repogarde/
        fi
        real="$(cd "$(dirname "$candidate")" && pwd -P)"
        [ "$real" = "$HOOKS_DIR" ] && continue
        # Hook installé par lefthook (« lefthook install ») : lefthook n'est plus
        # pris en charge depuis repowarden 4. Ses commandes se déclarent dans
        # .repowarden/<hook>, lancé juste avant.
        if grep -qs lefthook "$candidate"; then
            attention_t hook.common.lefthook_ignored "$candidate" "$HOOK_NAME"
            continue
        fi
        info_t hook.common.5 "$candidate"
        compat_warn
        "$candidate" "$@" || return $?
    done
    compat_warn
}

# Chargement immédiat dans le processus qui source ce fichier : un appel $(cfg …)
# s'exécute dans un sous-shell et ne pourrait pas remplir le cache du parent.
cfg_load

# Langue confirmée et plateforme, une fois la configuration lue
i18n_init

# Anciens noms rencontrés (REPOGARDE_*, repogarde.*, .repogarde.conf) : un
# avertissement par processus, avec les nouveaux noms
compat_warn() {
    [ -n "$REPOWARDEN_OLD_NAMES" ] || return 0
    # Un seul avertissement par commit ou push : pas dans les hooks qui suivent
    case "$HOOK_NAME" in prepare-commit-msg | commit-msg | post-checkout | post-merge) return 0 ;; esac
    attention_t compat.old_names "$REPOWARDEN_OLD_NAMES"
    REPOWARDEN_OLD_NAMES=""
}
compat_warn
# shellcheck source=forge.sh
source "$(dirname "${BASH_SOURCE[0]}")/forge.sh"
