#!/usr/bin/env bash
# Vérifications CI : mêmes règles que les hooks, mais non contournables.
# Fonctionne sur GitHub Actions, GitLab CI ou tout autre CI (variables REPOWARDEN_*).
#
#   ci/check.sh [commits] [branch] [secrets] [format] [tests] [deadcode] [comments]   (défaut : tout)
#
# Variables (toutes optionnelles, détectées automatiquement sur GitHub/GitLab) :
#   REPOWARDEN_CHECKS   liste des vérifications (si aucun argument)
#   REPOWARDEN_BASE     commit de base (sinon : MR/PR, push précédent, branche par défaut)
#   REPOWARDEN_BRANCH   nom de branche à vérifier
#   REPOWARDEN_TARGET   branche cible de la PR / MR (flux integrationBranch)
#   REPOWARDEN_STRICT   "true" : un outil de formatage/test manquant fait échouer
#   REPOWARDEN_PR_BODY  description de la PR (sans signature d'agent IA)
#   REPOWARDEN_PR_TITLE titre de la PR / MR (devient le message du commit en squash)
#   REPOWARDEN_BIN      dossier des outils installés (gitleaks), ajouté au PATH
set -euo pipefail

REPOWARDEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../hooks/lib/common.sh
source "$REPOWARDEN_DIR/hooks/lib/common.sh"
# shellcheck source=../hooks/lib/lang.sh
source "$REPOWARDEN_DIR/hooks/lib/lang.sh"

export PATH="${REPOWARDEN_BIN:-$HOME/.local/bin}:$PATH"
cd "$(git rev-parse --show-toplevel)"

# --- Affichage -----------------------------------------------------------------

section() { echo; echo "${UI_B}━━ $* ━━${UI_N}"; }
section_t() { _tr "$@"; section "$_T"; }

# Erreur annotée (visible dans l'onglet "Files changed" sur GitHub)
ci_error_t() { _tr "$@"; ci_error "$_T"; }
ci_error() {
    if [ "${GITHUB_ACTIONS:-}" = true ]; then
        echo "::error title=repowarden::$*"
    else
        err "$*" >&2
    fi
}

# --- Contexte : base, branche, fichiers ------------------------------------------

is_zero() { [[ "$1" =~ ^0+$ ]]; }
is_commit() { git cat-file -e "$1^{commit}" 2>/dev/null; }

# Commit de base des changements à vérifier (vide = tout l'historique)
detect_base() {
    local v def
    if [ -n "${REPOWARDEN_BASE:-}" ]; then echo "$REPOWARDEN_BASE"; return; fi
    # GitLab merge request
    if [ -n "${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}" ]; then echo "$CI_MERGE_REQUEST_DIFF_BASE_SHA"; return; fi
    # GitHub pull request
    if [ -n "${GITHUB_BASE_REF:-}" ]; then
        git fetch -q origin "$GITHUB_BASE_REF" 2>/dev/null || true
        git merge-base HEAD "origin/$GITHUB_BASE_REF" 2>/dev/null && return
    fi
    # Push : état précédent de la branche
    for v in "${CI_COMMIT_BEFORE_SHA:-}" "${GITHUB_EVENT_BEFORE:-}"; do
        if [ -n "$v" ] && ! is_zero "$v" && is_commit "$v"; then echo "$v"; return; fi
    done
    # Nouvelle branche : point de départ depuis la branche par défaut
    def="${CI_DEFAULT_BRANCH:-${GITHUB_DEFAULT_BRANCH:-main}}"
    git fetch -q origin "$def" 2>/dev/null || true
    git merge-base HEAD "origin/$def" 2>/dev/null || true
}

detect_branch() {
    # Tag : pas de nom de branche à vérifier
    if [ -n "${CI_COMMIT_TAG:-}" ] || [ "${GITHUB_REF_TYPE:-}" = tag ]; then return; fi
    echo "${REPOWARDEN_BRANCH:-${GITHUB_HEAD_REF:-${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-${CI_COMMIT_BRANCH:-${GITHUB_REF_NAME:-}}}}}"
}

