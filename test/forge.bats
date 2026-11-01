#!/usr/bin/env bats
# Couche d'accès forge : dispatch GitHub vs GitLab vérifié ligne à ligne
# (chemin d'API, en-tête PRIVATE-TOKEN, jeton jamais affiché, encodage du projet).
# Faux gh, faux curl et faux glab dans le PATH (technique test/bots.bats).

load helpers

F="$BATS_TEST_TMPDIR/f"

setup() {
    setup_repo
    initial_commit
    mkdir -p "$F/bin"
    : >"$F/log"
    create_fake_gh
    create_fake_curl
    chmod +x "$F/bin/gh" "$F/bin/curl"
    export PATH="$F/bin:$PATH" FAKE="$F"
    unset GITHUB_ACTIONS GITLAB_CI CI_SERVER_HOST REPOWARDEN_GITLAB_HOST REPOWARDEN_GITLAB_TOKEN REPOWARDEN_GITLAB_INSECURE_HTTP GITHUB_REPOSITORY
    git config --unset repowarden.forge 2>/dev/null || true
    git config --unset repowarden.platform 2>/dev/null || true
    git config --unset repowarden.gitlabHost 2>/dev/null || true
}

create_fake_gh() {
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE/log"
case "$*" in
    "auth status"*) exit 0 ;;
    "issue view"*) echo '{"id":1,"iid":12,"title":"titre","state":"opened","labels":[]}' ;;
    "issue create"*) echo "https://github.com/o/r/issues/12" ;;
    "issue comment"*) exit 0 ;;
    "issue edit"*) exit 0 ;;
    "issue list"*) echo '[]' ;;
    "pr view"*) echo '{"id":1,"number":34,"title":"MR","state":"opened"}' ;;
    "pr create"*) echo "https://github.com/o/r/pull/34" ;;
    "pr edit"*) exit 0 ;;
    "pr list"*) echo '[]' ;;
    "pr merge"*) exit 0 ;;
    "pr close"*) exit 0 ;;
    "label create"*) exit 0 ;;
    "api repos/o/r"*) echo '{"permissions":{"moi":{"authorAssociation":"MEMBER"}},"default_branch":"main"}' ;;
    "api"*) echo '{}' ;;
esac
exit 0
GH
}

create_fake_curl() {
    cat >"$F/bin/curl" <<'CURL'
#!/usr/bin/env bash
echo "curl $*" >>"$FAKE/log"
case "$*" in
    *issues*) echo '[{"id":1,"iid":12,"title":"titre","state":"opened","labels":[]}]' ;;
    *merge_requests*) echo '[{"id":1,"iid":34,"title":"MR","state":"opened"}]' ;;
    *statuses*) echo '{}' ;;
    *repository/branches*) echo '{}' ;;
    *repository/compare*) echo '{"commits":[]}' ;;
    *members/all*) echo '[{"id":1,"access_level":40}]' ;;
    *) echo '{}' ;;
esac
exit 0
CURL
}

create_fake_glab() {
    cat >"$F/bin/glab" <<'GLAB'
#!/usr/bin/env bash
echo "glab $*" >>"$FAKE/log"
case "$*" in
    "auth status"*) exit 0 ;;
esac
case "$*" in
    *issues*) echo '[{"id":1,"iid":12,"title":"titre","state":"opened","labels":[]}]' ;;
    *merge_requests*) echo '[{"id":1,"iid":34,"title":"MR","state":"opened"}]' ;;
    *statuses*) echo '{}' ;;
    *repository/branches*) echo '{}' ;;
    *repository/compare*) echo '{"commits":[]}' ;;
    *members/all*) echo '[{"id":1,"access_level":40}]' ;;
    *) echo '{}' ;;
esac
exit 0
GLAB
    chmod +x "$F/bin/glab"
}

# --- forge_init : FORGE_URL, ordre de priorite ---

@test "forge_init : FORGE_URL, REPOWARDEN_GITLAB_HOST prioritaire sur CI_SERVER_HOST" {
    (
        export REPOWARDEN_GITLAB_HOST=gitlab.monentreprise.fr
        export CI_SERVER_HOST=gitlab.ci.fr
        export GITLAB_CI=1
        export REPOWARDEN_GITLAB_TOKEN=jeton-test
        source "$HOOKS/lib/common.sh"
        [ "$FORGE_URL" = gitlab.monentreprise.fr ] || { echo "FORGE_URL=$FORGE_URL"; exit 1; }
    ) || false
}

