#!/usr/bin/env bats
# Paquet npm : commande repowarden (installation sur la machine), contenu publié

load helpers

PKG="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"

setup() {
    setup_repo
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
    touch "$GIT_CONFIG_GLOBAL"
}

@test "npm : version lue dans le tag (clone), package.json ecrit seulement a la publication" {
    run "$PKG/bin/repowarden" --version
    [ "$status" -eq 0 ]
    # Version portée par un tag du dépôt (choix exact : tests « version : » d'install.bats)
    if [ -n "$(git -C "$PKG" tag --list 'v[0-9]*')" ]; then
        [ -n "$(git -C "$PKG" tag --list "v$output")" ]
    else
        [ "$output" = 0.0.0-dev ]
    fi
    grep -q '"version": "0.0.0-dev"' "$PKG/package.json"
}

@test "npm : appelee par un lien symbolique (npm install -g), installe les vrais hooks" {
    mkdir -p "$BATS_TEST_TMPDIR/prefix/bin"
    ln -s "$PKG/bin/repowarden" "$BATS_TEST_TMPDIR/prefix/bin/repowarden" 2>/dev/null || true
    # Git Bash (Windows) copie au lieu de lier ; npm y crée des scripts .cmd
    [ -L "$BATS_TEST_TMPDIR/prefix/bin/repowarden" ] || skip "liens symboliques indisponibles"
    git config --unset core.hooksPath
    run "$BATS_TEST_TMPDIR/prefix/bin/repowarden" install --global --lang fr
    [ "$status" -eq 0 ]
    [ "$(git config --global --get core.hooksPath)" = "$PKG/hooks" ]
    [[ "$(git config --global --get alias.cc)" == *"$PKG/bin/commit"* ]] || false
    run "$BATS_TEST_TMPDIR/prefix/bin/repowarden" uninstall --global
    [ "$status" -eq 0 ]
    [ -z "$(git config --global --get core.hooksPath || true)" ]
}

@test "npm : npx refuse une installation globale (dossier temporaire)" {
    npx="$BATS_TEST_TMPDIR/_npx/abc/node_modules/repowarden"
    mkdir -p "$npx"
    cp -R "$PKG/bin" "$PKG/hooks" "$PKG/install.sh" "$PKG/package.json" "$npx/"
    run "$npx/bin/repowarden" install --global
    [ "$status" -ne 0 ]
    [[ "$output" == *"npm install -g"* ]] || false
    [ -z "$(git config --global --get core.hooksPath || true)" ]
}

@test "npm : commande inconnue refusee, aide affichee" {
    run "$PKG/bin/repowarden" inconnue
    [ "$status" -ne 0 ]
    [[ "$output" == *"repowarden install"* ]] || false
}

@test "npm : le paquet contient les hooks, ni tests, ni CI, ni modeles" {
    require npm
    run bash -c "cd '$PKG' && npm pack --dry-run --json 2>/dev/null"
    [ "$status" -eq 0 ]
    for f in bin/repowarden bin/commit install.sh hooks/lib/common.sh hooks/pre-commit; do
        [[ "$output" == *"\"$f\""* ]] || false
    done
    # Rien d'inutile sur une machine : tests, scripts de CI (accès réseau), modèles ;
    # sauf le suivi des tickets, appelé par « repowarden tickets init »
    for f in ci/tickets.sh ci/tickets/commun.sh ci/tickets/adopter.sh; do
        [[ "$output" == *"\"$f\""* ]] || false
    done
    for d in test/ ci/check.sh ci/version.sh templates/; do
        [[ "$output" != *"\"$d"* ]] || false
    done
}

@test "npm : desinstallation complete -> npm uninstall -g propose, pas rm -rf" {
    pkg="$BATS_TEST_TMPDIR/prefix/lib/node_modules/repowarden"
    mkdir -p "$pkg"
    cp -R "$PKG/bin" "$PKG/hooks" "$PKG/install.sh" "$PKG/package.json" "$pkg/"
    "$pkg/bin/repowarden" install --global --lang fr >/dev/null
    run "$pkg/bin/repowarden" uninstall --global --purge
    [ "$status" -eq 0 ]
    [[ "$output" == *"npm uninstall -g repowarden"* ]] || false
    [[ "$output" != *"rm -rf"* ]] || false
}

