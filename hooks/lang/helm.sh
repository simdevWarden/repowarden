#!/usr/bin/env bash
# Helm : helm lint + rendu (helm template) + schémas (kubeconform) + helm unittest.
# Les fichiers d'un chart sont des templates Go : JAMAIS de formatage YAML
# (prettier les casserait) — d'où l'absence de helm_format.
register helm "Chart.yaml" '\.(ya?ml|tpl|txt)$'

# URL des dépôts HTTP(S) des dependencies: de Chart.yaml, une par ligne, sans
# doublon. awk suffit (pas de parseur YAML) ; oci://, file:// et @alias sont exclus.
helm_http_repos() {
    awk '
        /^dependencies:/ { dep = 1; next }
        /^[A-Za-z]/ { dep = 0 }
        dep && /repository:/ {
            sub(/.*repository:[ \t]*/, "")
            gsub(/["\047\r ]/, "")
            if ($0 ~ /^https?:\/\//) print
        }' Chart.yaml | sort -u
}

# Ajoute chaque dépôt HTTP(S) dans la configuration temporaire $1 : helm
# dependency build ne trouve un dépôt que s'il est ajouté. Refus si injoignable.
helm_repos_prepare() {
    local dir="$1" url name base i noms=""
    mkdir -p "$dir/cache"
    while IFS= read -r url; do
        # Nom dérivé de l'URL, unique : deux URL ne partagent jamais un nom
        name="$(printf '%s' "${url#*://}" | tr -c 'A-Za-z0-9' '-' | tr '[:upper:]' '[:lower:]' | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')"
        base="$name"
        i=2
        while :; do
            case " $noms " in *" $name "*) name="$base-$i"; i=$((i + 1)) ;; *) break ;; esac
        done
        noms="$noms $name"
        if ! HELM_REPOSITORY_CONFIG="$dir/repositories.yaml" HELM_REPOSITORY_CACHE="$dir/cache" \
            helm repo add "$name" "$url" --force-update >/dev/null; then
            err_t lang.helm.5 "$url"
            return 1
        fi
    done < <(helm_http_repos)
}

# helm dependency build. Avec un dépôt HTTP(S), il tourne sur une configuration
# temporaire supprimée ensuite : la configuration helm de l'utilisateur reste intacte.
helm_depends() {
    local dir rc=0
    if [ -z "$(helm_http_repos)" ]; then
        helm dependency build >/dev/null
        return
    fi
    dir="$(mktemp -d)" || return 1
    if helm_repos_prepare "$dir"; then
        HELM_REPOSITORY_CONFIG="$dir/repositories.yaml" HELM_REPOSITORY_CACHE="$dir/cache" \
            helm dependency build >/dev/null || rc=1
    else
        rc=1
    fi
    rm -rf "$dir"
    return "$rc"
}

helm_test() {
    has helm || { warn "Helm : helm absent, vérification ignorée."; return 0; }
    local rendered rc=0
    if grep -qs '^dependencies:' Chart.yaml; then
        step_t lang.helm.1
        helm_depends || return 1
    fi
    step_t lang.helm.2
    helm lint --quiet . || return 1
    rendered="$(mktemp)"
    helm template repowarden . >"$rendered" || { rm -f "$rendered"; return 1; }
    if has kubeconform; then
        step_t lang.helm.3
        kubeconform -strict -summary -ignore-missing-schemas -cache "$(kubeconform_cache)" <"$rendered" || rc=1
    fi
    rm -f "$rendered"
    [ "$rc" = 0 ] || return 1
    if [ -d tests ] && grep -q '^unittest' <<<"$(helm plugin list 2>/dev/null)"; then
        step_t lang.helm.4
        helm unittest .
    fi
}