@test "forge_init : FORGE_URL, CI_SERVER_HOST puis git config repowarden.gitlabHost" {
    (
        export CI_SERVER_HOST=gitlab.ci.fr
        export GITLAB_CI=1
        export REPOWARDEN_GITLAB_TOKEN=jeton-test
        source "$HOOKS/lib/common.sh"
        [ "$FORGE_URL" = gitlab.ci.fr ] || { echo "FORGE_URL=$FORGE_URL"; exit 1; }
    ) || false
}

@test "forge_init : FORGE_URL, git config repowarden.gitlabHost" {
    (
        export GITLAB_CI=1
        export REPOWARDEN_GITLAB_TOKEN=jeton-test
        git config repowarden.gitlabHost gitlab.config.fr
        source "$HOOKS/lib/common.sh"
        [ "$FORGE_URL" = gitlab.config.fr ] || { echo "FORGE_URL=$FORGE_URL"; exit 1; }
    ) || false
}

@test "forge_init : FORGE_URL, defaut gitlab.com" {
    (
        export GITLAB_CI=1
        export REPOWARDEN_GITLAB_TOKEN=jeton-test
        source "$HOOKS/lib/common.sh"
        [ "$FORGE_URL" = gitlab.com ] || { echo "FORGE_URL=$FORGE_URL"; exit 1; }
    ) || false
}

# --- forge_init : alias repowarden.platform ---

@test "forge_init : repowarden.platform alias de repowarden.forge" {
    (
        git config repowarden.platform gitlab
        source "$HOOKS/lib/common.sh"
        [ "$FORGE" = gitlab ] || { echo "FORGE=$FORGE"; exit 1; }
    ) || false
}

@test "forge_init : repowarden.forge l'emporte sur repowarden.platform" {
    (
        git config repowarden.forge github
        git config repowarden.platform gitlab
        source "$HOOKS/lib/common.sh"
        [ "$FORGE" = github ] || { echo "FORGE=$FORGE"; exit 1; }
    ) || false
}

# --- forge_project_id_r : encodage / en %2F ---

@test "forge_project_id_r : https encode / en %2F" {
    (
        source "$HOOKS/lib/common.sh"
        forge_project_id_r 'https://gitlab.com/groupe/projet.git'
        [ "$REPLY" = 'groupe%2Fprojet' ] || { echo "REPLY=$REPLY"; exit 1; }
    ) || false
}

@test "forge_project_id_r : ssh encode / en %2F" {
    (
        source "$HOOKS/lib/common.sh"
        forge_project_id_r 'git@gitlab.com:groupe/projet.git'
        [ "$REPLY" = 'groupe%2Fprojet' ] || { echo "REPLY=$REPLY"; exit 1; }
    ) || false
}

@test "forge_project_id_r : sous-groupes et port encodes" {
    (
        source "$HOOKS/lib/common.sh"
        forge_project_id_r 'http://gitlab.localhost:8929/a/b/c.git'
        [ "$REPLY" = 'a%2Fb%2Fc' ] || { echo "REPLY=$REPLY"; exit 1; }
    ) || false
}

# --- forge_ready ---

@test "forge_ready : github, gh presente et connectee" {
    (
        export GITHUB_ACTIONS=1
        source "$HOOKS/lib/common.sh"
        forge_ready || { echo "forge_ready échec github"; exit 1; }
    ) || false
}

@test "forge_ready : gitlab, jeton presente (sans glab)" {
    (
        export GITLAB_CI=1
        export REPOWARDEN_GITLAB_TOKEN=jeton-test
        source "$HOOKS/lib/common.sh"
        forge_ready || { echo "forge_ready échec gitlab"; exit 1; }
    ) || false
}

@test "forge_ready : gitlab, ni glab ni jeton -> echec" {
    (
        export GITLAB_CI=1
        source "$HOOKS/lib/common.sh"
        ! forge_ready || { echo "forge_ready aurait dû echouer"; exit 1; }
    ) || false
}

# --- forge_get|forge_post|forge_put|forge_delete : dispatch GitHub ---