@test "statut : sans argument -> etat et etape suivante, puis tout est pret apres installation" {
    git config --unset core.hooksPath
    run "$PKG/bin/repowarden"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hooks git non activés"* ]] || false
    [[ "$output" == *"Étape suivante : repowarden install --global"* ]] || false
    "$PKG/bin/repowarden" install --global --lang fr >/dev/null
    garde_branche
    run "$PKG/bin/repowarden" statut
    [[ "$output" == *"Hooks git actifs pour tous les dépôts"* ]] || false
    [[ "$output" == *"Assistant de commit : git cc"* ]] || false
    [[ "$output" == *"Tout est prêt"* ]] || false
}

@test "statut : lefthook.yml present -> signale comme non pris en charge" {
    printf 'pre-commit: {}\n' >lefthook.yml
    run "$PKG/bin/repowarden" statut
    [ "$status" -eq 0 ]
    [[ "$output" == *"lefthook.yml présent : lefthook n'est plus pris en charge"* ]] || false
    [[ "$output" != *"absents : "*"lefthook"* ]] || false
}

@test "statut : .pre-commit-config.yaml sans ses hooks -> marche a suivre, puis plus rien une fois installes" {
    git config --unset core.hooksPath
    "$PKG/bin/repowarden" install --global --lang fr >/dev/null
    garde_branche
    printf 'repos: []\n' >.pre-commit-config.yaml
    marche='GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0= pre-commit install'
    run "$PKG/bin/repowarden" statut
    [ "$status" -eq 0 ]
    [[ "$output" == *".pre-commit-config.yaml présent : ses hooks ne sont pas lancés"* ]] || false
    [[ "$output" == *"Étape suivante : $marche"* ]] || false
    REPOWARDEN_LANG=en run "$PKG/bin/repowarden" statut
    [[ "$output" == *".pre-commit-config.yaml present: its hooks are not run"* ]] || false
    # La marche masque core.hooksPath au « git config core.hooksPath » que lit pre-commit
    run env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0= git config core.hooksPath
    [ -z "$output" ]
    [ -n "$(git config core.hooksPath)" ]
    # Hook écrit par « pre-commit install » dans .git/hooks : repowarden le lance
    printf '#!/usr/bin/env bash\n# File generated by pre-commit: https://pre-commit.com\nexit 0\n' >.git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    run "$PKG/bin/repowarden" statut
    [[ "$output" != *".pre-commit-config.yaml présent"* ]] || false
    [[ "$output" == *"Tout est prêt"* ]] || false
}

@test "statut : installation locale (sans --global) -> hooks et git cc reconnus" {
    git config --unset core.hooksPath
    "$PKG/install.sh" --lang fr >/dev/null
    garde_branche
    run "$PKG/bin/repowarden" statut
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hooks git actifs dans ce dépôt seulement"* ]] || false
    [[ "$output" == *"Assistant de commit : git cc"* ]] || false
    [[ "$output" != *"non activés"* ]] || false
    [[ "$output" == *"Tout est prêt"* ]] || false
}

