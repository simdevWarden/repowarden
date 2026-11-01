#!/usr/bin/env bash
# Plateforme de gestion de version : github, gitlab, bitbucket, gitea (Gitea,
# Forgejo, Codeberg) ou other. Réglage forge (git config ou .repowarden.conf),
# sinon variables de la CI, sinon adresse du remote origin (domaine interne
# reconnu s'il contient gitlab, gitea…). Résultat mémorisé : FORGE.
# Vocabulaire : FORGE_PR (PR / MR), FORGE_REFS (exemple de références).
# GitLab : FORGE_URL (hôte), FORGE_PROJECT (chemin, / encodé en %2F),
# transport par curl + PRIVATE-TOKEN ou par glab api. Couche d'accès commune :
# forge_get/post/put/delete + fonctions sémantiques issues/MR/branches/statuts/membres.
# shellcheck disable=SC2034 # variables utilisées par les scripts qui sourcent ce fichier

forge_init() {
    local forge="" url
    if declare -F cfg_r >/dev/null; then
        cfg_r forge ""
        forge="$REPLY"
        if [ -z "$forge" ]; then
            # repowarden.platform est un alias de repowarden.forge
            cfg_r platform ""
            forge="$REPLY"
        fi
    fi
    if [ -z "$forge" ]; then
        if [ -n "${GITHUB_ACTIONS:-}" ]; then forge=github
        elif [ -n "${GITLAB_CI:-}" ]; then forge=gitlab
        elif [ -n "${BITBUCKET_BUILD_NUMBER:-}" ]; then forge=bitbucket
        elif [ -n "${GITEA_ACTIONS:-}${FORGEJO_ACTIONS:-}" ]; then forge=gitea
        else
            url="$(git remote get-url origin 2>/dev/null || true)"
            case "$url" in
                *github*) forge=github ;;
                *gitlab*) forge=gitlab ;;
                *bitbucket*) forge=bitbucket ;;
                *gitea* | *forgejo* | *codeberg*) forge=gitea ;;
                *) forge=other ;;
            esac
        fi
    fi
    FORGE="$forge"
    case "$FORGE" in
        gitlab) FORGE_PR=MR FORGE_REFS="Closes #12, !34" ;;
        bitbucket) FORGE_PR=PR FORGE_REFS="PROJ-42" ;;
        *) FORGE_PR=PR FORGE_REFS="Closes #12" ;;
    esac
    # Hôte GitLab (REPOWARDEN_GITLAB_HOST > CI_SERVER_HOST >
    # repowarden.gitlabHost > gitlab.com) et chemin du projet (%2F).
    if [ "$FORGE" = gitlab ]; then
        if [ -n "${REPOWARDEN_GITLAB_HOST:-}" ]; then
            FORGE_URL="$REPOWARDEN_GITLAB_HOST"
        elif [ -n "${CI_SERVER_HOST:-}" ]; then
            FORGE_URL="$CI_SERVER_HOST"
        else
            cfg_r gitlabHost ""
            FORGE_URL="${REPLY:-gitlab.com}"
        fi
        forge_project_id_r ""
        FORGE_PROJECT="$REPLY"
    fi
}

# Dépôt GitHub $1 sans rulesets ni protection de branches (dépôt privé d'une
# offre gratuite : GitHub les refuse en 403, « Upgrade to GitHub Pro or make
# this repository public ») ; le merge automatique y est aussi ignoré
github_sans_rulesets() {
    local reponse
    ! reponse="$(gh api "repos/$1/rulesets" 2>&1)" && [[ "$reponse" == *"403"* ]]
}

# gh présent (rien n'est affiché)
gh_present() { command -v gh >/dev/null 2>&1; }

# gh présent et connecté : gh auth status réussi
gh_connected() { gh_present && gh auth status >/dev/null 2>&1; }

# Contrôle partagé des commandes qui parlent à GitHub (bin/ticket, bin/tickets,
# bin/app) : gh installé ET connecté, sinon le message du problème et un échec.
# Sans gh : bot.no_gh ; sans connexion : gh.not_logged (la commande de
# connexion, le scope workflow étant requis pour pousser .github/workflows/).
gh_ready() {
    if ! gh_present; then
        err_t bot.no_gh
        return 1
    fi
    if ! gh_connected; then
        err_t gh.not_logged
        return 1
    fi
}

