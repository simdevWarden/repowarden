#!/usr/bin/env bats
# repowarden agents init (ticket #317) : garde-fou branché dans Claude Code
# (hook PreToolUse) et opencode (plugin), sans jamais écraser un fichier.

load helpers

RW="$BATS_TEST_DIRNAME/../bin/repowarden"
MODELE="$BATS_TEST_DIRNAME/../hooks/agents/repowarden-garde.js"
MODELE_V2="$BATS_TEST_DIRNAME/../hooks/agents/repowarden-garde-v2.js"

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
    [[ "$output" == *"À versionner : git add .claude/settings.json .opencode/plugins/repowarden-garde.js .opencode/plugins/repowarden-garde-v2.js .claude/skills/repowarden/SKILL.md .opencode/skills/repowarden/SKILL.md"* ]] || false
    # jq -e : comparaison dans jq, sans les fins de ligne \r\n de jq sous Windows
    jq -e '.hooks.PreToolUse[0].matcher == "Edit|Write|MultiEdit|NotebookEdit|Bash"
        and .hooks.PreToolUse[0].hooks[0].command == "repowarden garde --format claude"' .claude/settings.json
    cmp -s .opencode/plugins/repowarden-garde.js "$MODELE"
    cmp -s .opencode/plugins/repowarden-garde-v2.js "$MODELE_V2"
}

