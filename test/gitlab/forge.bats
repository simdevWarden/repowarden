#!/usr/bin/env bats
# Tests d'intégration GitLab pour la couche forge (ticket #533).
# S'exécute avec : REPOWARDEN_IT_GITLAB_URL=http://gitlab.localhost:8929
# REPOWARDEN_IT_GITLAB_TOKEN=jeton-root bats test/gitlab/forge.bats
# Voir CONTRIBUTING.md ("Tests contre GitLab").
#
# Un projet "repowarden-it-<date>-<alea>" est cree en setup_file, et supprime
# en teardown_file (jamais de jeton en clair dans la sortie).
# Sans REPOWARDEN_IT_GITLAB_URL / REPOWARDEN_IT_GITLAB_TOKEN, tout est saute.

load ../helpers

# helpers.bash calcule HOOKS depuis BATS_TEST_DIRNAME/../hooks, juste pour un
# fichier de test directement dans test/ ; depuis test/gitlab/ il faut remonter
# jusqu'a la racine du depot pour trouver hooks/.
HOOKS=""
_d="$BATS_TEST_DIRNAME"
while [ -n "$_d" ] && [ "$_d" != "/" ]; do
    if [ -d "$_d/hooks" ]; then HOOKS="$_d/hooks"; break; fi
    _d="$(cd "$_d/.." 2>/dev/null && pwd -P)"
done
unset _d
[ -n "$HOOKS" ] || { echo "dossier hooks introuvable" >&2; exit 1; }

# Configure l'acces forge GitLab depuis les variables d'integration.
# (appele dans setup_file, setup et teardown_file : bats isole chaque
# etape dans son propre processus, rien n'y survit d'une etape a l'autre).
forge_env() {
    hote="${REPOWARDEN_IT_GITLAB_URL#*://}"
    hote="${hote%%/*}"
    export FORGE=gitlab
    export FORGE_URL="$hote"
    export REPOWARDEN_GITLAB_HOST="$hote"
    export REPOWARDEN_GITLAB_TOKEN="$REPOWARDEN_IT_GITLAB_TOKEN"
    case "${REPOWARDEN_IT_GITLAB_URL}" in
        http://*) export REPOWARDEN_GITLAB_INSECURE_HTTP=1 ;;
    esac
}

charger_forge() {
    source "$HOOKS/lib/common.sh"
    source "$HOOKS/lib/forge.sh"
}

setup_file() {
    if [ -z "${REPOWARDEN_IT_GITLAB_URL:-}" ] || [ -z "${REPOWARDEN_IT_GITLAB_TOKEN:-}" ]; then
        skip "REPOWARDEN_IT_GITLAB_URL ou REPOWARDEN_IT_GITLAB_TOKEN absent : tests GitLab sautes"
    fi
    charger_forge
    forge_env
    command -v jq >/dev/null 2>&1 || { echo "jq absent" >&2; exit 1; }

    nom="repowarden-it-$(date +%s)-$RANDOM"
    forge_post projects -d "name=$nom" -d "initialize_with_readme=true" -d "default_branch=main"
    IT_CHEMIN="$(printf '%s' "$REPLY" | jq -r '.path_with_namespace // empty')"
    [ -n "$IT_CHEMIN" ] || { echo "projet non cree : $REPLY" >&2; exit 1; }
    IT_NOM="$nom"
    export IT_NOM
    FORGE_PROJECT="$(printf '%s' "$IT_CHEMIN" | sed 's|/|%2F|g')"
    export FORGE_PROJECT
    printf '%s\n' "$IT_CHEMIN" >"$BATS_FILE_TMPDIR/pret"
    printf '%s\n' "$IT_CHEMIN" >"$BATS_FILE_TMPDIR/chemin"
    printf '%s\n' "$FORGE_PROJECT" >"$BATS_FILE_TMPDIR/projet"
    printf '%s\n' "$nom" >"$BATS_FILE_TMPDIR/nom"

    forge_get "projects/$FORGE_PROJECT/repository/branches/main"
    IT_SHA="$(printf '%s' "$REPLY" | jq -r '.commit.id // empty')"
    [ -n "$IT_SHA" ] || { echo "sha de main introuvable : $REPLY" >&2; exit 1; }
    export IT_SHA
    printf '%s\n' "$IT_SHA" >"$BATS_FILE_TMPDIR/sha"
}