# Contrôle du transport forge : github = gh_ready ; gitlab = glab connecté
# ou REPOWARDEN_GITLAB_TOKEN exploitable ; autre plateforme = refus.
# Messages : bot.no_glab (glab absent, pas de jeton), gl.not_token
# (glab présent mais non connecté, sans jeton de secours).
forge_ready() {
    case "$FORGE" in
        github) gh_ready ;;
        gitlab)
            if command -v glab >/dev/null 2>&1 && glab auth status >/dev/null 2>&1; then
                return 0
            fi
            if [ -n "${REPOWARDEN_GITLAB_TOKEN:-}" ]; then
                return 0
            fi
            if command -v glab >/dev/null 2>&1; then
                err_t gl.not_token
            else
                err_t bot.no_glab
            fi
            return 1 ;;
        *)
            err_t bot.no_glab
            return 1 ;;
    esac
}

# REPLY = chemin du projet GitLab tiré du remote origin, / encodé en %2F
# (bash 3.2 : pas de tableau associatif, sed fait l'encodage manuel).
# Accepte une URL en argument, sinon utilise remote.origin.url.
forge_project_id_r() {
    local url="${1:-$(git remote get-url origin 2>/dev/null || true)}"
    [ -n "$url" ] || { REPLY=""; return 1; }
    case "$url" in
        *://*) url="${url#*://}"; url="${url#*/}" ;;
        *@*:*) url="${url#*:}" ;;
    esac
    url="${url%.git}"
    REPLY="$(printf '%s' "$url" | sed 's|/|%2F|g')"
}

# forge_api <verbe> <chemin> [args…] : transport forge.
#   github : gh api -X VERBE chemin args…  (comportement inchangé)
#   gitlab : REPOWARDEN_GITLAB_TOKEN défini -> curl + PRIVATE-TOKEN (CI et
#            poste) sur /api/v4 ; sinon glab connecté -> glab api --hostname
#            (chemin relatif à /api/v4, champs -f) ; sinon gl.not_token.
# Les champs -d des appelants deviennent -f pour glab api.
# JSON sur stdout ; sortie non nulle en cas d'erreur. Le jeton n'est jamais affiché.
forge_api() {
    local verbe="$1" chemin="$2"; shift 2
    case "$FORGE" in
        github)
            gh api -X "$verbe" "$chemin" "$@" ;;
        gitlab)
            if [ -n "${REPOWARDEN_GITLAB_TOKEN:-}" ]; then
                local base="${CI_API_V4_URL:-https://${FORGE_URL:-gitlab.com}/api/v4}"
                [ "${REPOWARDEN_GITLAB_INSECURE_HTTP:-}" = 1 ] && base="${base/https:/http:}"
                curl --fail --silent --show-error -H "PRIVATE-TOKEN: $REPOWARDEN_GITLAB_TOKEN" -X "$verbe" "$base/$chemin" "$@"
            elif command -v glab >/dev/null 2>&1 && glab auth status >/dev/null 2>&1; then
                local args=()
                while [ $# -gt 0 ]; do
                    case "$1" in
                        -d)
                            if [ $# -ge 2 ]; then args+=(-f "$2"); shift 2; else shift; fi ;;
                        *)
                            args+=("$1"); shift ;;
                    esac
                done
                glab api --hostname "${FORGE_URL:-gitlab.com}" -X "$verbe" "$chemin" "${args[@]+"${args[@]}"}"
            else
                err_t gl.not_token
                return 1
            fi ;;
        *)
            err_t bot.no_glab
            return 1 ;;
    esac
}

# forge_get|forge_post|forge_put|forge_delete <chemin> [args…]
forge_get()    { REPLY="$(forge_api GET    "$@")" || return 1; }
# forge_post <chemin> [args…] : POST via le transport forge (gh api, curl ou glab api).
forge_post()   { REPLY="$(forge_api POST   "$@")" || return 1; }
# forge_put <chemin> [args…] : PUT via le transport forge (gh api, curl ou glab api).
forge_put()    { REPLY="$(forge_api PUT    "$@")" || return 1; }
# forge_delete <chemin> [args…] : DELETE via le transport forge (gh api, curl ou glab api).
forge_delete() { REPLY="$(forge_api DELETE "$@")" || return 1; }

