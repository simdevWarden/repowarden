#!/usr/bin/env bats
# Garde-fou des agents IA (ticket #317) : repowarden garde reçoit l'action
# d'un agent (JSON, format Claude Code ou opencode) et la permet (code 0) ou
# la refuse (code 2, raison et commande à lancer).

load helpers

RW="$BATS_TEST_DIRNAME/../bin/repowarden"

setup() {
    require jq
    # Aucun réglage repowarden global du poste ne compte
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig-global"
    : >"$GIT_CONFIG_GLOBAL"
    setup_repo
    initial_commit
}

# Action Claude Code (hook PreToolUse) : outil, entrée (JSON), dossier
claude() {
    jq -n --arg t "$1" --argjson i "$2" --arg d "${3:-$PWD}" \
        '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: $i, cwd: $d}' |
        "$RW" garde --format claude
}

# Action opencode (tool.execute.before) : outil, arguments (JSON), dossier
opencode() {
    jq -n --arg t "$1" --argjson a "$2" --arg d "${3:-$PWD}" '{tool: $t, args: $a, cwd: $d}' |
        "$RW" garde
}

# Commande shell lancée par un agent (format opencode)
shell() { opencode bash "$(jq -n --arg c "$1" '{command: $c}')"; }

edit() { claude Edit "$(jq -n --arg f "$PWD/${1:-README.md}" '{file_path: $f, old_string: "a", new_string: "b"}')"; }

@test "garde : modification sur main refusee, avec la commande a lancer" {
    run edit
    [ "$status" -eq 2 ]
    [[ "$output" == *"« main » est une branche protégée"* ]] || false
    [[ "$output" == *"git switch -c <type>/<sujet>"* ]] || false
}

@test "garde : modification sur une branche de travail permise" {
    git switch -q -c feat/essai
    run edit
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run opencode write "$(jq -n '{filePath: "nouveau.txt", content: "x"}')"
    [ "$status" -eq 0 ]
}

@test "garde : branche d'integration et protectedBranches refusees" {
    git config repowarden.integrationBranch develop
    git switch -q -c develop
    run edit
    [ "$status" -eq 2 ]
    [[ "$output" == *"« develop » est une branche protégée"* ]] || false
    git config repowarden.protectedBranches "main prod"
    git switch -q -c prod
    run opencode edit "$(jq -n --arg f "$PWD/README.md" '{filePath: $f}')"
    [ "$status" -eq 2 ]
}

@test "garde : HEAD detache refuse" {
    git switch -q --detach
    run edit
    [ "$status" -eq 2 ]
    [[ "$output" == *"HEAD détaché"* ]] || false
    [[ "$output" == *"repowarden ticket <n>"* ]] || false
}

@test "garde : depot qui suit ses tickets, seulement sur une branche de ticket" {
    git config repowarden.tickets true
    git switch -q -c feat/essai
    run edit
    [ "$status" -eq 2 ]
    [[ "$output" == *"n'est pas celle d'un ticket"* ]] || false
    [[ "$output" == *"repowarden ticket <n>"* ]] || false
    # main : la marche à suivre est le ticket, pas une branche libre
    git switch -q main
    run edit
    [ "$status" -eq 2 ]
    [[ "$output" == *"repowarden ticket <n>"* ]] || false
    git switch -q -c feat/12-essai
    run edit
    [ "$status" -eq 0 ]
}

@test "garde : suivi des tickets detecte par le workflow tickets.yml" {
    mkdir -p .github/workflows
    printf 'jobs:\n  t:\n    uses: simdevWarden/repowarden/.github/workflows/tickets.yml@v4\n' >.github/workflows/tickets.yml
    git switch -q -c feat/essai
    run edit
    [ "$status" -eq 2 ]
}

@test "garde : creation de branche refusee si le depot suit ses tickets" {
    for c in "git checkout -b feat/x" "git switch -c feat/x" "git branch feat/x" \
        "git worktree add -b feat/x ../x" "git switch --create feat/x"; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "sans tickets : $c refusé"; return 1; }
    done
    git config repowarden.tickets true
    for c in "git checkout -b feat/x" "git switch -c feat/x" "git branch feat/x" \
        "git worktree add -b feat/x ../x" "git switch --create feat/x"; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "avec tickets : $c permis"; return 1; }
        [[ "$output" == *"repowarden ticket <n>"* ]] || false
    done
    for c in "git branch -d feat/x" "git branch" "git branch --show-current" "git switch feat/x" "git checkout feat/x"; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refusé"; return 1; }
    done
}

@test "garde : commit par repowarden cc ; seul --amend --no-edit permis" {
    run shell 'git commit -m "feat: x"'
    [ "$status" -eq 2 ]
    [[ "$output" == *"repowarden cc -m"* ]] || false
    run shell 'git commit --amend'
    [ "$status" -eq 2 ]
    for c in 'git commit --amend --no-edit' 'git status'; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refusé"; return 1; }
    done
    git switch -q -c feat/essai
    for c in 'repowarden cc -m "x" --type feat' 'git cc -m x'; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refusé"; return 1; }
    done
}

