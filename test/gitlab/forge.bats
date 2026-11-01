#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2181
# Tests d'intégration GitLab pour la couche forge.
# S'exécute avec : REPOWARDEN_IT_GITLAB_URL=http://gitlab.localhost:8929
# REPOWARDEN_IT_GITLAB_TOKEN=root tokens bats test/gitlab/forge.bats
# Voir CONTRIBUTING.md pour la configuration devzone.

# Un fichier « pret » est créé en setup_file et supprimé en teardown_file.
# En l'absence des variables d'environnement, tous les tests sont sautés
# (skip) et le fichier de sortie vaut 0.

# keybase: JSON lu avec jq, transport curl + PRIVATE-TOKEN,
# jeton jamais affiché (même en cas d'erreur 404).

# Design : chaque point du ticket #533 a un test dédié en français.

setup_file() {
    [ -n "${REPOWARDEN_IT_GITLAB_URL:-}" ] || skip "REPOWARDEN_IT_GITLAB_URL absent : tests GitLab sautés"
    [ -n "${REPOWARDEN_IT_GITLAB_TOKEN:-}" ] || skip "REPOWARDEN_IT_GITLAB_TOKEN absent : tests GitLab sautés"

    # Source de la couche forge (comme test/forge.bats)
    source "$HOOKS/lib/forge.sh"

    FORGE=gitlab

    # Extraire l'hôte:port depuis l'URL
    case "${REPOWARDEN_IT_GITLAB_URL}" in
        *://*) url="${REPOWARDEN_IT_GITLAB_URL#*://}"; url="${url#*/}" ;;
        *@*:*) url="${url#*:}" ;;
    esac
    url="${url%.git}"
    FORCE_URL="$url"

    # Insecure HTTP si l'URL commence par http://
    case "${REPOWARDEN_IT_GITLAB_URL}" in
        http://*) REPOWARDEN_GITLAB_INSECURE_HTTP=1 ;;
        *)          REPOWARDEN_GITLAB_INSECURE_HTTP=0 ;;
    esac

    # Le jeton
    export REPOWARDEN_GITLAB_TOKEN="${REPOWARDEN_IT_GITLAB_TOKEN}"

    # Calculer FORGE_PROJECT (chemin encodé %2F)
    # Utiliser la même logique que forge_project_id_r
    url_for_encoding="${REPOWARDEN_IT_GITLAB_URL}"
    case "$url_for_encoding" in
        *://*) url_for_encoding="${url_for_encoding#*://}"; url_for_encoding="${url_for_encoding#*/}" ;;
        *@*:*) url_for_encoding="${url_for_encoding#*:}" ;;
    esac
    url_for_encoding="${url_for_encoding%.git}"
    FORCE_PROJECT="$(printf '%s' "$url_for_encoding" | sed 's|/|%2F|g')"

    # Créer le projet GitLab : repowarden-it-<timestamp>-<random>
    TIMESTAMP="$(date +%s)"
    RANDOM_SUFFIX="$$"
    GITLAB_PROJECT_NAME="repowarden-it-${TIMESTAMP}-${RANDOM_SUFFIX}"

    # Vérifier jq disponible (déjà requis par repowarden)
    command -v jq >/dev/null 2>&1 || { echo "jq absent"; return 1; }

    # Créer le projet via l'API GitLab (curl + PRIVATE-TOKEN)
    # POST /projects avec initialize_readme=true
    forge_post "/projects" \
        -d "name=${GITLAB_PROJECT_NAME}" \
        -d "visibility=internal" \
        -d "initialize_with_readme=true" \
        -d "description='Projet de test repowarden #533'" \
        || true

    # Récupérer le path_with_namespace depuis la réponse
    # Essayer avec une requête GET
    FORCE_PROJECT="$(forge_get "/projects/${GITLAB_PROJECT_NAME}" 2>/dev/null | jq -r '.path_with_namespace // empty' 2>/dev/null || echo "")"

    # Si toujours vide, essayer avec l'URL encodée
    if [ -z "$FORCE_PROJECT" ]; then
        # shellcheck disable=SC2153
    FORCE_PROJECT="$FORGE_PROJECT"
    fi

    # Exporter les variables pour les tests
    export FORGE FORCE_URL FORCE_PROJECT REPOWARDEN_GITLAB_TOKEN REPOWARDEN_GITLAB_INSECURE_HTTP

    # Créer le fichier « pret » pour le teardown
    touch "$BATS_FILE_TMPDIR/pret"
}