# --- Fonctions sémantiques (issues) ---

# forge_issue_view_r n [champs…] : REPLY = JSON de l'issue $n (iid sur GitLab,
# champs GitHub par defaut : number,title,state,body).
forge_issue_view_r() {
    local n="$1"; shift
    case "$FORGE" in
        github)
            # --json sans champs est une erreur gh : champs par defaut
            if [ $# -gt 0 ]; then
                REPLY="$(gh issue view "$n" --json "$@" 2>/dev/null)"
            else
                REPLY="$(gh issue view "$n" --json number,title,state,body 2>/dev/null)"
            fi ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}/issues/${n}" || return 1 ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_issue_create_r titre corps [labels…] : REPLY = JSON/URL de l'issue créée.
forge_issue_create_r() {
    local titre="$1" corps="$2"; shift 2
    case "$FORGE" in
        github)
            if [ $# -gt 0 ]; then
                REPLY="$(gh issue create --title "$titre" --body "$corps" --label "$@" 2>/dev/null)"
            else
                REPLY="$(gh issue create --title "$titre" --body "$corps" 2>/dev/null)"
            fi ;;
        gitlab)
            # forge_get/forge_post remplissent REPLY : tout capture la vide
            forge_post "projects/${FORGE_PROJECT}/issues" -d "title=${titre}" -d "description=${corps}" "$@" || return 1 ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_issue_comment n texte : ajoute un commentaire à l'issue $n.
forge_issue_comment() {
    local n="$1" texte="$2"; shift 2
    case "$FORGE" in
        github)
            gh issue comment "$n" --body "$texte" >/dev/null 2>&1 ;;
        gitlab)
            forge_post "projects/${FORGE_PROJECT}/issues/${n}/notes" -d "body=${texte}" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_issue_labels_r n : REPLY = tableau JSON des labels de l'issue $n.
forge_issue_labels_r() {
    local n="$1"
    case "$FORGE" in
        github)
            REPLY="$(gh issue view "$n" --json labels -q '.labels[].name' 2>/dev/null)" ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}/issues/${n}" || return 1
            REPLY="$(printf '%s' "$REPLY" | jq -r '.labels[]' 2>/dev/null)" ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_issue_labels_add n label… : ajoute les labels (noms, séparés par virgule).
forge_issue_labels_add() {
    local n="$1" labels="" label; shift
    case "$FORGE" in
        github)
            gh issue edit "$n" --add-label "$@" >/dev/null 2>&1 ;;
        gitlab)
            for label in "$@"; do labels="${labels:+$labels,}$label"; done
            forge_put "projects/${FORGE_PROJECT}/issues/${n}" -d "add_labels=${labels}" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_issue_labels_remove n label… : retire les labels (noms, séparés par virgule).
forge_issue_labels_remove() {
    local n="$1" labels="" label; shift
    case "$FORGE" in
        github)
            gh issue edit "$n" --remove-label "$@" >/dev/null 2>&1 ;;
        gitlab)
            for label in "$@"; do labels="${labels:+$labels,}$label"; done
            forge_put "projects/${FORGE_PROJECT}/issues/${n}" -d "remove_labels=${labels}" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_issue_list_r [filtres…] : REPLY = JSON des issues ouvertes.
forge_issue_list_r() {
    case "$FORGE" in
        github)
            REPLY="$(gh issue list --json "$@" 2>/dev/null)" ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}/issues" "$@" || return 1 ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# --- Fonctions sémantiques (merge requests) ---

# forge_mr_view_r iid : REPLY = JSON de la MR $iid.
forge_mr_view_r() {
    local iid="$1"
    case "$FORGE" in
        github)
            REPLY="$(gh pr view "$iid" --json number,title,state 2>/dev/null)" ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}/merge_requests/${iid}" || return 1 ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_mr_list_r [filtres…] : REPLY = JSON des MR ouvertes.
forge_mr_list_r() {
    case "$FORGE" in
        github)
            REPLY="$(gh pr list --json "$@" 2>/dev/null)" ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}/merge_requests" "$@" || return 1 ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_mr_create_r titre corps [source_branch] [--draft] : REPLY = JSON/URL de la MR créée.
