#!/usr/bin/env bats
# Garde-fou des agents IA (ticket #541) : agentsProtectedPaths, des chemins que
# le mainteneur retire aux agents, à l'écriture comme au commit.

load helpers

RW="$BATS_TEST_DIRNAME/../bin/repowarden"
AGENT=".devcontainer/opencode/agent.json"

setup() {
    require jq
    # Aucun réglage repowarden global du poste ne compte
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig-global"
    : >"$GIT_CONFIG_GLOBAL"
    setup_repo
    mkdir -p .devcontainer/opencode
    echo '{}' >"$AGENT"
    echo 'echo droits' >.devcontainer/agent-droits.sh
    printf '[repowarden]\n    agentsProtectedPaths = %s .devcontainer/*.sh\n' "$AGENT" >.repowarden.conf
    echo init >README.md
    git add -A
    git commit -q --no-verify -m "chore: init"
    git switch -q -c feat/essai
}

claude() {
    jq -n --arg t "$1" --argjson i "$2" --arg d "${3:-$PWD}" \
        '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: $i, cwd: $d}' |
        "$RW" garde --format claude
}

opencode() {
    jq -n --arg t "$1" --argjson a "$2" --arg d "${3:-$PWD}" '{tool: $t, args: $a, cwd: $d}' |
        "$RW" garde
}

shell() { opencode bash "$(jq -n --arg c "$1" '{command: $c}')"; }

edit() { claude Edit "$(jq -n --arg f "$PWD/${1:-README.md}" '{file_path: $f, old_string: "a", new_string: "b"}')"; }

refuse() {
    [ "$status" -eq 2 ] || { echo "status $status : $output"; return 1; }
    echo "$output"
    [[ "$output" == *"chemin protégé des agents"* ]] || false
}

@test "chemins : edition d'un chemin protege refusee, formats claude et opencode" {
    run edit "$AGENT"
    refuse
    [[ "$output" == *"$AGENT"* ]] || false
    run opencode write "$(jq -n --arg f "$PWD/$AGENT" '{filePath: $f, content: "x"}')"
    refuse
    # Joker du motif, et chemin relatif depuis un sous-dossier
    run edit ".devcontainer/agent-droits.sh"
    refuse
    run claude Write "$(jq -n '{file_path: "agent.json"}')" "$PWD/.devcontainer/opencode"
    refuse
    # Un autre fichier : la regle habituelle seule
    run edit "src/normal.ts"
    [ "$status" -eq 0 ]
    run edit ".devcontainer/autre.json"
    [ "$status" -eq 0 ]
}

@test "chemins : redirection, sed -i, cp et tee vers un chemin protege refuses" {
    for c in "echo x > $AGENT" "printf y>>$AGENT" "sed -i s/a/b/ $AGENT" \
        "cp /tmp/x $AGENT" "cp /tmp/agent.json .devcontainer/opencode/" "echo x | tee $AGENT" \
        "mv a .devcontainer/agent-droits.sh"; do
        run shell "$c"
        refuse || { echo "$c"; return 1; }
    done
    run shell 'echo x > journal.txt'
    [ "$status" -eq 0 ]
}

@test "chemins : agentsConfig true ne leve pas agentsProtectedPaths" {
    git config repowarden.agentsConfig true
    run edit "$AGENT"
    refuse
    run edit ".shellcheckrc"
    [ "$status" -eq 0 ]
}

@test "chemins : commit d'agent refuse si l'index touche un chemin protege" {
    echo '{"a":1}' >"$AGENT"
    echo y >autre.txt
    git add autre.txt
    run shell 'repowarden cc -m "fix: essai"'
    [ "$status" -eq 0 ]
    git add "$AGENT"
    run shell 'repowarden cc -m "fix: essai"'
    refuse
    run shell 'git cc -m "fix: essai"'
    refuse
    run shell 'git commit --amend --no-edit'
    refuse
    git reset -q "$AGENT"
    run shell 'git commit --amend --no-edit'
    [ "$status" -eq 0 ]
}

@test "chemins : -a et chemins donnes comptent comme l'index" {
    echo '{"a":1}' >"$AGENT"
    run shell 'repowarden cc -m "fix: essai"'
    [ "$status" -eq 0 ]
    run shell 'repowarden cc -a -m "fix: essai"'
    refuse
    run shell 'repowarden cc -m "fix: essai" -- .devcontainer/opencode'
    refuse
    run shell 'git commit -am "fix: essai"'
    refuse
    run shell 'repowarden cc -m "fix: essai" README.md'
    [ "$status" -eq 0 ]
}

@test "chemins : motif retire de l'arbre mais present dans HEAD reste protege" {
    printf '[repowarden]\n    sensitiveFiles = .env\n' >.repowarden.conf
    run edit "$AGENT"
    refuse
    # Le git config local est ignore pour cette cle
    git config repowarden.agentsProtectedPaths ""
    run edit "$AGENT"
    refuse
    git add .repowarden.conf
    run shell 'repowarden cc -m "fix: essai"'
    [ "$status" -eq 0 ]
}

@test "chemins : motif ajoute seulement a l'arbre protege aussi" {
    printf '[repowarden]\n    agentsProtectedPaths = docs/secret.md\n' >.repowarden.conf
    git commit -q --no-verify -am "chore: conf"
    printf '[repowarden]\n    agentsProtectedPaths = %s\n' "$AGENT" >.repowarden.conf
    run edit "$AGENT"
    refuse
    run edit "docs/secret.md"
    refuse
}

@test "chemins : sans le reglage, le depot se comporte comme avant" {
    git rm -q -f .repowarden.conf
    printf '[repowarden]\n    sensitiveFiles = .env\n' >.repowarden.conf
    git add .repowarden.conf
    git commit -q --no-verify -m "chore: conf"
    run edit "$AGENT"
    [ "$status" -eq 0 ]
    run shell "echo x > $AGENT"
    [ "$status" -eq 0 ]
    echo '{"a":1}' >"$AGENT"
    git add "$AGENT"
    run shell 'repowarden cc -m "fix: essai"'
    [ "$status" -eq 0 ]
}

@test "chemins : message en anglais" {
    REPOWARDEN_LANG=en run edit "$AGENT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"path protected from agents"* ]] || false
}
