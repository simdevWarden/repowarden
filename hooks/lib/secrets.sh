#!/usr/bin/env bash
# Secrets détectés par gitleaks (pre-commit) : où ils sont et que faire, sans
# jamais afficher la valeur. Chargé après common.sh. Compatible bash 3.2.

# Lit le rapport JSON de gitleaks $1 (un objet par fuite, un champ par ligne,
# format de --report-format json) : seuls File, StartLine, RuleID et
# Fingerprint sont lus, jamais Secret ni Match. Affiche « fichier:ligne
# (règle) » par fuite, puis la marche à suivre et les empreintes à mettre dans
# .gitleaksignore en cas de faux positif.
secrets_report() {
    local fuites empreintes f l r e
    # awk : déséchappe ce que le JSON de Go échappe dans un chemin (\" \\ et
    # les codes \u0026, \u003c, \u003e de & < >) ; sortie « fichier<TAB>ligne<TAB>règle<TAB>empreinte »
    fuites="$(awk '
        function valeur(s) {
            sub(/^[^:]*: */, "", s); sub(/,$/, "", s)
            if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2)
            gsub(/\\u0026/, "\\&", s); gsub(/\\u003c/, "<", s); gsub(/\\u003e/, ">", s)
            gsub(/\\"/, "\"", s); gsub(/\\\\/, "\\", s)
            return s
        }
        /^ *\{/ { f = ""; l = ""; r = ""; e = "" }
        /^ *"File": / { f = valeur($0) }
        /^ *"StartLine": / { l = valeur($0) }
        /^ *"RuleID": / { r = valeur($0) }
        /^ *"Fingerprint": / { e = valeur($0) }
        /^ *\}/ { printf "%s\t%s\t%s\t%s\n", f, l, r, e }
    ' "$1" 2>/dev/null || true)"
    if [ -z "$fuites" ]; then
        # Rapport illisible (format changé) : le dire, sans rien deviner
        echo_t hook.secrets.unreadable
    else
        empreintes=""
        while IFS="$(printf '\t')" read -r f l r e; do
            _tr hook.secrets.where "$f" "$l" "$r"
            echo "$_T"
            [ -z "$e" ] || empreintes="$empreintes    $e"$'\n'
        done <<<"$fuites"
    fi
    echo
    echo_t hook.secrets.todo
    echo_t hook.secrets.todo_1
    echo_t hook.secrets.todo_2
    echo_t hook.secrets.todo_3
    if [ -n "${empreintes:-}" ]; then
        echo_t hook.secrets.todo_4
        printf '%s' "$empreintes"
    fi
}