@test "agents init : relance, rien ne change" {
    "$RW" agents init >/dev/null
    avant="$(cat .claude/settings.json .opencode/plugins/repowarden-garde.js .claude/skills/repowarden/SKILL.md .opencode/skills/repowarden/SKILL.md | git hash-object --stdin)"
    run "$RW" agents init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code : garde-fou déjà en place"* ]] || false
    [[ "$output" == *"opencode : garde-fou déjà en place"* ]] || false
    [[ "$output" == *"Claude Code : skill repowarden déjà en place"* ]] || false
    [[ "$output" == *"opencode : skill repowarden déjà en place"* ]] || false
    [[ "$output" != *"À versionner"* ]] || false
    [ "$(cat .claude/settings.json .opencode/plugins/repowarden-garde.js .claude/skills/repowarden/SKILL.md .opencode/skills/repowarden/SKILL.md | git hash-object --stdin)" = "$avant" ]
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
    [[ "$output" == *"Claude Code : skill repowarden retirée"* ]] || false
    [[ "$output" == *"opencode : skill repowarden retirée"* ]] || false
    [ ! -e .claude/settings.json ] && [ ! -e .opencode/plugins/repowarden-garde.js ]
    [ ! -e .opencode/plugins/repowarden-garde-v2.js ]
    [ ! -e .claude/skills/repowarden ] && [ ! -e .opencode/skills/repowarden ]
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

# Ticket #470 : un garde-fou posé par une version antérieure de repowarden suit
# les mises à jour ; un fichier personnel n'est jamais écrasé
ANCIEN_PLUGIN="$BATS_TEST_DIRNAME/fixtures/agents/ancien-plugin-opencode-autonome.js"

@test "agents init : ancien plugin opencode de repowarden remplace par le modele" {
    mkdir -p .opencode/plugins
    cp "$ANCIEN_PLUGIN" .opencode/plugins/repowarden-garde.js
    run "$RW" agents init --opencode
    [ "$status" -eq 0 ]
    [[ "$output" == *"opencode : garde-fou mis à jour"* ]] || false
    [[ "$output" == *"À versionner : git add .opencode/plugins/repowarden-garde.js"* ]] || false
    cmp -s .opencode/plugins/repowarden-garde.js "$MODELE"
    # Relance : déjà à jour
    run "$RW" agents init --opencode
    [[ "$output" == *"opencode : garde-fou déjà en place"* ]] || false
}

@test "agents init : plugin personnalise (sans en-tete repowarden) garde et signale" {
    mkdir -p .opencode/plugins
    printf '// Mon garde-fou\nimport { spawnSync } from "node:child_process"\n// repowarden garde\n' >.opencode/plugins/repowarden-garde.js
    cp .opencode/plugins/repowarden-garde.js "$BATS_TEST_TMPDIR/perso.js"
    run "$RW" agents init --opencode
    [ "$status" -eq 0 ]
    [[ "$output" == *"diffère du modèle ; gardé tel quel"* ]] || false
    [[ "$output" != *"mis à jour"* ]] || false
    cmp -s .opencode/plugins/repowarden-garde.js "$BATS_TEST_TMPDIR/perso.js"
}

@test "agents init : ancien hook Claude remplace, autres hooks et reglages intacts" {
    mkdir -p .claude
    printf '%s\n' '{"model":"x","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"./mon-hook.sh"}]},{"matcher":"Edit|Write|Bash","hooks":[{"type":"command","command":"repowarden garde"}]},{"matcher":"Write","hooks":[{"type":"command","command":"repowarden garde --format claude"},{"type":"command","command":"autre-hook"}]}],"Stop":[{"hooks":[{"type":"command","command":"fin"}]}]}}' >.claude/settings.json
    run "$RW" agents init --claude
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code : garde-fou mis à jour"* ]] || false
    # Une seule entrée repowarden, sous la forme actuelle
    jq -e '[.hooks.PreToolUse[].hooks[] | select(.command | startswith("repowarden garde"))] | length == 1' .claude/settings.json
    jq -e '.hooks.PreToolUse[-1] == {matcher: "Edit|Write|MultiEdit|NotebookEdit|Bash", hooks: [{type: "command", command: "repowarden garde --format claude"}]}' .claude/settings.json
    # Hooks et réglages de l'utilisateur intacts
    jq -e '.hooks.PreToolUse[0] == {matcher: "Bash", hooks: [{type: "command", command: "./mon-hook.sh"}]}' .claude/settings.json
    jq -e '.hooks.PreToolUse[1] == {matcher: "Write", hooks: [{type: "command", command: "autre-hook"}]}' .claude/settings.json
    jq -e '.model == "x" and .hooks.Stop[0].hooks[0].command == "fin" and (.hooks.PreToolUse | length) == 3' .claude/settings.json
    run "$RW" agents init --claude
    [[ "$output" == *"Claude Code : garde-fou déjà en place"* ]] || false
}

# Ticket #475 : skill repowarden (le circuit, les commandes, quoi faire d'un
# refus) posée avec le garde-fou, mise à jour selon la même règle
SKILL_FR="$BATS_TEST_DIRNAME/../hooks/agents/skill-repowarden.fr.md"
SKILL_EN="$BATS_TEST_DIRNAME/../hooks/agents/skill-repowarden.en.md"

# Ticket #469 : opencode 2.x n'appelle que l'export par défaut { id, setup } ;
# opencode 1.x ignore l'export nommé d'un module qui en a un : deux fichiers
@test "agents init : plugin opencode 2.x a cote du plugin 1.x, ajoute s'il manque" {
    mkdir -p .opencode/plugins
    cp "$MODELE" .opencode/plugins/repowarden-garde.js
    run "$RW" statut
    [[ "$output" == *"Garde-fou repowarden périmé"*"repowarden-garde-v2.js"* ]] || false
    run "$RW" agents init --opencode
    [ "$status" -eq 0 ]
    [[ "$output" == *"opencode : garde-fou déjà en place ("*"/.opencode/plugins/repowarden-garde.js)"* ]] || false
    [[ "$output" == *"opencode : garde-fou ajouté ("*"/.opencode/plugins/repowarden-garde-v2.js)"* ]] || false
    cmp -s .opencode/plugins/repowarden-garde-v2.js "$MODELE_V2"
    run "$RW" statut
    [[ "$output" != *"périmé"* ]] || false
}

@test "agents init : plugin opencode 2.x refuse sur main, permet sur une branche (contexte v2 simule)" {
    require node
    case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) skip "Node natif sous Windows" ;; esac
    "$RW" agents init --opencode >/dev/null
    cp .opencode/plugins/repowarden-garde.js "$BATS_TEST_TMPDIR/v1.mjs"
    cp .opencode/plugins/repowarden-garde-v2.js "$BATS_TEST_TMPDIR/v2.mjs"
    # Contexte d'opencode 2.x : ctx.tool.hook(nom, rappel), ctx.location.directory
    cat >"$BATS_TEST_TMPDIR/appel.mjs" <<'JS'
const plugin = (await import(process.argv[2])).default
const crochets = {}
await plugin.setup({ location: { directory: process.cwd() }, tool: { hook: (nom, rappel) => { crochets[nom] = rappel } } })
const [tool, input] = [process.argv[3], JSON.parse(process.argv[4])]
try {
  await crochets["execute.before"]({ tool, sessionID: "s", id: "c", input })
  console.log("permis")
} catch (e) {
  console.log("refusé : " + e.message)
}
JS
    run node "$BATS_TEST_TMPDIR/appel.mjs" "$BATS_TEST_TMPDIR/v2.mjs" write '{"path":"README.md","content":"x"}'
    [[ "$output" == "refusé : "*"branche protégée"* ]] || false
    run node "$BATS_TEST_TMPDIR/appel.mjs" "$BATS_TEST_TMPDIR/v2.mjs" shell '{"command":"git commit -m x"}'
    [[ "$output" == "refusé : "*"repowarden cc"* ]] || false
    # repowarden absent : rien n'est bloqué
    node="$(command -v node)"
    PATH="$BATS_TEST_TMPDIR/vide" run "$node" "$BATS_TEST_TMPDIR/appel.mjs" "$BATS_TEST_TMPDIR/v2.mjs" write '{"path":"README.md","content":"x"}'
    [ "$output" = permis ]
    git switch -q -c feat/essai
    run node "$BATS_TEST_TMPDIR/appel.mjs" "$BATS_TEST_TMPDIR/v2.mjs" write '{"path":"README.md","content":"x"}'
    [ "$output" = permis ]
    # Contexte d'opencode 1.x (sans ctx.tool) : setup ne fait rien ; le plugin
    # 1.x n'a pas d'export par défaut, sinon 1.x n'appellerait plus son crochet
    cat >"$BATS_TEST_TMPDIR/v1x.mjs" <<'JS'
const v2 = (await import(process.argv[2])).default
await v2.setup({ agent: {}, plugin: {} })
const v1 = await import(process.argv[3])
console.log(v2.id, typeof v1.default, typeof v1.RepowardenGarde)
JS
    run node "$BATS_TEST_TMPDIR/v1x.mjs" "$BATS_TEST_TMPDIR/v2.mjs" "$BATS_TEST_TMPDIR/v1.mjs"
    [ "$status" -eq 0 ]
    [ "$output" = "repowarden-garde undefined function" ]
}