forge_mr_create_r() {
    local titre="$1" corps="$2"; shift 2
    local draft=""
    [ "${1:-}" = "--draft" ] && { draft="true"; shift; }
    local source="${1:-}"; shift
    case "$FORGE" in
        github)
            if [ -n "$draft" ]; then
                REPLY="$(gh pr create --title "$titre" --body "$corps" --head "$source" --draft 2>/dev/null)"
            else
                REPLY="$(gh pr create --title "$titre" --body "$corps" --head "$source" 2>/dev/null)"
            fi ;;
        gitlab)
            local args=(-d "title=${titre}" -d "description=${corps}" -d "source_branch=${source}"
                -d "squash=true" -d "remove_source_branch=true")
            [ -n "$draft" ] && args+=(-d "draft=true")
            forge_post "projects/${FORGE_PROJECT}/merge_requests" "${args[@]}" || return 1 ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_mr_edit_r iid [champs…] : modifie la MR $iid.
forge_mr_edit_r() {
    local iid="$1"; shift
    case "$FORGE" in
        github)
            gh pr edit "$iid" "$@" >/dev/null 2>&1 ;;
        gitlab)
            forge_put "projects/${FORGE_PROJECT}/merge_requests/${iid}" "$@" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_mr_merge_auto iid : merge automatique (squash si pipeline en cours/vert).
forge_mr_merge_auto() {
    local iid="$1"
    case "$FORGE" in
        github)
            gh pr merge "$iid" --auto --squash >/dev/null 2>&1 ;;
        gitlab)
            forge_put "projects/${FORGE_PROJECT}/merge_requests/${iid}/merge" -d "merge_when_pipeline_succeeds=true" -d "squash=true" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_mr_close iid commentaire : ferme la MR $iid avec un commentaire.
forge_mr_close() {
    local iid="$1" commentaire="$2"; shift 2
    case "$FORGE" in
        github)
            gh pr close "$iid" --comment "$commentaire" >/dev/null 2>&1 ;;
        gitlab)
            forge_put "projects/${FORGE_PROJECT}/merge_requests/${iid}" -d "state_event=close" >/dev/null
            forge_post "projects/${FORGE_PROJECT}/merge_requests/${iid}/notes" -d "body=${commentaire}" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# --- Fonctions sémantiques (statuts de commit) ---

# forge_status_post sha contexte etat description : publie un statut externe.
forge_status_post() {
    local sha="$1" contexte="$2" etat="$3" description="$4"; shift 4
    case "$FORGE" in
        github)
            gh api "repos/${GITHUB_REPOSITORY:-}/statuses/${sha}" -X POST \
                -f context="$contexte" -f state="$etat" -f description="$description" "$@" >/dev/null 2>&1 ;;
        gitlab)
            forge_post "projects/${FORGE_PROJECT}/statuses/${sha}" \
                -d "name=${contexte}" -d "state=${etat}" -d "description=${description}" "$@" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# --- Fonctions sémantiques (branches) ---

# forge_branch_create nom ref : crée la branche $nom sur $ref.
forge_branch_create() {
    local nom="$1" ref="$2"; shift 2
    case "$FORGE" in
        github)
            gh api "repos/${GITHUB_REPOSITORY:-}/git/refs" -X POST \
                -f "ref=refs/heads/${nom}" -f "sha=${ref}" "$@" >/dev/null 2>&1 ;;
        gitlab)
            forge_post "projects/${FORGE_PROJECT}/repository/branches" \
                -d "branch=${nom}" -d "ref=${ref}" "$@" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_branch_delete nom : supprime la branche $nom.
forge_branch_delete() {
    local nom="$1"; shift
    case "$FORGE" in
        github)
            gh api "repos/${GITHUB_REPOSITORY:-}/git/refs/heads/${nom}" -X DELETE >/dev/null 2>&1 ;;
        gitlab)
            forge_delete "projects/${FORGE_PROJECT}/repository/branches/${nom}" >/dev/null ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_compare_ahead_r base head : REPLY = nombre de commits d'avance de head sur base.
