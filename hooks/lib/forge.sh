#!/usr/bin/env bash
# Plateforme de gestion de version : github, gitlab, bitbucket, gitea (Gitea,
# Forgejo, Codeberg) ou other. Réglage forge (git config ou .repowarden.conf),
# sinon variables de la CI, sinon adresse du remote origin (domaine interne
# reconnu s'il contient gitlab, gitea…). Résultat mémorisé : FORGE.
# Vocabulaire : FORGE_PR (PR / MR), FORGE_REFS (exemple de références).
# shellcheck disable=SC2034 # variables utilisées par les scripts qui sourcent ce fichier

forge_init() {
    local forge="" url
    if declare -F cfg_r >/dev/null; then
        cfg_r forge ""
        forge="$REPLY"
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
}

forge_init

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
