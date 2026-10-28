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

@test "garde : fichier ignore par git permis sur une branche protegee, fichier suivi controle" {
    printf 'notes/\n*.log\n' >.gitignore
    printf 'x\n' >suivi.log
    git add .gitignore && git add -f suivi.log
    git -c core.hooksPath=/dev/null commit -q -m "chore: ignore"
    git config repowarden.integrationBranch develop
    patch='*** Begin Patch\n*** Add File: notes/p.md\n+x\n*** Update File: sortie.log\n+x\n*** End Patch'
    for b in main develop; do
        git switch -q "$b" 2>/dev/null || git switch -q -c "$b"
        mkdir -p src/sous
        for f in notes/a/x.md sortie.log src/sous/y.log; do
            run edit "$f"
            [ "$status" -eq 0 ] || { echo "$b : $f refusé : $output"; return 1; }
        done
        run opencode apply_patch "$(jq -n --arg p "$(printf "$patch")" '{patchText: $p}')"
        [ "$status" -eq 0 ] || { echo "$b : apply_patch refusé : $output"; return 1; }
        # Non ignoré, ou suivi malgré le motif d'ignore : toujours contrôlé
        for f in README.md src/n.ts suivi.log; do
            run edit "$f"
            [ "$status" -eq 2 ] || { echo "$b : $f permis"; return 1; }
            [[ "$output" == *"« $b » est une branche protégée"* ]] || false
        done
    done
    # Dépôt qui suit ses tickets : branche hors ticket, fichier ignoré permis
    git config repowarden.tickets true
    git switch -q -c feat/essai
    run edit notes/x.md
    [ "$status" -eq 0 ]
    run edit README.md
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

@test "garde : aide et apercu de cc et git commit permis partout (rien n'est commite)" {
    for c in 'repowarden cc --help' 'repowarden cc -h' 'repowarden cc --dry-run -m x' 'git cc --help' 'git commit -h' 'git commit --dry-run'; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refusé : $output"; return 1; }
    done
    # Hooks inactifs : l'aide reste lisible, le commit non
    printf '[repowarden]\n\tversion = 4\n' >.repowarden.conf
    git config --unset core.hooksPath
    run shell 'repowarden cc --help'
    [ "$status" -eq 0 ]
    run shell 'repowarden cc -m x'
    [ "$status" -eq 2 ]
    # --no-verify reste refuse, meme avec une aide
    run shell 'git commit --dry-run --no-verify'
    [ "$status" -eq 2 ]
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

@test "garde : force push refuse, git push simple permis" {
    git switch -q -c feat/essai
    for c in 'git push --force' 'git push -f' 'git push -uf origin feat/essai' 'git push --force-with-lease' \
        'git push --force-with-lease=feat/essai origin feat/essai' 'git push --force-if-includes' \
        'git push origin +feat/essai' 'git -C . push -f' 'git add README.md && git push -f'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"réécrit l'historique"* ]] || false
        [[ "$output" == *"nouveau commit"* ]] || false
    done
    run claude Bash '{"command": "git push --force origin main"}'
    [ "$status" -eq 2 ]
    for c in 'git push' 'git push -u origin HEAD' 'git push origin feat/essai'; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refuse"; return 1; }
    done
    REPOWARDEN_LANG=en run shell 'git push -f'
    [ "$status" -eq 2 ]
    [[ "$output" == *"rewrites the history"* ]] || false
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

@test "garde : redirection 2>&1 gardee dans la commande citee et proposee" {
    gh_simule
    run shell 'gh issue close 1 2>&1 | head'
    [ "$status" -eq 2 ]
    [[ "$output" == *"« gh issue close 1 2>&1 »"* ]] || false
    [[ "$output" == *"REPOWARDEN_TICKET=<n> gh issue close 1 2>&1"* ]] || false
}

@test "garde : redirections 2>&1, >&2 et &>log ne coupent pas la commande" {
    for c in 'git status 2>&1' 'git status >&2' 'git status &>log'; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refuse : $output"; return 1; }
    done
    # La redirection ne masque pas la commande : refus entier, pas une ligne
    # de plusieurs commandes
    for c in 'git add . 2>&1' 'git add . >&2' 'git add . &>log'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"« $c »"* ]] || false
        [[ "$output" != *"Rien de cette ligne"* ]] || false
    done
}