@test "agents init : skill repowarden posee pour Claude Code et opencode, dans la langue de repowarden" {
    run "$RW" agents init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code : skill repowarden ajoutée"* ]] || false
    [[ "$output" == *"opencode : skill repowarden ajoutée"* ]] || false
    cmp -s .claude/skills/repowarden/SKILL.md "$SKILL_FR"
    cmp -s .opencode/skills/repowarden/SKILL.md "$SKILL_FR"
    rm -rf .claude .opencode
    REPOWARDEN_LANG=en run "$RW" agents init --opencode
    [ "$status" -eq 0 ]
    [[ "$output" == *"opencode: repowarden skill added"* ]] || false
    cmp -s .opencode/skills/repowarden/SKILL.md "$SKILL_EN"
    [ ! -e .claude ]
}

@test "agents init --global : skill dans la configuration de l'utilisateur, CLAUDE_CONFIG_DIR et OPENCODE_CONFIG_DIR suivis" {
    run "$RW" agents init --global
    [ "$status" -eq 0 ]
    cmp -s "$HOME/.claude/skills/repowarden/SKILL.md" "$SKILL_FR"
    cmp -s "$HOME/.config/opencode/skills/repowarden/SKILL.md" "$SKILL_FR"
    CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude" OPENCODE_CONFIG_DIR="$BATS_TEST_TMPDIR/oc" run "$RW" agents init --global
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/claude/skills/repowarden/SKILL.md" ]
    [ -f "$BATS_TEST_TMPDIR/oc/skills/repowarden/SKILL.md" ]
    [ ! -e .claude ]
}