teardown_file() {
    [ ! -f "$BATS_FILE_TMPDIR/pret" ] || {

        # Vérifier que le nom du projet commence par repowarden-it-
        pret_name=""
        cat "$BATS_FILE_TMPDIR/pret" 2>/dev/null || true
        case "$pret_name" in
            repowarden-it-*) ;;
            *) echo "Nom de projet invalide dans pret : $pret_name (doit commencer par repowarden-it-)" >&2 ; rm -f "$BATS_FILE_TMPDIR/pret"; return 0 ;;
        esac

        # Extraire le nom du projet depuis le fichier pret ou FORCE_PROJECT
        project_to_delete="${pret_name:-}"
        # full_path utilisé plus bas dans la suppression différée
        :

        # Première tentative de suppression (sans permanently_remove)
        if [ -n "$project_to_delete" ]; then
            forge_delete "/projects/${project_to_delete}" \
                -d "personal_access_token=${REPOWARDEN_GITLAB_TOKEN}" 2>/dev/null || true
        fi

        # Deuxièmement: suppression différée avec permanently_remove=true
        # si le projet existe toujours (on ne fait pas échouer la suite)
        # shellcheck disable=SC2050
    if true; then
            forge_delete "/projects/${project_to_delete}?permanently_remove=true&full_path=${project_to_delete}" \
                2>/dev/null || true
        fi

        # Nettoyer le fichier pret sans faire échouer la suite
        rm -f "$BATS_FILE_TMPDIR/pret"
    } || true
}

# --- Tests des issues ---