@test "forge_get github : gh api -X GET avec le chemin" {
    (
        export GITHUB_ACTIONS=1
        export GITHUB_REPOSITORY=o/r
        git remote set-url origin https://github.com/o/r.git
        source "$HOOKS/lib/common.sh"
        forge_get 'repos/o/r/issues/12'
        [ "$REPLY" = '{}' ] || { echo "REPLY=$REPLY"; exit 1; }
    ) || false
    grep -q "gh api -X GET repos/o/r/issues/12" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_post github : gh api -X POST avec arguments" {
    (
        export GITHUB_ACTIONS=1
        export GITHUB_REPOSITORY=o/r
        git remote set-url origin https://github.com/o/r.git
        source "$HOOKS/lib/common.sh"
        forge_post 'repos/o/r/issues' -f title=t -f body=b
        [ "$REPLY" = '{}' ] || { echo "REPLY=$REPLY"; exit 1; }
    ) || false
    grep -q "gh api -X POST repos/o/r/issues" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_put github : gh api -X PUT" {
    (
        export GITHUB_ACTIONS=1
        export GITHUB_REPOSITORY=o/r
        git remote set-url origin https://github.com/o/r.git
        source "$HOOKS/lib/common.sh"
        forge_put 'repos/o/r/merge_requests/34' -f title=t
    ) || false
    grep -q "gh api -X PUT repos/o/r/merge_requests/34" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_delete github : gh api -X DELETE" {
    (
        export GITHUB_ACTIONS=1
        export GITHUB_REPOSITORY=o/r
        git remote set-url origin https://github.com/o/r.git
        source "$HOOKS/lib/common.sh"
        forge_delete 'repos/o/r/branches/old'
    ) || false
    grep -q "gh api -X DELETE repos/o/r/branches/old" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

# --- forge_get|forge_post|forge_put|forge_delete : dispatch GitLab ---

@test "forge_get gitlab : curl, chemin API v4, en-tete PRIVATE-TOKEN" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_get "projects/groupe%2Fprojet/issues/12"
        [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    ) || false
    grep -q "projects/groupe%2Fprojet/issues/12" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    grep -q "PRIVATE-TOKEN" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    ! grep -q "jeton-secret" "$output" || { echo "jeton affiché : $output"; return 1; }
}

@test "forge_post gitlab : curl, PRIVATE-TOKEN presente, jeton jamais affiche" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_post "projects/groupe%2Fprojet/issues" -d title=t -d description=b
    ) || false
    grep -q "PRIVATE-TOKEN" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    ! grep -q "jeton-secret" "$output" || { echo "jeton affiché : $output"; return 1; }
}

@test "forge_delete gitlab : curl, chemin encode %2F" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_delete "projects/groupe%2Fprojet/repository/branches/old"
    ) || false
    grep -q "projects/groupe%2Fprojet/repository/branches/old" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    grep -q "PRIVATE-TOKEN" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_api gitlab : REPOWARDEN_GITLAB_INSECURE_HTTP=1 utilise http" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        export REPOWARDEN_GITLAB_INSECURE_HTTP=1
        source "$HOOKS/lib/common.sh"
        forge_get "projects/groupe%2Fprojet/issues/12"
    ) || false
    grep -q "http://gitlab.com/api/v4/projects/groupe%2Fprojet/issues/12" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

# --- forge_api gitlab : transport glab quand aucun jeton ---

@test "forge_api gitlab : sans jeton, glab connecte -> glab api avec le chemin" {
    create_fake_glab
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        unset REPOWARDEN_GITLAB_TOKEN
        source "$HOOKS/lib/common.sh"
        forge_post "projects/groupe%2Fprojet/issues" -d title=t -d description=corps
    ) || false
    grep -q "glab api --hostname gitlab.com -X POST projects/groupe%2Fprojet/issues -f title=t -f description=corps" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    ! grep -q "^curl " "$FAKE/log" || { echo "curl appelé : $(cat "$FAKE/log")"; return 1; }
}

@test "forge_api gitlab : jeton present -> curl meme si glab est connecte" {
    create_fake_glab
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_get "projects/groupe%2Fprojet/issues/12"
    ) || false
    grep -q "^curl " "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    ! grep -q "^glab " "$FAKE/log" || { echo "glab appelé : $(cat "$FAKE/log")"; return 1; }
}