@test "statut : agent IA sans garde-fou -> avertissement, repowarden agents init en etape suivante" {
    agent_sans_garde
    "$PKG/bin/repowarden" install --global --lang fr >/dev/null
    run "$PKG/bin/repowarden" statut
    [ "$status" -eq 0 ]
    [[ "$output" == *"Agent IA sans garde-fou"* ]] || false
    [[ "$output" == *"Étape suivante : repowarden agents init"* ]] || false
    [[ "$output" != *"Tout est prêt"* ]] || false
    # Garde-fou de l'utilisateur, puis celui du dépôt : plus rien à signaler
    printf '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit|Bash","hooks":[{"type":"command","command":"repowarden garde --format claude"}]}]}}\n' >"$HOME/.claude/settings.json"
    run "$PKG/bin/repowarden" statut
    [[ "$output" != *"sans garde-fou"* ]] || false
    [[ "$output" == *"Tout est prêt"* ]] || false
    rm "$HOME/.claude/settings.json"
    mkdir -p .opencode/plugins
    cp "$PKG/hooks/agents/repowarden-garde.js" "$PKG/hooks/agents/repowarden-garde-v2.js" .opencode/plugins/
    run "$PKG/bin/repowarden" statut
    [[ "$output" != *"sans garde-fou"* ]] || false
    # Hors dépôt : branchement pour l'utilisateur
    cd "$BATS_TEST_TMPDIR"
    REPOWARDEN_LANG=en run "$PKG/bin/repowarden" statut
    [[ "$output" == *"AI agent without the guard"* ]] || false
    [[ "$output" == *"repowarden agents init --global"* ]] || false
}

@test "statut : garde-fou perime (version anterieure de repowarden) -> signale, agents init en etape suivante" {
    require jq
    agent_sans_garde
    "$PKG/bin/repowarden" install --global --lang fr >/dev/null
    # Ancien plugin autonome pour l'utilisateur : branché, mais périmé
    mkdir -p "$HOME/.config/opencode/plugins"
    cp "$BATS_TEST_DIRNAME/fixtures/agents/ancien-plugin-opencode-autonome.js" "$HOME/.config/opencode/plugins/repowarden-garde.js"
    run "$PKG/bin/repowarden" statut
    [ "$status" -eq 0 ]
    [[ "$output" != *"sans garde-fou"* ]] || false
    [[ "$output" == *"Garde-fou repowarden périmé"*"repowarden-garde.js"* ]] || false
    [[ "$output" == *"Étape suivante : repowarden agents init --global"* ]] || false
    [[ "$output" != *"Tout est prêt"* ]] || false
    # À jour pour l'utilisateur ; hook Claude d'une ancienne forme dans le dépôt
    cp "$PKG/hooks/agents/repowarden-garde.js" "$PKG/hooks/agents/repowarden-garde-v2.js" "$HOME/.config/opencode/plugins/"
    mkdir -p .claude
    printf '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|Bash","hooks":[{"type":"command","command":"repowarden garde"}]}]}}\n' >.claude/settings.json
    REPOWARDEN_LANG=en run "$PKG/bin/repowarden" statut
    [[ "$output" == *"Outdated repowarden guard"*".claude/settings.json"* ]] || false
    [[ "$output" == *"repowarden agents init"* ]] || false
    [[ "$output" != *"repowarden agents init --global"* ]] || false
    "$PKG/bin/repowarden" agents init --claude >/dev/null
    run "$PKG/bin/repowarden" statut
    [[ "$output" != *"périmé"* ]] || false
    [[ "$output" == *"Tout est prêt"* ]] || false
}

@test "statut : autre installation de repowarden -> signalee, reinstallation proposee" {
    autre="$BATS_TEST_TMPDIR/autre"
    mkdir -p "$autre"
    cp -R "$PKG/hooks" "$autre/"
    git config --global core.hooksPath "$autre/hooks"
    run "$PKG/bin/repowarden" statut
    [[ "$output" == *"Hooks git d'une autre installation de repowarden"* ]] || false
    [[ "$output" == *"Étape suivante : repowarden install --global"* ]] || false
}

@test "npm : uninstall --global rappelle npm uninstall -g (le paquet reste installe)" {
    pkg="$BATS_TEST_TMPDIR/prefix/lib/node_modules/repowarden"
    mkdir -p "$pkg"
    cp -R "$PKG/bin" "$PKG/hooks" "$PKG/install.sh" "$PKG/package.json" "$pkg/"
    "$pkg/bin/repowarden" install --global --lang fr >/dev/null
    run "$pkg/bin/repowarden" uninstall --global
    [ "$status" -eq 0 ]
    [[ "$output" == *"Le paquet reste installé ; pour le retirer aussi : npm uninstall -g repowarden"* ]] || false
}