@test "garde : un faux & de redirection ne masque jamais une commande" {
    # bash lance chaque fois une seconde commande git : refus obligatoire
    for c in 'true \>&git push -f' 'echo >&git push -f' 'true 2>&git add .' \
        'echo x >& git push --force'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis : $output"; return 1; }
        [[ "$output" == *"Rien de cette ligne"* ]] || false
    done
}

@test "garde : & seul separe toujours deux commandes" {
    run shell 'true & git add .'
    [ "$status" -eq 2 ]
    [[ "$output" == *"« git add . »"* ]] || false
    [[ "$output" == *"Rien de cette ligne"* ]] || false
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

# Ticket #469 : outils d'opencode 2.x (write/edit à argument path, shell)
@test "garde : opencode 2.x, write et edit (path) et shell verifies" {
    run opencode write "$(jq -n --arg f "$PWD/README.md" '{path: $f, content: "x"}')"
    [ "$status" -eq 2 ]
    [[ "$output" == *"« main » est une branche protégée"* ]] || false
    run opencode edit "$(jq -n '{path: "README.md", oldString: "a", newString: "b"}')"
    [ "$status" -eq 2 ]
    run opencode shell "$(jq -n '{command: "git commit -m x", workdir: "."}')"
    [ "$status" -eq 2 ]
    [[ "$output" == *"repowarden cc"* ]] || false
    git switch -q -c feat/essai
    run opencode write "$(jq -n '{path: "nouveau.txt", content: "x"}')"
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

# gh simulé (ticket #454) : journal des appels ; gh issue view rend
# $FAKE_TICKET (état puis étiquettes, une par ligne), code $FAKE_TICKET_RC
gh_simule() {
    mkdir -p "$BATS_TEST_TMPDIR/gh/bin"
    cat >"$BATS_TEST_TMPDIR/gh/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$BATS_TEST_TMPDIR/gh/log"
case "$1 $2" in
    "issue view") [ -n "${FAKE_TICKET:-}" ] && printf '%b\n' "$FAKE_TICKET"; exit "${FAKE_TICKET_RC:-0}" ;;
esac
exit 0
GH
    chmod +x "$BATS_TEST_TMPDIR/gh/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/gh/bin:$PATH"
}

@test "garde gh : lectures permises ; ecritures du circuit refusees, avec la commande repowarden" {
    gh_simule
    for c in 'gh issue view 12' 'gh issue list --label validé' 'gh issue status' 'gh pr view 3' 'gh pr list' \
        'gh pr status' 'gh pr checks 3' 'gh pr diff 3' 'gh run view 1 --log-failed' 'gh run list' \
        'gh release view v1' 'gh release list' 'gh repo view' 'gh workflow view ci.yml' 'gh workflow list' \
        'gh api repos/o/r/pulls' 'gh api -X GET repos/o/r/issues -f state=open' 'gh auth status' \
        "gh api graphql -f query='query { viewer { login } }'" 'gh pr edit 3 --body x' 'gh -R o/r issue view 1'; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refusé : $output"; return 1; }
    done
    run shell 'gh issue create --title x --body y'
    [ "$status" -eq 2 ]
    [[ "$output" == *"repowarden ticket nouveau"* ]] || false
    for c in 'gh issue comment 12 --body x' 'gh issue edit 12 --add-label validé'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"repowarden ticket comment"*"repowarden ticket label"* ]] || false
    done
    run shell 'gh pr create --fill'
    [ "$status" -eq 2 ]
    [[ "$output" == *"git push -u origin HEAD"* ]] || false
    run shell 'gh run rerun 123 --failed'
    [ "$status" -eq 2 ]
    [[ "$output" == *"repowarden run rerun"* ]] || false
}