setup() {
    charger_forge
    forge_env
    if [ -f "$BATS_FILE_TMPDIR/chemin" ]; then
        IT_CHEMIN="$(cat "$BATS_FILE_TMPDIR/chemin")"
        export IT_CHEMIN
    fi
    if [ -f "$BATS_FILE_TMPDIR/projet" ]; then
        FORGE_PROJECT="$(cat "$BATS_FILE_TMPDIR/projet")"
        export FORGE_PROJECT
    fi
    if [ -f "$BATS_FILE_TMPDIR/nom" ]; then
        IT_NOM="$(cat "$BATS_FILE_TMPDIR/nom")"
        export IT_NOM
    fi
    if [ -f "$BATS_FILE_TMPDIR/sha" ]; then
        IT_SHA="$(cat "$BATS_FILE_TMPDIR/sha")"
        export IT_SHA
    fi
}

teardown_file() {
    [ -f "$BATS_FILE_TMPDIR/pret" ] || return 0
    charger_forge
    forge_env
    chemin="$(cat "$BATS_FILE_TMPDIR/pret")"
    case "${chemin##*/}" in
        repowarden-it-*) ;;
        *) echo "refus de supprimer $chemin" >&2; return 1 ;;
    esac
    enc="$(printf '%s' "$chemin" | sed 's|/|%2F|g')"
    forge_delete "projects/$enc" >/dev/null 2>&1 || true
    forge_delete "projects/$enc?permanently_remove=true&full_path=$enc" >/dev/null 2>&1 || true
}

# --- issue ---

@test "issue : creer puis lire une issue" {
    forge_issue_create_r "titre-it" "corps-it"
    iid="$(printf '%s' "$REPLY" | jq -r '.iid // empty')"
    [ -n "$iid" ] || { echo "iid manquant : $REPLY" >&2; exit 1; }
    printf '%s\n' "$iid" >"$BATS_FILE_TMPDIR/iid"

    forge_issue_view_r "$iid"
    [ "$(printf '%s' "$REPLY" | jq -r '.title')" = "titre-it" ] || { echo "titre : $REPLY" >&2; exit 1; }
    [ "$(printf '%s' "$REPLY" | jq -r '.state')" = opened ] || { echo "etat : $REPLY" >&2; exit 1; }
}

# --- commentaire ---

@test "commentaire : ajouter une note puis la relire" {
    forge_issue_create_r "titre-com" "corps-com"
    iid="$(printf '%s' "$REPLY" | jq -r '.iid // empty')"
    [ -n "$iid" ] || { echo "iid manquant : $REPLY" >&2; exit 1; }

    forge_issue_comment "$iid" "note-it"
    forge_notes_r "$iid"
    [ "$(printf '%s' "$REPLY" | jq -r '.[] | select(.body=="note-it") | .body')" = "note-it" ] || { echo "note absente : $REPLY" >&2; exit 1; }
}

# --- labels ---

@test "labels : ajouter it-a it-b, puis retirer it-a" {
    forge_issue_create_r "titre-lab" "corps-lab"
    iid="$(printf '%s' "$REPLY" | jq -r '.iid // empty')"
    [ -n "$iid" ] || { echo "iid manquant : $REPLY" >&2; exit 1; }

    forge_issue_labels_add "$iid" it-a it-b
    forge_issue_labels_r "$iid"
    lab="$(printf '%s' "$REPLY")"
    [[ "$lab" == *it-a* ]] || { echo "it-a absent : $REPLY" >&2; exit 1; }
    [[ "$lab" == *it-b* ]] || { echo "it-b absent : $REPLY" >&2; exit 1; }

    forge_issue_labels_remove "$iid" it-a
    forge_issue_labels_r "$iid"
    lab="$(printf '%s' "$REPLY")"
    [[ "$lab" != *it-a* ]] || { echo "it-a encore present : $REPLY" >&2; exit 1; }
    [[ "$lab" == *it-b* ]] || { echo "it-b disparu : $REPLY" >&2; exit 1; }
}

# --- liste ---