# Branche cible de la PR / MR (vide hors PR)
detect_target() {
    echo "${REPOWARDEN_TARGET:-${GITHUB_BASE_REF:-${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}}}"
}

# Fichiers ajoutés/modifiés depuis la base (tous les fichiers suivis sans base)
changed_files() {
    if [ -n "$BASE" ]; then
        git diff --name-only --diff-filter=ACMR "$BASE" HEAD
    else
        git ls-files
    fi
}

# --- Vérifications ---------------------------------------------------------------

# Branches des bots de dépendances : titre de PR exempté de la longueur
is_bot_branch() { [[ "$1" == dependabot/* || "$1" == renovate/* ]]; }

check_commits() {
    section_t ci.section.commits
    local sha email subject bad=0 count=0 bot=""
    is_bot_branch "$(detect_branch)" && bot=1
    if [ -z "$BASE" ]; then info_t ci.check.2; return 0; fi
    # Séparateur 0x1f (non blanc) : un champ vide ne décale pas les suivants
    while IFS=$'\x1f' read -r sha email subject; do
        [ -n "$sha" ] || continue
        count=$((count + 1))
        commit_subject_problem_r "$subject" "$email"
        if [ -n "$REPLY" ]; then
            ci_error_t "$REPLY" "${sha:0:7}" "$subject"
            bad=1
        fi
    done < <(git log --no-merges --format='%H%x1f%ae%x1f%s' "$BASE..HEAD")
    # Agents IA : ni auteur ni committer, ni signature (messages, description
    # de PR qui devient le message du commit en squash)
    if agents_refused; then
        local an ae cn ce agents=0
        while IFS=$'\t' read -r sha an ae cn ce; do
            [ -n "$sha" ] || continue
            if agent_identity "$an" "$ae"; then
                ci_error_t ci.check.agent_identity "${sha:0:7}" "$an <$ae>"; agents=1
            elif agent_identity "$cn" "$ce"; then
                ci_error_t ci.check.agent_identity "${sha:0:7}" "$cn <$ce>"; agents=1
            fi
            agent_lines_r "$(git log -1 --format=%B "$sha")"
            if [ -n "$REPLY" ]; then
                ci_error_t ci.check.agent_line "${sha:0:7}" "${REPLY%%$'\n'*}"; agents=1
            fi
        done < <(git log --format='%H%x09%an%x09%ae%x09%cn%x09%ce' "$BASE..HEAD")
        agent_lines_r "${REPOWARDEN_PR_BODY:-${CI_MERGE_REQUEST_DESCRIPTION:-}}"
        if [ -n "$REPLY" ]; then
            ci_error_t ci.check.agent_pr_body "${REPLY%%$'\n'*}"; agents=1
        fi
        if [ "$agents" = 1 ]; then
            echo_t ci.check.agent_fix
            [ "$bad" = 1 ] || return 1
        fi
    fi
    # Titre de la PR : message du commit final en cas de merge squash
    local title="${REPOWARDEN_PR_TITLE:-${CI_MERGE_REQUEST_TITLE:-}}"
    if [ -n "$title" ]; then
        if ! [[ "$title" =~ $CC_PATTERN ]]; then
            ci_error_t ci.check.6 "$title"
            bad=1
        elif [ -z "$bot" ] && authored_length "$title" && [ "$REPLY" -gt 72 ]; then
            ci_error_t ci.check.7 "$title"
            bad=1
        else
            ok_t ci.check.8
        fi
    fi
    if [ "$bad" = 1 ]; then
        echo_t ci.check.9
        types_help 2>&1
        echo_t ci.check.10
        echo_t ci.check.11 "$BASE"
        return 1
    fi
    ok_t ci.check.12 "$count"
}

check_branch() {
    section_t ci.section.branch
    local branch
    branch="$(detect_branch)"
    if [ -z "$branch" ]; then info_t ci.check.13; return 0; fi
    if ! branch_name_valid "$branch"; then
        ci_error_t ci.check.14 "$branch" "$(suggest_branch_name "$branch")."
        branch_help "$branch" 2>&1
        return 1
    fi
    ok_t ci.check.15 "$branch"
    # Flux avec branche d'intégration : la PR vise-t-elle la bonne branche ?
    local target allowed
    target="$(detect_target)"
    pr_targets_r "$branch"
    allowed="$REPLY"
    # Branche develop présente mais flux non déclaré : repowarden traiterait le
    # projet comme « main seule » et laisserait le travail entrer dans main
    cfg_r integrationBranch ""
    if [ -z "$REPLY" ] && [ -n "$target" ] && [ "$branch" != develop ] &&
        git rev-parse -q --verify refs/remotes/origin/develop >/dev/null; then
        cfg_r mainBranch main
        if [ "$target" = "$REPLY" ]; then
            ci_error_t ci.check.develop_undeclared "$branch" "$target"
            return 1
        fi
    fi
    [ -n "$target" ] && [ -n "$allowed" ] || return 0
    if [[ " $allowed " == *" $target "* ]]; then
        ok_t ci.check.16 "$target"
        return 0
    fi
    ci_error_t ci.check.17 "$branch" "$target" "${allowed// / ou }"
    echo_t ci.check.18 "${allowed%% *}"
    return 1
}

check_secrets() {
    section_t ci.section.secrets
    if ! has gitleaks; then
        ci_error_t ci.check.19
        return 1
    fi
    if [ -n "$BASE" ]; then
        gitleaks git --redact --no-banner --log-opts="$BASE..HEAD" .
    else
        gitleaks git --redact --no-banner .
    fi || { ci_error "Secret détecté : le retirer de l'historique et révoquer le secret."; return 1; }
}

check_format() {
    section_t ci.section.format
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        ci_error_t ci.check.20
        return 1
    fi
    if ! changed_files | without_excluded | format_files; then
        ci_error_t ci.check.21
        git checkout -q -- .
        return 1
    fi
    local diff
    diff="$(git diff --name-only)"
    if [ -n "$diff" ]; then
        while IFS= read -r f; do ci_error "$f : non formaté."; done <<<"$diff"
        git --no-pager diff --stat
        echo_t ci.check.22
        git checkout -q -- .
        return 1
    fi
    ok_t ci.check.23
}

check_deadcode() {
    section_t dc.section
    if [ -z "$BASE" ]; then info_t dc.no_base; return 0; fi
    changed_files | without_excluded | deadcode_projects "$BASE"
}

# Fonctions ajoutées sans commentaire : avertissement, jamais un échec
check_comments() {
    section_t cm.section
    if [ -z "$BASE" ]; then info_t cm.no_base; return 0; fi
    comments_check "$BASE" HEAD
    [ "$REPLY" != 0 ] || ok_t cm.none
}

# Motif ERE des déclarations de test de $1 (bats, pytest, Go, Java, JS/TS) :
# le même motif des deux côtés du diff, quel que soit le langage du projet.
# bats et Go restent ancrés en colonne 0 ; pytest, Java/Kotlin et JS/TS
# acceptent une indentation (méthodes dans une classe, tests dans un describe).
tests_motif_r() {
    case "$1" in
        *.bats) REPLY='^@test "' ;;
        test_*.py | *_test.py) REPLY='^[[:space:]]*def test_' ;;
        *_test.go) REPLY='^func Test' ;;
        *.java | *.kt) REPLY='^[[:space:]]*@Test' ;;
        *.test.* | *.spec.*) REPLY='^[[:space:]]*(it|test)\(' ;;
        *) return 1 ;;
    esac
}

# REPLY = déclarations de test du fichier $1 à la révision $2 (0 si le fichier
# n'y existe pas ou n'a pas de tests reconnus : un ajout n'est jamais une perte)
tests_nombre() {
    local motif
    if ! tests_motif_r "$1"; then
        REPLY=0
        return 0
    fi
    motif="$REPLY"
    if git cat-file -e "$2:$1" 2>/dev/null; then
        REPLY="$(git show "$2:$1" | grep -acE "$motif" || true)"
    else
        REPLY=0
    fi
}

# Une PR ne retire pas de tests : le nombre de déclarations d'un fichier ne
# baisse pas entre la base et la tête, sauf raison écrite dans la PR (#518)
tests_declares_check() {
    [ -n "$BASE" ] || return 0
    # La raison est déjà donnée dans la description : permis, mais dit
    if grep -qE '^Tests (retirés|removed) *: .' <<<"${REPOWARDEN_PR_BODY:-${CI_MERGE_REQUEST_DESCRIPTION:-}}"; then
        return 0
    fi
    local st a b anc nou av ap baisse=0
    while IFS=$'\t' read -r st a b; do
        [ -n "$st" ] || continue
        case "$st" in
            R* | C*) anc="$a" nou="$b" ;;
            *) anc="$a" nou="$a" ;;
        esac
        if is_excluded "$nou"; then continue; fi
        tests_nombre "$anc" "$BASE"; av="$REPLY"
        tests_nombre "$nou" HEAD; ap="$REPLY"
        if [ "$ap" -lt "$av" ]; then
            ci_error_t ci.check.tests_down "$nou" "$av" "$ap"
            baisse=1
        fi
    done < <(git diff --name-status --diff-filter=ACDMR "$BASE" HEAD)
    if [ "$baisse" = 0 ]; then return 0; fi
    echo_t ci.check.tests_fix
    return 1
}

# Tests des projets touchés, puis déclarations de test (aucun retrait silencieux)
check_tests() {
    section_t ci.section.tests
    local baisse=0
    changed_files | without_excluded | test_projects || baisse=1
    tests_declares_check || baisse=1
    if [ "$baisse" = 0 ]; then return 0; fi
    return 1
}

# --- Exécution ---------------------------------------------------------------------

CHECKS="${*:-${REPOWARDEN_CHECKS:-commits branch secrets format tests deadcode comments}}"
REPOWARDEN_WARN_FILE="$(mktemp)"
export REPOWARDEN_WARN_FILE
trap 'rm -f "$REPOWARDEN_WARN_FILE"' EXIT

# Historique complet nécessaire pour comparer à la base
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    git fetch -q --unshallow 2>/dev/null || warn "Clone superficiel : utiliser fetch-depth: 0 (GitHub) ou GIT_DEPTH: 0 (GitLab)."
fi

BASE="$(detect_base)"
echo_t ci.check.24 "${BASE:-aucune (historique complet)}" "$CHECKS"

# PR partant de main ou de develop : ses vérifications s'accrochent au commit
# de cette branche persistante, qui ne doit jamais apparaître en rouge
persistent_pr_r "$(detect_branch)" "$(detect_target)"
case "$REPLY" in
    inversee)
        # Sans objet (develop → branche de ticket, main → autre que develop) :
        # rien à vérifier, la PR est fermée par le suivi des tickets
        section_t ci.section.branch
        attention_t ci.check.inverted "$(detect_branch)" "$(detect_target)"
        echo_t ci.check.inverted_fix "$(cfg integrationBranch)"
        exit 0
        ;;
    retour)
        # Retour de main dans develop : merge commit, le titre de la PR n'est
        # pas un message de commit
        info_t ci.check.back_merge "$(detect_branch)" "$(detect_target)"
        REPOWARDEN_PR_TITLE="" CI_MERGE_REQUEST_TITLE=""
        ;;
esac

failed=""
for check in $CHECKS; do
    # Étapes désactivables par le projet (.repowarden.conf versionné)
    case "$check" in
        commits) key="commit-msg" ;;
        branch) key="branch-name" ;;
        *) key="$check" ;;
    esac
    if skipped "$key"; then
        section "$check"
        info_t ci.check.25 "$key"
        continue
    fi
    declare -F "check_$check" >/dev/null || { ci_error "Vérification inconnue : $check"; failed="$failed $check"; continue; }
    "check_$check" || failed="$failed $check"
done

if [ "${REPOWARDEN_STRICT:-false}" = true ] && [ -s "$REPOWARDEN_WARN_FILE" ]; then
    section_t ci.section.strict
    while IFS= read -r w; do ci_error "$w"; done <"$REPOWARDEN_WARN_FILE"
    failed="$failed strict"
fi

echo
if [ -n "$failed" ]; then
    err_t ci.check.26 "$failed"
    exit 1
fi
ok_t ci.check.27