@test "garde gh : decisions du mainteneur refusees, meme avec un ticket valide" {
    gh_simule
    export FAKE_TICKET='OPEN\nvalidé'
    for c in 'gh pr ready 3' 'gh pr merge 3 --squash' 'gh pr review 3 --approve' 'gh pr review 3 -a' \
        'gh api -X POST repos/o/r/actions/runs/1/pending_deployments -f state=approved' \
        'REPOWARDEN_TICKET=12 gh pr merge 3'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"décision du mainteneur"* ]] || false
    done
}

@test "garde gh : ecriture hors circuit refusee sans ticket" {
    gh_simule
    for c in 'gh api -X PATCH repos/o/r -f allow_auto_merge=true' 'gh api repos/o/r/labels -f name=x' \
        'gh api --method DELETE repos/o/r/hooks/1' 'gh api repos/o/r/rulesets --input r.json' \
        "gh api graphql -f query='mutation { x }'" 'gh repo edit --enable-auto-merge' 'gh repo delete o/r --yes' \
        'gh variable set X --body 1' 'gh secret delete X' 'gh release create v1' 'gh release edit v1' \
        'gh release delete v1' 'gh workflow run ci.yml' 'gh workflow enable ci.yml' 'gh workflow disable ci.yml' \
        'gh run cancel 1' 'gh run delete 1' 'gh label create x' 'gh label edit x' 'gh label delete x'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"sans ticket"*"REPOWARDEN_TICKET=<n>"* ]] || false
    done
    [ ! -s "$BATS_TEST_TMPDIR/gh/log" ]
}

@test "garde gh : prefixe REPOWARDEN_TICKET d'un ticket ouvert et valide" {
    gh_simule
    export FAKE_TICKET='OPEN\nfeat\nvalidé'
    run shell 'REPOWARDEN_TICKET=12 gh repo edit --enable-auto-merge'
    [ "$status" -eq 0 ]
    grep -q '^issue view 12 --json state,labels' "$BATS_TEST_TMPDIR/gh/log"
    # Ticket d'un autre dépôt (-R) : lu dans ce dépôt
    run shell 'env REPOWARDEN_TICKET=7 gh label create x -R o/autre'
    [ "$status" -eq 0 ]
    grep -q '^issue view 7 .*-R o/autre' "$BATS_TEST_TMPDIR/gh/log"
    # Fermé, non validé : refusé
    for t in 'CLOSED\nvalidé' 'OPEN\nstatut: à valider'; do
        FAKE_TICKET="$t" run shell 'REPOWARDEN_TICKET=12 gh repo edit --enable-auto-merge'
        [ "$status" -eq 2 ] || { echo "$t permis"; return 1; }
        [[ "$output" == *"#12 n'est pas ouvert et validé"* ]] || false
    done
    # Illisible (gh en échec, numéro invalide) : écriture sans preuve de ticket
    FAKE_TICKET="" FAKE_TICKET_RC=1 run shell 'REPOWARDEN_TICKET=12 gh repo edit --enable-auto-merge'
    [ "$status" -eq 2 ]
    [[ "$output" == *"#12 illisible"* ]] || false
    run shell 'REPOWARDEN_TICKET=abc gh repo edit --enable-auto-merge'
    [ "$status" -eq 2 ]
    [[ "$output" == *"illisible"* ]] || false
}

@test "garde gh : lignes composees, hors depot repowarden permis, anglais" {
    gh_simule
    run shell 'git status && gh issue create --title x'
    [ "$status" -eq 2 ]
    [[ "$output" == *"Rien de cette ligne"* ]] || false
    run shell "cd /tmp; '/usr/local/bin/gh' pr merge 3"
    [ "$status" -eq 0 ]
    run shell "cd $BATS_TEST_TMPDIR && gh pr merge 3"
    [ "$status" -eq 0 ]
    run shell 'echo x | gh pr merge 3'
    [ "$status" -eq 2 ]
    REPOWARDEN_LANG=en run shell 'gh repo edit --enable-auto-merge'
    [ "$status" -eq 2 ]
    [[ "$output" == *"without a ticket"* ]] || false
    REPOWARDEN_LANG=en run shell 'gh pr merge 3'
    [[ "$output" == *"maintainer's decision"* ]] || false
}