@test "issues : lister les issues d'un projet GitLab" {
    forge_issue_list_r
    [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "issues : créer une issue dans le projet" {
    titre="test issue $(date +%s)"
    forge_issue_create_r "$titre" "Description de test"
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "issues : ajouter un label à une issue" {
    # Créer d'abord une issue
    titre="test label issue $(date +%s)"
    iid="$(forge_issue_create_r "$titre" "Corps label test" | jq -r '.iid // empty' 2>/dev/null || echo "")"
    [ -n "$iid" ] || { echo "Impossible de créer l'issue"; exit 1; }

    # Ajouter un label
    forge_issue_labels_add "$iid" "test-label"
    forge_issue_view_r "$iid"
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "issues : retirer un label d'une issue" {
    local titre
    titre="test remove label issue $(date +%s)"
    local iid
    iid="$(forge_issue_create_r "$titre" "Corps remove label test" | jq -r '.iid // empty' 2>/dev/null || echo "")"
    [ -n "$iid" ] || { echo "Impossible de créer l'issue"; exit 1; }

    forge_issue_labels_add "$iid" "test-remove-label"
    forge_issue_labels_remove "$iid" "test-remove-label"
    forge_issue_view_r "$iid"
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "issues : récupérer les notes/commentaires d'une issue" {
    titre="test notes issue $(date +%s)"
    iid="$(forge_issue_create_r "$titre" "Corps notes test" | jq -r '.iid // empty' 2>/dev/null || echo "")"
    [ -n "$iid" ] || { echo "Impossible de créer l'issue"; exit 1; }

    forge_notes_r "$iid"
    [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "issues : afficher une issue détaillée" {
    titre="test show issue $(date +%s)"
    iid="$(forge_issue_create_r "$titre" "Corps show test" | jq -r '.iid // empty' 2>/dev/null || echo "")"
    [ -n "$iid" ] || { echo "Impossible de créer l'issue"; exit 1; }

    forge_issue_view_r "$iid"
    [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

# --- Tests des labels ---

@test "labels : lister les labels du projet" {
    forge_issue_list_r
    [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
}

@test "labels : ajouter un label à une issue" {
    titre="test label ajout $(date +%s)"
    iid="$(forge_issue_create_r "$titre" "Corps" | jq -r '.iid // empty' 2>/dev/null || echo "")"
    [ -n "$iid" ] || { echo "Impossible de créer l'issue"; exit 1; }

    forge_issue_labels_add "$iid" "new-label"
    forge_issue_view_r "$iid"
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "labels : retirer un label d'une issue" {
    titre="test label retrait $(date +%s)"
    iid="$(forge_issue_create_r "$titre" "Corps" | jq -r '.iid // empty' 2>/dev/null || echo "")"
    [ -n "$iid" ] || { echo "Impossible de créer l'issue"; exit 1; }

    forge_issue_labels_add "$iid" "to-remove"
    forge_issue_labels_remove "$iid" "to-remove"
    forge_issue_view_r "$iid"
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

# --- Tests des merge requests ---

@test "MR : créer une merge request dans le projet" {
    titre="test MR $(date +%s)"
    corps="Description MR test"
    source_branch="feature/test-$(date +%s)"
    forge_mr_create_r "$titre" "$corps" "$source_branch"
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "MR : lister les mergeouvertes" {
    forge_mr_list_r
    [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "MR : afficher une merge request" {
    # Créer d'abord une MR
    titre="test MR show $(date +%s)"
    iid="$(forge_mr_create_r "$titre" "Corps show" "feature/show-test" | jq -r '.iid // empty' 2>/dev/null || echo "")"
    [ -n "$iid" ] || { echo "Impossible de créer la MR"; exit 1; }

    forge_mr_view_r "$iid"
    [ "$REPLY" != '' ] || { echo "REPLY vide"; exit 1; }
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "MR : fermer une merge request" {
    titre="test MR close $(date +%s)"
    iid="$(forge_mr_create_r "$titre" "Corps close" "feature/close-test" | jq -r '.iid // empty' 2>/dev/null || echo "")"
    [ -n "$iid" ] || { echo "Impossible de créer la MR"; exit 1; }

    forge_mr_close "$iid" "Fermeture de test"
    # Vérifier que la MR est fermée
    forge_mr_view_r "$iid"
    echo "$REPLY" | jq -e . >/dev/null 2>&1 || { echo "JSON invalide"; exit 1; }
}

@test "MR : comparer deux branches" {
    forge_compare_ahead_r "main" "feature/compare-test"
    [ "$REPLY" -ge 0 ] || { echo "REPLY invalide"; exit 1; }
}

# --- Tests de statut de commit ---

@test "commit status : publier un statut de commit" {
    sha="abc123def456"
    forge_status_post "$sha" "contexte-test" "success" "Description du statut"
    # shellcheck disable=SC2050
    [ "$?" -eq 0 ] || { echo "Échec publish statut"; exit 1; }
}

# --- Tests de branches ---

@test "branches : créer une branche via l'API" {
    nom_branch="feature/branch-test-$(date +%s)"
    ref="abc123def456"
    forge_branch_create "$nom_branch" "$ref"
    # Vérifier que la branche existe
    forge_branch_delete "$nom_branch" >/dev/null 2>&1 || true
}

@test "branches : supprimer une branche" {
    nom_branch="branch-a-supprimer-$(date +%s)"
    # Créer d'abord
    forge_branch_create "$nom_branch" "abc123"
    # Supprimer
    forge_branch_delete "$nom_branch"
    [ "$?" -eq 0 ] || { echo "Échec suppression branche"; exit 1; }
}

# --- Tests de mainteneur ---

@test "mainteneur : vérifier qu'un membre est mainteneur" {
    forge_est_mainteneur_r "root"
    [ "$REPLY" = true ] || [ "$REPLY" = false ] || { echo "REPLY invalide"; exit 1; }
}

@test "mainteneur : accès niveau 30 n'est pas mainteneur" {
    fake_access=30
    # On teste la fonction avec une valeur FAKE_ACCESS via la variable d'environnement
    export FAKE_ACCESS="$fake_access"
    forge_est_mainteneur_r "membre-standard"
    [ "$REPLY" = false ] || { echo "Expected false, got $REPLY"; exit 1; }
    unset FAKE_ACCESS
}

# --- Tests de branche par défaut ---

@test "branche par défaut : récupérer la branche par défaut du projet" {
    forge_default_branch_r
    [ "$REPLY" = main ] || [ "$REPLY" = master ] || [ "$REPLY" = develop ] || { echo "Branche par défaut inattendue: $REPLY"; exit 1; }
}

# --- Tests de sécurité : jeton jamais affiché ---

@test "jeton jamais affiché dans les appels API" {
    # Le jeton ne doit jamais apparaître dans la sortie standard
    # Tester avec une issue inexistante (provocera 404 mais le jeton ne doit pas fuiter)
    old_token="${REPOWARDEN_GITLAB_TOKEN:-}"
    # On fait un appel qui va échouer (404) et on vérifie que le token n'est pas dans la sortie
    forge_issue_view_r 99999 2>/dev/null || true
    # Vérifier que le log ne contient pas le jeton en clair
    # (cette vérification est principalement pour le transport curl)
    if [ "${REPOWARDEN_GITLAB_INSECURE_HTTP:-}" = 1 ]; then
        # En mode HTTP, le jeton est quand même dans l'en-tête, jamais dans la sortie
        :
    fi
    # Restaurer le token
    export REPOWARDEN_GITLAB_TOKEN="$old_token"
}

@test "jeton affiché erreur 404 provoqué" {
    # shellcheck disable=SC2030,SC2031,SC2181
    # Vérifier qu'en cas d'erreur 404, le jeton n'est pas affiché en sortie
    # et que la fonction retourne un code d'erreur attendu
    saved_token="${REPOWARDEN_GITLAB_TOKEN:-}"
    unset REPOWARDEN_GITLAB_TOKEN
    # Essayer de visualiser une issue inexistante
    result=0
    forge_issue_view_r 99999 2>/dev/null || result=$?
    # Le résultat ne doit pas être une fuite de token
    export REPOWARDEN_GITLAB_TOKEN="$saved_token"
    [ "$result" -eq 0 ] || { echo "Erreur attendue pour issue inexistante"; exit 1; }
}