forge_compare_ahead_r() {
    local base="$1" head="$2"
    case "$FORGE" in
        github)
            REPLY="$(gh api "repos/${GITHUB_REPOSITORY:-}/compare/${base}...${head}" -q '.ahead_by // 0' 2>/dev/null || echo 0)" ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}/repository/compare?from=${base}&to=${head}" || return 1
            REPLY="$(printf '%s' "$REPLY" | jq -r '.commits | length // 0' 2>/dev/null || echo 0)" ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_mr_commits_r iid : REPLY = JSON des commits de la MR $iid.
forge_mr_commits_r() {
    local iid="$1"
    case "$FORGE" in
        github)
            REPLY="$(gh pr view "$iid" --json commits 2>/dev/null)" ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}/merge_requests/${iid}/commits" || return 1 ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_notes_r n : REPLY = JSON des commentaires de l'issue $n.
forge_notes_r() {
    local n="$1"
    case "$FORGE" in
        github)
            REPLY="$(gh issue view "$n" --json comments 2>/dev/null)" ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}/issues/${n}/notes" || return 1 ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# --- Fonctions sémantiques (membres / dépôt) ---

# forge_est_mainteneur_r user : REPLY = true si l'utilisateur a le droit de
# merger (GitHub collaborators/permission dans admin|maintain|write,
# GitLab access_level >= 40 de members/all/:id).
forge_est_mainteneur_r() {
    local user="$1"
    case "$FORGE" in
        github)
            # Permission du collaborateur : admin / maintain / write
            local perm
            perm="$(gh api "repos/${GITHUB_REPOSITORY:-}/collaborators/${user}/permission" 2>/dev/null | jq -r '.permission // "none"')"
            case "$perm" in admin | maintain | write) REPLY=true ;; *) REPLY=false ;; esac ;;
        gitlab)
            # GET /projects/:id/members/all?username= (tableau) pour tirer
            # l'identifiant, puis GET /members/all/:id : objet, .access_level.
            forge_get "projects/${FORGE_PROJECT}/members/all?username=${user}" || return 1
            local id
            id="$(printf '%s' "$REPLY" | jq -r '.[0].id // empty' 2>/dev/null || true)"
            if [ -n "$id" ]; then
                local niveau
                forge_get "projects/${FORGE_PROJECT}/members/all/${id}" || return 1
                niveau="$(printf '%s' "$REPLY" | jq -r '.access_level // 0' 2>/dev/null || echo 0)"
                [ "$niveau" -ge 40 ] 2>/dev/null && REPLY=true || REPLY=false
            else
                REPLY=false
            fi ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_repo_admin_r : REPLY = true si l'utilisateur est administrateur du dépôt.
forge_repo_admin_r() {
    case "$FORGE" in
        github)
            local admin
            admin="$(gh api "repos/${GITHUB_REPOSITORY:-}" -q '.permissions.admin // false' 2>/dev/null || echo false)"
            [ "$admin" = true ] && REPLY=true || REPLY=false ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}" || return 1
            local niveau
            niveau="$(printf '%s' "$REPLY" | jq -r '.project_access.access_level // 0' 2>/dev/null || echo 0)"
            [ "$niveau" -ge 40 ] 2>/dev/null && REPLY=true || REPLY=false ;;
        *)
            err_t bot.no_glab; return 1 ;;
    esac
}

# forge_default_branch_r : REPLY = branche par défaut du dépôt.
forge_default_branch_r() {
    case "$FORGE" in
        github)
            REPLY="$(gh api "repos/${GITHUB_REPOSITORY:-}" -q '.default_branch // "main"' 2>/dev/null || echo main)" ;;
        gitlab)
            forge_get "projects/${FORGE_PROJECT}" || return 1
            REPLY="$(printf '%s' "$REPLY" | jq -r '.default_branch // "main"' 2>/dev/null || echo main)" ;;
        *)
            REPLY="main" ;;
    esac
}

# forge_labels_ajouter_si_absentes label… : crée les labels manquants sur le dépôt.
forge_labels_ajouter_si_absentes() {
    local label
    for label in "$@"; do
        case "$FORGE" in
            github)
                gh label create "$label" >/dev/null 2>&1 || true ;;
            gitlab)
                forge_post "projects/${FORGE_PROJECT}/labels" -d "name=${label}" -d "color=fbca00" >/dev/null 2>&1 || true ;;
            *)
                err_t bot.no_glab; return 1 ;;
        esac
    done
}

forge_init
