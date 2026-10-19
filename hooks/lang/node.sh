#!/usr/bin/env bash
# JavaScript / TypeScript (React, Next.js, Vue, Angular, Nest…) : prettier, <pm> test
# Extensions de code (analyse du code mort) : les autres (md, yml, json…) ne
# sont rattachées à node que pour le formatage
# shellcheck disable=SC2034 # lu par deadcode.sh (${PLUGIN}_CODE_EXT)
NODE_CODE_EXT='\.(js|jsx|ts|tsx|mjs|cjs|mts|cts|vue|svelte|astro)$'
register node "package.json" '\.(js|jsx|ts|tsx|mjs|cjs|mts|cts|vue|svelte|astro|json|jsonc|css|scss|less|html|md|mdx|ya?ml|graphql)$' standalone

# Gestionnaire de paquets d'après le lockfile (y compris à la racine d'un monorepo)
node_pm() {
    if find_up pnpm-lock.yaml >/dev/null; then echo pnpm
    elif find_up yarn.lock >/dev/null; then echo yarn
    elif find_up bun.lockb >/dev/null || find_up bun.lock >/dev/null; then echo bun
    else echo npm
    fi
}

node_format() {
    local prettier
    prettier="$(find_up node_modules/.bin/prettier || command -v prettier || true)"
    [ -n "$prettier" ] || { tool_missing "Node : prettier introuvable (npm i -D prettier), formatage ignoré."; return 0; }
    step_t lang.node.1
    "$prettier" --write --ignore-unknown --log-level warn "$@"
}

node_test() {
    has node || { warn "Node : node absent, tests ignorés."; return 0; }
    # Ignore le script "test" par défaut généré par npm init
    if ! node -e 'const t=(require("./package.json").scripts||{}).test; process.exit(t && !/no test specified/.test(t) ? 0 : 1)'; then
        info_t lang.node.2
        return 0
    fi
    local pm; pm="$(node_pm)"
    has "$pm" || { warn "Node : $pm absent, tests ignorés."; return 0; }
    step_t lang.node.3 "$pm"
    case "$pm" in
        bun) bun run test ;;
        npm) npm test --silent ;;
        *) "$pm" test ;;
    esac
}

# Code mort : TypeScript (variables, paramètres, imports inutilisés, code
# inaccessible : prouvé) ; knip s'il est installé dans le projet (fichiers,
# exports, dépendances non référencés : candidats)
node_deadcode() {
    local ran="" a_tsc=0 a_knip=0
    if [ -f tsconfig.json ] && [ -x node_modules/.bin/tsc ]; then
        ran=1
        a_tsc=1
        node_modules/.bin/tsc --noEmit -p . --noUnusedLocals --noUnusedParameters \
            --allowUnreachableCode false --pretty false 2>/dev/null |
            sed -nE 's/^(.+)\(([0-9]+),[0-9]+\): error (TS6133|TS6138|TS6192|TS6196|TS6198|TS7027): (.*)$/prouve\t\1\t\2\t\4/p'
    fi
    if [ -x node_modules/.bin/knip ] && has node; then
        ran=1
        a_knip=1
        _tr dc.knip_file
        local m_file="$_T"
        _tr dc.knip_export
        local m_export="$_T"
        _tr dc.knip_dep
        local m_dep="$_T"
        node_modules/.bin/knip --reporter json --no-progress 2>/dev/null |
            M_FILE="$m_file" M_EXPORT="$m_export" M_DEP="$m_dep" node -e '
                let r; try { r = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch { process.exit(0); }
                const out = (f, l, m) => console.log(["candidat", f, l, m].join("\t"));
                for (const f of r.files || []) out(f, 0, process.env.M_FILE);
                for (const i of r.issues || []) {
                    for (const k of ["exports", "types", "nsExports", "nsTypes"])
                        for (const e of i[k] || []) out(i.file, e.line || 0, process.env.M_EXPORT + " " + e.name);
                    for (const k of ["dependencies", "devDependencies"])
                        for (const d of i[k] || []) out(i.file, 0, process.env.M_DEP + " " + d.name);
                }'
    fi
    if [ -z "$ran" ]; then
        deadcode_tool_missing "JavaScript / TypeScript" "typescript / knip"
    elif [ "$a_tsc" = 0 ]; then
        # knip seul : les variables, paramètres et imports inutilisés restent à analyser
        _tr dc.scope.locals
        deadcode_partial "JavaScript / TypeScript" typescript "$_T" "npm i -D typescript"
    elif [ "$a_knip" = 0 ]; then
        # tsc seul : les fichiers, exports et dépendances non référencés restent à analyser
        _tr dc.scope.files
        deadcode_partial "JavaScript / TypeScript" knip "$_T" "npm i -D knip"
    fi
}