@test "liste : les issues du projet contiennent l'iid cree" {
    [ -f "$BATS_FILE_TMPDIR/iid" ] || skip "issue precedente non creee"
    iid="$(cat "$BATS_FILE_TMPDIR/iid")"
    forge_issue_list_r
    [[ "$REPLY" == *"\"iid\":$iid"* ]] || { echo "iid $iid absent de la liste : $REPLY" >&2; exit 1; }
}

# --- statut de commit ---

@test "statut : publier un statut puis le relire sur le commit" {
    forge_status_post "$IT_SHA" it/contexte success "statut-it"
    forge_get "projects/$FORGE_PROJECT/repository/commits/$IT_SHA/statuses"
    [ "$(printf '%s' "$REPLY" | jq -r '.[] | select(.name=="it/contexte") | .status')" = success ] || { echo "statut : $REPLY" >&2; exit 1; }
}

# --- branche + MR ---

@test "branche et MR : creer la branche it/mr, y committer, creer et clore la MR" {
    forge_branch_create it/mr main
    forge_post "projects/$FORGE_PROJECT/repository/files/it.txt" -d branch=it/mr -d content=x -d "commit_message=test: it"

    forge_compare_ahead_r main it/mr
    [ "$REPLY" = 1 ] || { echo "compare : $REPLY" >&2; exit 1; }

    forge_mr_create_r "mr-it" "corps" it/mr
    miid="$(printf '%s' "$REPLY" | jq -r '.iid // empty')"
    [ -n "$miid" ] || { echo "iid MR manquant : $REPLY" >&2; exit 1; }
    printf '%s\n' "$miid" >"$BATS_FILE_TMPDIR/miid"

    forge_mr_list_r
    [[ "$REPLY" == *"\"iid\":$miid"* ]] || { echo "MR $miid absente de la liste : $REPLY" >&2; exit 1; }

    forge_mr_view_r "$miid"
    [ "$(printf '%s' "$REPLY" | jq -r '.title')" = "mr-it" ] || { echo "titre MR : $REPLY" >&2; exit 1; }

    forge_mr_close "$miid" "fermee"
    forge_mr_view_r "$miid"
    [ "$(printf '%s' "$REPLY" | jq -r '.state')" = closed ] || { echo "etat MR : $REPLY" >&2; exit 1; }
}

# --- suppression de branche ---

@test "branche : creer it/sup puis la supprimer" {
    forge_branch_create it/sup main
    forge_branch_delete it/sup
    if forge_get "projects/$FORGE_PROJECT/repository/branches/it%2Fsup" >/dev/null 2>&1; then
        echo "branche it/sup encore presente" >&2; exit 1
    fi
}

# --- mainteneur ---

@test "mainteneur : le jeton est mainteneur, un inconnu ne l'est pas" {
    forge_get user
    utilisateur="$(printf '%s' "$REPLY" | jq -r '.username // empty')"
    [ -n "$utilisateur" ] || { echo "utilisateur du jeton : $REPLY" >&2; exit 1; }

    forge_est_mainteneur_r "$utilisateur"
    [ "$REPLY" = true ] || { echo "$utilisateur mainteneur : $REPLY" >&2; exit 1; }

    forge_est_mainteneur_r "inexistant-$RANDOM"
    [ "$REPLY" = false ] || { echo "inconnu mainteneur : $REPLY" >&2; exit 1; }
}

# --- branche par defaut ---

@test "branche par defaut : main exactement" {
    forge_default_branch_r
    [ "$REPLY" = main ] || { echo "branche par defaut : $REPLY" >&2; exit 1; }
}

# --- jeton jamais affiche ---

@test "jeton : jamais affiche, ni en 404 ni en succes" {
    run forge_get "projects/$FORGE_PROJECT/issues/999999"
    [ "$status" -ne 0 ] || { echo "404 attendu, status=$status" >&2; exit 1; }
    [[ "$output" != *"$REPOWARDEN_GITLAB_TOKEN"* ]] || { echo "token fuit (404)" >&2; exit 1; }

    run forge_get "projects/$FORGE_PROJECT/issues"
    [ "$status" -eq 0 ] || { echo "appel reussi attendu, status=$status" >&2; exit 1; }
    [[ "$output" != *"$REPOWARDEN_GITLAB_TOKEN"* ]] || { echo "token fuit (succes)" >&2; exit 1; }
}