@test "garde : repowarden cc sur une branche protegee refuse, avec la branche a creer" {
    for c in 'repowarden cc -m "x" --type feat' 'git cc -m x' "'repowarden' commit -m x"; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"« main » est une branche protégée, le commit y serait refusé"* ]] || false
        [[ "$output" == *"git switch -c <type>/<sujet>"* ]] || false
    done
    # Depot qui suit ses tickets : la branche nait du ticket
    git config repowarden.tickets true
    run shell 'repowarden cc -m x'
    [ "$status" -eq 2 ]
    [[ "$output" == *"repowarden ticket <n>"* ]] || false
}

@test "garde : hooks repowarden inactifs -> commits refuses, avec repowarden install" {
    printf '[repowarden]\n\tversion = 4\n' >.repowarden.conf
    git config --unset core.hooksPath
    git switch -q -c feat/essai
    for c in 'repowarden cc -m x' 'git commit --amend --no-edit' 'git commit -m x'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"hooks repowarden ne sont pas actifs"*"repowarden install"* ]] || false
    done
    # Les modifications restent permises : seul le commit, non verifie, est refuse
    run edit
    [ "$status" -eq 0 ]
    # Chemin relatif (depuis la racine du depot), comme git le lit : actifs
    ln -s "$HOOKS" "$REPO/.hooks-rw" 2>/dev/null || cp -R "$HOOKS" "$REPO/.hooks-rw"
    git config core.hooksPath .hooks-rw
    run shell 'repowarden cc -m x'
    [ "$status" -eq 0 ]
}

@test "garde : ligne de plusieurs commandes refusee en bloc, et l'agent le sait" {
    git switch -q -c feat/essai
    run shell 'git add README.md && git commit -m "feat: x"'
    [ "$status" -eq 2 ]
    [[ "$output" == *"Rien de cette ligne n'a été lancé"* ]] || false
    run shell 'git commit -m "feat: x"'
    [ "$status" -eq 2 ]
    [[ "$output" != *"Rien de cette ligne"* ]] || false
}

@test "garde : --no-verify refuse (commit -n compris)" {
    for c in 'git push --no-verify' 'git commit --amend --no-edit --no-verify' 'git commit -n -m x' 'git commit -nm x'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"--no-verify"* ]] || false
    done
}

@test "garde : git add . / -A / --all refuses, fichiers nommes permis" {
    for c in 'git add .' 'git add -A' 'git add --all' 'git add -Av'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"git add <fichiers>"* ]] || false
    done
    run shell 'git add README.md src/a.sh'
    [ "$status" -eq 0 ]
}

@test "garde : chaque commande d'une ligne, cd et git -C suivis" {
    run shell 'echo ok && ls | grep x; git add -A'
    [ "$status" -eq 2 ]
    # Dossier pas encore créé : le dépôt qui le contient compte
    run shell 'cd sous/dossier && git commit -m x'
    [ "$status" -eq 2 ]
    # Autre dépôt, sans repowarden : tout y est permis
    git init -q -b main "$BATS_TEST_TMPDIR/libre"
    run shell "git -C $BATS_TEST_TMPDIR/libre commit -m x"
    [ "$status" -eq 0 ]
    run shell "cd $BATS_TEST_TMPDIR/libre && git add -A"
    [ "$status" -eq 0 ]
    FOO=1 run shell 'FOO=1 git commit -m x'
    [ "$status" -eq 2 ]
}

@test "garde : apply_patch d'opencode, chemins lus dans patchText" {
    patch='*** Begin Patch\n*** Add File: src/nouveau.ts\n+x\n*** End Patch'
    run opencode apply_patch "$(jq -n --arg p "$(printf "$patch")" '{patchText: $p}')"
    [ "$status" -eq 2 ]
    git switch -q -c feat/essai
    run opencode apply_patch "$(jq -n --arg p "$(printf "$patch")" '{patchText: $p}')"
    [ "$status" -eq 0 ]
}

@test "garde : hors depot repowarden, tout est permis" {
    libre="$BATS_TEST_TMPDIR/libre"
    git init -q -b main "$libre"
    run claude Write "$(jq -n --arg f "$libre/a" '{file_path: $f, content: "x"}')" "$libre"
    [ "$status" -eq 0 ]
    run claude Write "$(jq -n --arg f "$BATS_TEST_TMPDIR/hors-git.txt" '{file_path: $f, content: "x"}')" "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # Outils qui ne modifient rien
    run claude Read "$(jq -n --arg f "$PWD/README.md" '{file_path: $f}')"
    [ "$status" -eq 0 ]
}

@test "garde : panne du garde-fou jamais bloquante, format inconnu refuse" {
    run bash -c "echo 'pas du json' | '$RW' garde --format claude"
    [ "$status" -eq 1 ]
    [[ "$output" == *"illisible"* ]] || false
    run "$RW" garde --format cursor </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"claude ou opencode"* ]] || false
}

@test "garde : messages en anglais avec REPOWARDEN_LANG=en" {
    REPOWARDEN_LANG=en run edit
    [ "$status" -eq 2 ]
    [[ "$output" == *'"main" is a protected branch'* ]] || false
    REPOWARDEN_LANG=en run shell 'git add README.md && repowarden cc -m x'
    [ "$status" -eq 2 ]
    [[ "$output" == *"git switch -c <type>/<topic>"* ]] || false
    [[ "$output" == *"Nothing on this line was run"* ]] || false
}