@test "agents init : skill repowarden perimee remplacee, skill personnalisee gardee" {
    # Posée par repowarden (repère), mais d'une version antérieure
    mkdir -p .claude/skills/repowarden .opencode/skills/repowarden
    sed 's/^# .*/# Ancienne version/' "$SKILL_FR" >.claude/skills/repowarden/SKILL.md
    run cmp -s .claude/skills/repowarden/SKILL.md "$SKILL_FR"
    [ "$status" -ne 0 ]
    # Écrite à la main, sans repère : jamais écrasée
    printf -- '---\nname: repowarden\ndescription: la mienne\n---\nMes règles\n' >.opencode/skills/repowarden/SKILL.md
    cp .opencode/skills/repowarden/SKILL.md "$BATS_TEST_TMPDIR/perso.md"
    run "$RW" agents init
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code : skill repowarden mise à jour"* ]] || false
    [[ "$output" == *"pour la personnaliser"* ]] || false
    [[ "$output" == *"retirer la ligne repère"* ]] || false
    [[ "$output" == *"opencode : skill repowarden"*"diffère du modèle ; gardée telle quelle"* ]] || false
    cmp -s .claude/skills/repowarden/SKILL.md "$SKILL_FR"
    cmp -s .opencode/skills/repowarden/SKILL.md "$BATS_TEST_TMPDIR/perso.md"
    # Autre langue : posée par repowarden, remplacée par le modèle de la langue
    REPOWARDEN_LANG=en run "$RW" agents init --claude
    [[ "$output" == *"Claude Code: repowarden skill updated"* ]] || false
    [[ "$output" == *"to customize it"* ]] || false
    [[ "$output" == *"remove its marker line"* ]] || false
    cmp -s .claude/skills/repowarden/SKILL.md "$SKILL_EN"
}

@test "agents retirer : skill identique au modele retiree, skill modifiee gardee" {
    "$RW" agents init >/dev/null
    printf '\nMa règle\n' >>.opencode/skills/repowarden/SKILL.md
    run "$RW" agents retirer
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code : skill repowarden retirée"* ]] || false
    [[ "$output" == *"opencode : skill repowarden"*"gardée"* ]] || false
    [ ! -e .claude/skills/repowarden ]
    [ -f .opencode/skills/repowarden/SKILL.md ]
    run "$RW" agents retirer --claude
    [ "$status" -eq 0 ]
    [[ "$output" == *"pas de skill repowarden à retirer"* ]] || false
}

@test "skill repowarden : modeles fr et en, nom, declencheurs et commandes du circuit" {
    for f in "$SKILL_FR" "$SKILL_EN"; do
        [ "$(sed -n 1p "$f")" = --- ]
        [ "$(sed -n 2p "$f")" = "name: repowarden" ]
        description="$(grep -m1 '^description: ' "$f")"
        for mot in ticket commit PR push; do
            [[ "$description" == *"$mot"* ]] || false
        done
        grep -q '^<!-- repowarden:skill' "$f"
        for commande in "repowarden ticket <n>" "repowarden ticket comment" "repowarden cc -m" "git add <" \
            "git push -u origin HEAD" "repowarden pr checks" "repowarden run rerun" "REPOWARDEN_TICKET=<n>" \
            "opencode run --auto" "< /dev/null" "--no-verify"; do
            grep -qF -- "$commande" "$f" || { echo "$f : $commande absente"; false; }
        done
    done
    grep -q 'retirer cette ligne pour la personnaliser' "$SKILL_FR" || false
    grep -q 'remove this line to customize it' "$SKILL_EN" || false
    grep -q 'Personnaliser la skill' "$BATS_TEST_DIRNAME/../docs/agents.md" || false
    grep -q 'Customizing the skill' "$BATS_TEST_DIRNAME/../docs/agents.en.md" || false
    # Même plan dans les deux langues
    [ "$(grep -c '^## ' "$SKILL_FR")" = "$(grep -c '^## ' "$SKILL_EN")" ]
}