@test "forge_api gitlab : ni jeton ni glab connecte -> erreur, aucun appel" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        unset REPOWARDEN_GITLAB_TOKEN
        source "$HOOKS/lib/common.sh"
        ! forge_get "projects/groupe%2Fprojet/issues/12" || { echo "forge_get aurait dû échouer"; exit 1; }
    ) || false
    [ ! -s "$FAKE/log" ] || { echo "appel inattendu : $(cat "$FAKE/log")"; return 1; }
}

# --- Fonctions sémantiques : dispatch GitHub vs GitLab ---

@test "forge_issue_view_r github : gh issue view --json" {
    (
        export GITHUB_ACTIONS=1
        source "$HOOKS/lib/common.sh"
        forge_issue_view_r 12
        [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    ) || false
    grep -q "gh issue view 12 --json" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_issue_view_r gitlab : GET /projects/:id/issues/:n" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_issue_view_r 12
        [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    ) || false
    grep -q "projects/groupe%2Fprojet/issues/12" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_issue_create_r github : gh issue create" {
    (
        export GITHUB_ACTIONS=1
        source "$HOOKS/lib/common.sh"
        forge_issue_create_r 'titre' 'corps'
        [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    ) || false
    grep -q "gh issue create --title titre --body corps" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_issue_create_r gitlab : POST /projects/:id/issues" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_issue_create_r 'titre' 'corps'
    ) || false
    grep -q "projects/groupe%2Fprojet/issues" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    grep -q "PRIVATE-TOKEN" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_mr_create_r github : gh pr create" {
    (
        export GITHUB_ACTIONS=1
        source "$HOOKS/lib/common.sh"
        forge_mr_create_r 'titre' 'corps' 'feature/12'
    ) || false
    grep -q "gh pr create --title titre --body corps --head feature/12" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_mr_create_r gitlab : POST /projects/:id/merge_requests" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_mr_create_r 'titre' 'corps' 'feature/12'
    ) || false
    grep -q "projects/groupe%2Fprojet/merge_requests" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    grep -q "PRIVATE-TOKEN" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_status_post github : gh api statuses" {
    (
        export GITHUB_ACTIONS=1
        export GITHUB_REPOSITORY=o/r
        git remote set-url origin https://github.com/o/r.git
        source "$HOOKS/lib/common.sh"
        forge_status_post abc123 ticket success OK
    ) || false
    grep -q "gh api repos/o/r/statuses/abc123 -X POST" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_status_post gitlab : POST /projects/:id/statuses/:sha" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_status_post abc123 ticket success OK
    ) || false
    grep -q "projects/groupe%2Fprojet/statuses/abc123" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    grep -q "PRIVATE-TOKEN" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_branch_create github : gh api git/refs" {
    (
        export GITHUB_ACTIONS=1
        export GITHUB_REPOSITORY=o/r
        git remote set-url origin https://github.com/o/r.git
        source "$HOOKS/lib/common.sh"
        forge_branch_create feat/12 abc123
    ) || false
    grep -q "gh api repos/o/r/git/refs -X POST" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_branch_create gitlab : POST /repository/branches" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_branch_create feat/12 abc123
    ) || false
    grep -q "projects/groupe%2Fprojet/repository/branches" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
    grep -q "PRIVATE-TOKEN" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_est_mainteneur_r github : authorAssociation" {
    (
        export GITHUB_ACTIONS=1
        export GITHUB_REPOSITORY=o/r
        git remote set-url origin https://github.com/o/r.git
        source "$HOOKS/lib/common.sh"
        forge_est_mainteneur_r moi
        [ "$REPLY" = true ] || { echo "REPLY=$REPLY"; exit 1; }
    ) || false
}

@test "forge_est_mainteneur_r gitlab : access_level >= 40" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_est_mainteneur_r moi
        [ "$REPLY" = true ] || { echo "REPLY=$REPLY"; exit 1; }
    ) || false
    grep -q "projects/groupe%2Fprojet/members/all" "$FAKE/log" || { echo "log: $(cat "$FAKE/log")"; return 1; }
}

@test "forge_default_branch_r gitlab : default_branch du projet" {
    (
        export GITLAB_CI=1
        git remote set-url origin https://gitlab.com/groupe/projet.git
        export REPOWARDEN_GITLAB_TOKEN=jeton-secret
        source "$HOOKS/lib/common.sh"
        forge_default_branch_r
        [ "$REPLY" = main ] || { echo "REPLY=$REPLY"; exit 1; }
    ) || false
}
