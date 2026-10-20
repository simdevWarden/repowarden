#!/usr/bin/env bats
# repowarden agents init (ticket #317) : garde-fou branché dans Claude Code
# (hook PreToolUse) et opencode (plugin), sans jamais écraser un fichier.

load helpers

RW="$BATS_TEST_DIRNAME/../bin/repowarden"
MODELE="$BATS_TEST_DIRNAME/../hooks/agents/repowarden-garde.js"

setup() {
    require jq
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig-global"
    : >"$GIT_CONFIG_GLOBAL"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    # Configuration des agents hors du HOME de test (devzone : CLAUDE_CONFIG_DIR
    # pointe le vrai ~/.claude) : jamais suivie par les tests
    unset CLAUDE_CONFIG_DIR OPENCODE_CONFIG_DIR XDG_CONFIG_HOME
    setup_repo
    initial_commit
    # repowarden dans le PATH, comme après npm install -g ; script relais et
    # non lien symbolique : Git Bash (Windows) copie le fichier au lieu du lien
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$RW" >"$BATS_TEST_TMPDIR/bin/repowarden"
    chmod +x "$BATS_TEST_TMPDIR/bin/repowarden"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "agents init : hook Claude Code et plugin opencode dans le depot" {
    run "$RW" agents init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code : garde-fou ajouté"* ]] || false
    [[ "$output" == *"opencode : garde-fou ajouté"* ]] || false
    [[ "$output" == *"À versionner : git add .claude/settings.json .opencode/plugins/repowarden-garde.js"* ]] || false
    # jq -e : comparaison dans jq, sans les fins de ligne \r\n de jq sous Windows
    jq -e '.hooks.PreToolUse[0].matcher == "Edit|Write|MultiEdit|NotebookEdit|Bash"
        and .hooks.PreToolUse[0].hooks[0].command == "repowarden garde --format claude"' .claude/settings.json
    cmp -s .opencode/plugins/repowarden-garde.js "$MODELE"
}

@test "agents init : relance, rien ne change" {
    "$RW" agents init >/dev/null
    avant="$(cat .claude/settings.json .opencode/plugins/repowarden-garde.js | git hash-object --stdin)"
    run "$RW" agents init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code : garde-fou déjà en place"* ]] || false
    [[ "$output" == *"opencode : garde-fou déjà en place"* ]] || false
    [[ "$output" != *"À versionner"* ]] || false
    [ "$(cat .claude/settings.json .opencode/plugins/repowarden-garde.js | git hash-object --stdin)" = "$avant" ]
}

@test "agents init : settings.json existant complete, rien de perdu" {
    mkdir -p .claude
    printf '{"permissions":{"allow":["Bash(npm test)"]},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"./mon-hook.sh"}]}]}}\n' >.claude/settings.json
    run "$RW" agents init --claude
    [ "$status" -eq 0 ]
    [ "$(jq -r '.permissions.allow[0]' .claude/settings.json)" = "Bash(npm test)" ]
    [ "$(jq -r '.hooks.PreToolUse | length' .claude/settings.json)" = 2 ]
    [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' .claude/settings.json)" = "./mon-hook.sh" ]
    [ ! -e .opencode ]
}

@test "agents init : JSON invalide ou plugin modifie gardes tels quels" {
    mkdir -p .claude .opencode/plugins
    echo '{ pas du json' >.claude/settings.json
    echo '// mon plugin' >.opencode/plugins/repowarden-garde.js
    run "$RW" agents init
    [ "$status" -eq 1 ]
    [[ "$output" == *"n'est pas un JSON valide"* ]] || false
    [[ "$output" == *"diffère du modèle"* ]] || false
    [ "$(cat .claude/settings.json)" = '{ pas du json' ]
    [ "$(cat .opencode/plugins/repowarden-garde.js)" = '// mon plugin' ]
}

@test "agents init --global : configuration de l'utilisateur" {
    run "$RW" agents init --global
    [ "$status" -eq 0 ]
    [ -f "$HOME/.claude/settings.json" ]
    [ -f "$HOME/.config/opencode/plugins/repowarden-garde.js" ]
    [ ! -e .claude ]
    [[ "$output" != *"À versionner"* ]] || false
}

@test "agents init : hors depot git en mode projet, refuse" {
    cd "$BATS_TEST_TMPDIR"
    run "$RW" agents init
    [ "$status" -eq 1 ]
    [[ "$output" == *"Pas dans un dépôt git"* ]] || false
    [ ! -e "$BATS_TEST_TMPDIR/.claude" ]
}

@test "agents init : la commande ecrite pour Claude Code refuse sur main" {
    "$RW" agents init --claude >/dev/null
    commande="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' .claude/settings.json)"
    entree="$(jq -n --arg f "$PWD/README.md" --arg d "$PWD" \
        '{hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $f, content: "x"}, cwd: $d}')"
    run bash -c "$commande" <<<"$entree"
    [ "$status" -eq 2 ]
    [[ "$output" == *"branche protégée"* ]] || false
}

@test "agents init : le plugin opencode refuse sur main, permet sur une branche de travail" {
    require node
    # Node natif de Windows : les chemins POSIX de Git Bash lui sont illisibles
    case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) skip "Node natif sous Windows" ;; esac
    "$RW" agents init --opencode >/dev/null
    # Module ESM chargé comme opencode le ferait (Bun ou Node)
    cp .opencode/plugins/repowarden-garde.js "$BATS_TEST_TMPDIR/garde.mjs"
    cat >"$BATS_TEST_TMPDIR/appel.mjs" <<'JS'
const { RepowardenGarde } = await import(process.argv[2])
const hooks = await RepowardenGarde({ directory: process.cwd() })
try {
  await hooks["tool.execute.before"]({ tool: "write", sessionID: "s", callID: "c" }, { args: { filePath: "README.md", content: "x" } })
  console.log("permis")
} catch (e) {
  console.log("refusé : " + e.message)
}
JS
    run node "$BATS_TEST_TMPDIR/appel.mjs" "$BATS_TEST_TMPDIR/garde.mjs"
    [[ "$output" == "refusé : "*"branche protégée"* ]] || false
    git switch -q -c feat/essai
    run node "$BATS_TEST_TMPDIR/appel.mjs" "$BATS_TEST_TMPDIR/garde.mjs"
    [ "$output" = permis ]
}

@test "agents init --global : CLAUDE_CONFIG_DIR, OPENCODE_CONFIG_DIR, XDG_CONFIG_HOME suivis" {
    CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude" OPENCODE_CONFIG_DIR="$BATS_TEST_TMPDIR/oc" run "$RW" agents init --global
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/claude/settings.json" ]
    [ -f "$BATS_TEST_TMPDIR/oc/plugins/repowarden-garde.js" ]
    [ ! -e "$HOME/.claude" ] && [ ! -e "$HOME/.config/opencode" ]
    XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg" run "$RW" agents init --global --opencode
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/xdg/opencode/plugins/repowarden-garde.js" ]
}

@test "agents init : hooks repowarden inactifs signales, avec la commande" {
    run "$RW" agents init
    [[ "$output" != *"Hooks repowarden inactifs"* ]] || false
    rm -rf .claude .opencode
    git config --unset core.hooksPath
    run "$RW" agents init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hooks repowarden inactifs"*"repowarden install"* ]] || false
    run "$RW" agents init --global
    [[ "$output" == *"repowarden install --global"* ]] || false
}

@test "agents retirer : enleve seulement ce qu'init a ecrit" {
    "$RW" agents init >/dev/null
    run "$RW" agents retirer
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code : garde-fou retiré"* ]] || false
    [[ "$output" == *"opencode : garde-fou retiré"* ]] || false
    [ ! -e .claude/settings.json ] && [ ! -e .opencode/plugins/repowarden-garde.js ]
    # Relance : rien a retirer, sans erreur
    run "$RW" agents retirer
    [ "$status" -eq 0 ]
    [[ "$output" == *"pas de garde-fou à retirer"* ]] || false
}

@test "agents retirer : reglages et hooks voisins gardes, plugin modifie garde" {
    mkdir -p .claude
    printf '{"model":"x","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"mon-hook"}]}],"Stop":[{"hooks":[{"type":"command","command":"fin"}]}]}}\n' >.claude/settings.json
    "$RW" agents init >/dev/null
    printf '\n// modifie\n' >>.opencode/plugins/repowarden-garde.js
    run "$RW" agents retirer
    [ "$status" -eq 0 ]
    [ "$(jq -c '.hooks.PreToolUse' .claude/settings.json)" = '[{"matcher":"Bash","hooks":[{"type":"command","command":"mon-hook"}]}]' ]
    [ "$(jq -r '.model + " " + .hooks.Stop[0].hooks[0].command' .claude/settings.json)" = "x fin" ]
    ! grep -q "repowarden garde" .claude/settings.json
    [ -f .opencode/plugins/repowarden-garde.js ]
    [[ "$output" == *"diffère du modèle ; gardé"* ]] || false
}

@test "agents retirer --global : configuration de l'utilisateur, CLAUDE_CONFIG_DIR suivi" {
    export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
    "$RW" agents init --global >/dev/null
    run "$RW" agents retirer --global --claude
    [ "$status" -eq 0 ]
    [ ! -e "$CLAUDE_CONFIG_DIR/settings.json" ]
    [ -f "$HOME/.config/opencode/plugins/repowarden-garde.js" ]
}
