#!/usr/bin/env bash
# Agents IA du poste et garde-fou repowarden (repowarden agents, statut,
# install.sh). Compatible bash 3.2.

# Forme actuelle du garde-fou : un garde-fou posé par repowarden qui en diffère
# date d'une version antérieure et est mis à jour (#470)
AGENTS_MODELE_OPENCODE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../agents" && pwd -P)/repowarden-garde.js"
AGENTS_COMMANDE_CLAUDE="repowarden garde --format claude"
AGENTS_MATCHER_CLAUDE="Edit|Write|MultiEdit|NotebookEdit|Bash"

# Dossiers de configuration de l'utilisateur, là où chaque outil les lit
# (CLAUDE_CONFIG_DIR ; OPENCODE_CONFIG_DIR, sinon XDG_CONFIG_HOME)
agents_dossiers_globaux() {
    AGENTS_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    AGENTS_OPENCODE_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
}

# Vrai si le plugin opencode $1 a été posé par repowarden (en-tête du modèle,
# ancien plugin autonome compris) : lui seul peut être remplacé sans perte
agents_plugin_repowarden() {
    local ligne=""
    [ -f "$1" ] || return 1
    IFS= read -r ligne <"$1" || true
    case "$ligne" in "// Garde-fou repowarden pour opencode"*) return 0 ;; esac
    return 1
}

# Vrai si le plugin $1 vient de repowarden mais diffère du modèle actuel :
# posé par une version antérieure, il n'a pas suivi les mises à jour
agents_plugin_perime() {
    agents_plugin_repowarden "$1" && ! cmp -s "$1" "$AGENTS_MODELE_OPENCODE"
}

# Vrai si le settings.json $1 a un hook « repowarden garde… » d'une autre forme
# que l'actuelle (commande ou matcher) : posé par une version antérieure
agents_claude_perime() {
    [ -f "$1" ] && command -v jq >/dev/null 2>&1 || return 1
    jq -e --arg c "$AGENTS_COMMANDE_CLAUDE" --arg m "$AGENTS_MATCHER_CLAUDE" '
        [.hooks.PreToolUse[]? | . as $e | .hooks[]?
            | select((.command // "") | startswith("repowarden garde"))
            | select(.command != $c or $e.matcher != $m)] | length > 0' "$1" >/dev/null 2>&1
}

# Garde-fous périmés du dépôt $1 (vide hors dépôt) puis de l'utilisateur, une
# ligne « portée agent fichier » chacun : statut les signale, install les met à jour
agents_perimes() {
    agents_dossiers_globaux
    if [ -n "${1:-}" ]; then
        ! agents_claude_perime "$1/.claude/settings.json" || echo "projet claude $1/.claude/settings.json"
        ! agents_plugin_perime "$1/.opencode/plugins/repowarden-garde.js" ||
            echo "projet opencode $1/.opencode/plugins/repowarden-garde.js"
    fi
    ! agents_claude_perime "$AGENTS_CLAUDE_DIR/settings.json" || echo "global claude $AGENTS_CLAUDE_DIR/settings.json"
    ! agents_plugin_perime "$AGENTS_OPENCODE_DIR/plugins/repowarden-garde.js" ||
        echo "global opencode $AGENTS_OPENCODE_DIR/plugins/repowarden-garde.js"
    return 0
}

# Vrai si Claude Code ou opencode est sur ce poste (commande, ou dossier de
# configuration) sans garde-fou branché, ni dans le dépôt $1 (racine, vide hors
# dépôt) ni pour l'utilisateur : ses actions ne seraient vues qu'au commit
agents_sans_garde() {
    local f fichiers=()
    agents_dossiers_globaux
    command -v claude >/dev/null 2>&1 || command -v opencode >/dev/null 2>&1 ||
        [ -d "$AGENTS_CLAUDE_DIR" ] || [ -d "$AGENTS_OPENCODE_DIR" ] || return 1
    [ -z "${1:-}" ] || fichiers=("$1/.claude/settings.json" "$1/.opencode/plugins/repowarden-garde.js")
    fichiers+=("$AGENTS_CLAUDE_DIR/settings.json" "$AGENTS_OPENCODE_DIR/plugins/repowarden-garde.js")
    # Plugin repowarden d'une version antérieure : branché (périmé, pas absent)
    for f in "${fichiers[@]}"; do
        ! grep -qs "repowarden garde" "$f" || return 1
        ! agents_plugin_repowarden "$f" || return 1
    done
    return 0
}