@test "garde gh : refus par defaut, toute commande gh hors lectures connues demande un ticket" {
    gh_simule
    for c in 'gh search issues panier' 'gh browse --no-browser' 'gh status' 'gh pr checks 3 --watch' \
        'gh run watch 1' 'gh issue close --help' 'gh secret list' 'gh label list'; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refusé : $output"; return 1; }
    done
    for c in 'gh issue close 12' 'gh issue reopen 12' 'gh issue delete 12 --yes' 'gh issue develop 12' \
        'gh issue transfer 12 o/autre' 'gh issue pin 12' 'gh issue lock 12' 'gh pr close 3' 'gh pr reopen 3' \
        'gh pr comment 3 --body x' 'gh pr review 3 --comment -b ok' 'gh gist create a.txt' \
        'gh codespace delete -c x' 'gh frobnique truc' 'gh repo frobnique'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"sans ticket"*"REPOWARDEN_TICKET=<n>"* ]] || false
        FAKE_TICKET='OPEN\nvalidé' run shell "REPOWARDEN_TICKET=12 $c"
        [ "$status" -eq 0 ] || { echo "REPOWARDEN_TICKET=12 $c refusé : $output"; return 1; }
    done
}

@test "garde : refus d'une modification de fichier existant -> rappel de repowarden carte" {
    mkdir -p lib
    echo x >lib/outil.sh
    run edit lib/outil.sh
    [ "$status" -eq 2 ]
    [[ "$output" == *"repowarden carte lib/outil.sh"* ]] || false
    # Chemin lu par jq sous Windows : CR final
    run claude Edit "$(jq -n --arg f "$PWD/lib/outil.sh"$'\r' '{file_path: $f, old_string: "a", new_string: "b"}')"
    [ "$status" -eq 2 ]
    [[ "$output" == *"repowarden carte lib/outil.sh"* ]] || false
    run claude Write "$(jq -n --arg f "$PWD/nouveau.sh" '{file_path: $f, content: "x"}')"
    [ "$status" -eq 2 ]
    [[ "$output" != *"repowarden carte"* ]] || false
}

@test "garde : valider un ticket (valide, statut) refuse, meme avec REPOWARDEN_TICKET" {
    gh_simule
    export FAKE_TICKET='OPEN\nvalidé'
    for c in 'repowarden ticket label 12 validé' 'repowarden ticket label 12 validé --remove' \
        'repowarden ticket label 12 "statut: en cours"' "repowarden ticket label 12 'statut: backlog' --remove" \
        'repowarden ticket-label 12 validé' 'REPOWARDEN_TICKET=12 repowarden ticket label 12 validé' \
        'REPOWARDEN_TICKET=12 repowarden ticket label 12 "statut: done"' 'git status && repowarden ticket label 12 validé'; do
        run shell "$c"
        [ "$status" -eq 2 ] || { echo "$c permis"; return 1; }
        [[ "$output" == *"valider un ticket est une décision du mainteneur"* ]] || false
    done
    for c in 'repowarden ticket label 12 "type: fix"' 'repowarden ticket label 12 "type: fix" --remove' \
        'repowarden ticket label --help' 'repowarden ticket comment 12 "validé ?"'; do
        run shell "$c"
        [ "$status" -eq 0 ] || { echo "$c refusé : $output"; return 1; }
    done
    REPOWARDEN_LANG=en run shell 'repowarden ticket label 12 validé'
    [ "$status" -eq 2 ]
    [[ "$output" == *"validating a ticket is the maintainer's decision"* ]] || false
    # Hors dépôt repowarden : tout est permis
    git init -q -b main "$BATS_TEST_TMPDIR/libre"
    run shell "cd $BATS_TEST_TMPDIR/libre && repowarden ticket label 12 validé"
    [ "$status" -eq 0 ]
}
