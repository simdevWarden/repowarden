#!/usr/bin/env bash
# Alias de compatibilité : noms français → noms anglais canoniques (#565).
# Tout mot inconnu est rendu tel quel (y compris la chaîne vide).
# Compatible bash 3.2 (macOS) : pas de tableaux associatifs.

# command_canonical <mot> : nom anglais canonique d'une commande de premier niveau
command_canonical() {
    case "${1:-}" in
        statut) echo status ;;
        code-mort) echo dead-code ;;
        carte) echo map ;;
        proteger) echo protect ;;
        migrer) echo migrate ;;
        npm-publication) echo npm-publish ;;
        garde) echo guard ;;
        *) echo "${1:-}" ;;
    esac
}

# subcommand_canonical <commande> <mot> : sous-commande canonique d'une commande
subcommand_canonical() {
    case "${1:-}" in
        ticket)
            case "${2:-}" in
                nouveau) echo new ;;
                *) echo "${2:-}" ;;
            esac
            ;;
        agents)
            case "${2:-}" in
                retirer) echo remove ;;
                *) echo "${2:-}" ;;
            esac
            ;;
        bot)
            case "${2:-}" in
                rapport) echo report ;;
                *) echo "${2:-}" ;;
            esac
            ;;
        *)
            echo "${2:-}"
            ;;
    esac
}

# option_canonical <mot> : option canonique (anglaise), indépendante de la commande
option_canonical() {
    case "${1:-}" in
        --sans-bots) echo --no-bots ;;
        --projet) echo --project ;;
        --oui) echo --yes ;;
        *) echo "${1:-}" ;;
    esac
}
