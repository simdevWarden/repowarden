# Helpers communs aux tests bats : chaque test tourne dans un dépôt jetable
# avec les hooks du dépôt repowarden courant.

HOOKS="$(cd "$BATS_TEST_DIRNAME/../hooks" && pwd -P)"
# Messages attendus en français (les tests anglais fixent REPOWARDEN_LANG=en)
export REPOWARDEN_LANG=fr
# Entrée standard hors du terminal, comme en CI : lancés depuis un terminal,
# install.sh, cc, npm-publication… poseraient leurs questions ([ -t 0 ]) et
# le test attendrait une réponse invisible. Un test qui veut une entrée la
# donne lui-même (<<<, REPOWARDEN_INTERACTIF).
exec </dev/null

setup_repo() {
    REPO="$BATS_TEST_TMPDIR/repo"
    REMOTE="$BATS_TEST_TMPDIR/remote.git"
    git init -q --bare -b main "$REMOTE" # indépendant de init.defaultBranch
    git init -q -b main "$REPO"
    cd "$REPO" || return 1
    git config user.name test
    git config user.email test@example.com
    git config commit.gpgsign false
    git config core.hooksPath "$HOOKS"
    git config repowarden.skip secrets # gitleaks pas forcément installé
    git remote add origin "$REMOTE"
}

# Premier commit sur main (autorisé : pas encore de HEAD)
initial_commit() {
    echo init >README.md
    git add README.md
    git commit -q -m "chore: init"
}

# Module Go minimal avec un test qui passe (TEST_OK=1) ou échoue
go_project() {
    printf 'module x\n\ngo 1.21\n' >go.mod
    write_go_test "$1"
}

write_go_test() {
    local expected=1
    [ "$1" = fail ] && expected=2
    printf 'package main\n\nimport "testing"\n\nfunc TestX(t *testing.T) {\n\tif 1 != %s {\n\t\tt.Fatal("ko")\n\t}\n}\n' "$expected" >x_test.go
}

subject() { git log -1 --format=%s "${1:-HEAD}"; }

require() {
    command -v "$1" >/dev/null 2>&1 || skip "$1 absent"
}

# Garde-fou des agents IA branché dans le dépôt de test : sur un poste où
# Claude Code ou opencode est installé, statut ne le réclame plus
garde_branche() {
    mkdir -p .claude
    printf '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit|Bash","hooks":[{"type":"command","command":"repowarden garde --format claude"}]}]}}\n' >.claude/settings.json
}

# Poste de test avec Claude Code (~/.claude), garde-fou branché nulle part
agent_sans_garde() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.claude"
    unset CLAUDE_CONFIG_DIR OPENCODE_CONFIG_DIR XDG_CONFIG_HOME
}
