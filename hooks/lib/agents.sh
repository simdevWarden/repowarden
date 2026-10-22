#!/usr/bin/env bash
# Agents IA du poste et garde-fou repowarden (repowarden statut, install.sh).
# Compatible bash 3.2.

# Vrai si Claude Code ou opencode est sur ce poste (commande, ou dossier de
# configuration) sans garde-fou branché, ni dans le dépôt $1 (racine, vide hors
# dépôt) ni pour l'utilisateur : ses actions ne seraient vues qu'au commit
agents_sans_garde() {
    local claude_dir opencode_dir f fichiers=()
    claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    opencode_dir="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
    command -v claude >/dev/null 2>&1 || command -v opencode >/dev/null 2>&1 ||
        [ -d "$claude_dir" ] || [ -d "$opencode_dir" ] || return 1
    [ -z "${1:-}" ] || fichiers=("$1/.claude/settings.json" "$1/.opencode/plugins/repowarden-garde.js")
    fichiers+=("$claude_dir/settings.json" "$opencode_dir/plugins/repowarden-garde.js")
    for f in "${fichiers[@]}"; do
        ! grep -qs "repowarden garde" "$f" || return 1
    done
    return 0
}
