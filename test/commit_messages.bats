#!/usr/bin/env bats
# commit-msg + prepare-commit-msg + messages des commits poussés (pre-push)

load helpers

setup() { setup_repo; initial_commit; }

@test "commit-msg : message conforme accepte" {
    git switch -q -c feat/x
    run git commit -q --allow-empty -m "fix: corrige un truc"
    [ "$status" -eq 0 ]
    [ "$(subject)" = "fix: corrige un truc" ]
}

@test "commit-msg : message invalide refuse avec l'aide" {
    git switch -q -c wip-x 2>/dev/null
    git config repowarden.skip "secrets branch-name"
    run git commit -q --allow-empty -m "n'importe quoi"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Message de commit invalide"* ]] || false
    [[ "$output" == *"nouvelle fonctionnalité"* ]] || false
}

@test "commit-msg : premiere ligne > 72 caracteres refusee" {
    git switch -q -c feat/x
    run git commit -q --allow-empty -m "fix: $(printf 'a%.0s' {1..80})"
    [ "$status" -ne 0 ]
    [[ "$output" == *"trop longue"* ]] || false
}

@test "prepare-commit-msg : prefixe deduit de la branche" {
    git switch -q -c feat/bean
    git commit -q --allow-empty -m "ajoute le bean"
    [ "$(subject)" = "feat(bean): ajoute le bean" ]
}

@test "prepare-commit-msg : alias de branche (bugfix -> fix)" {
    git switch -q -c bugfix/timeout
    git commit -q --allow-empty -m "corrige"
    [ "$(subject)" = "fix(timeout): corrige" ]
}

@test "prepare-commit-msg : scope trop long omis" {
    git switch -q -c fix/un-sujet-vraiment-tres-long
    git commit -q --allow-empty -m "corrige"
    [ "$(subject)" = "fix: corrige" ]
}

@test "prepare-commit-msg : message deja conforme inchange" {
    git switch -q -c feat/bean
    git commit -q --allow-empty -m "docs: readme"
    [ "$(subject)" = "docs: readme" ]
}

@test "prepare-commit-msg : amend sans double prefixe" {
    git switch -q -c feat/bean
    git commit -q --allow-empty -m "ajoute"
    GIT_EDITOR=true git commit -q --amend --allow-empty
    [ "$(subject)" = "feat(bean): ajoute" ]
}

@test "repowarden.skip true desactive tout" {
    git config repowarden.skip true
    run git commit -q --allow-empty -m "n'importe quoi"
    [ "$status" -eq 0 ]
}

@test "commit-msg : signatures d'agent IA retirees du message, identite d'agent refusee" {
    git switch -q -c feat/x
    run git commit -q --allow-empty -m "feat: ajoute un truc" -m "Pourquoi." \
        -m "Co-Authored-By: Claude Opus <noreply@anthropic.com>
🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-authored-by: Alice <alice@example.com>"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Signature d'agent IA retirée"* ]] || false
    msg="$(git log -1 --format=%B)"
    echo "message : $msg"
    [[ "$msg" != *anthropic* && "$msg" != *"Generated with"* ]] || false
    [[ "$msg" == *"Co-authored-by: Alice <alice@example.com>"* ]] || false
    # auteur agent : refuse
    GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com \
        run git commit -q --allow-empty -m "fix: autre"
    [ "$status" -ne 0 ]
    [[ "$output" == *"agent IA"* ]] || false
    # reglage : agents autorises
    git config repowarden.allowAgentSignatures true
    GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com \
        run git commit -q --allow-empty -m "fix: autorise" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
    [ "$status" -eq 0 ]
    [[ "$(git log -1 --format=%B)" == *anthropic* ]] || false
}

@test "commit-msg : type inconnu sur une branche typee -> refuse avec le type le plus proche, pas enveloppe" {
    git switch -q -c feat/panier
    run git commit -q --allow-empty -m "doc: essai"
    [ "$status" -ne 0 ]
    [[ "$output" == *"docs: essai"* ]] || false
    [ "$(subject)" = "chore: init" ]
    run git commit -q --allow-empty -m "Feat(panier): ajoute"
    [ "$status" -ne 0 ]
    [[ "$output" == *"feat(panier): ajoute"* ]] || false
}

@test "commit-msg : description vide refusee, pas enveloppee" {
    git switch -q -c feat/panier
    run git commit -q --allow-empty -m "fix:"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Description manquante"* ]] || false
    [ "$(subject)" = "chore: init" ]
}

@test "prepare-commit-msg : message libre prefixe, corps et references intacts" {
    git switch -q -c feat/panier
    printf 'ajoute le panier\n\nPourquoi : les clients le demandent.\n\nTicket : #12\n' >"$BATS_TEST_TMPDIR/msg"
    git commit -q --allow-empty -F "$BATS_TEST_TMPDIR/msg"
    [ "$(subject)" = "feat(panier): ajoute le panier" ]
    [ "$(git log -1 --format=%b)" = "$(printf 'Pourquoi : les clients le demandent.\n\nTicket : #12')" ]
}

@test "commit-msg : point final retire (meme regle que git cc), majuscule initiale permise" {
    git switch -q -c feat/panier
    run git commit -q --allow-empty -m "docs: README à jour."
    [ "$status" -eq 0 ]
    [ "$(subject)" = "docs: README à jour" ]
}

@test "commit-msg : refus en anglais sans texte francais" {
    git switch -q -c feat/panier
    REPOWARDEN_LANG=en run git commit -q --allow-empty -m "doc: essai"
    [ "$status" -ne 0 ]
    [[ "$output" == *"docs: essai"* ]] || false
    [[ "$output" != *"inconnu"* && "$output" != *"Astuce"* ]] || false
}

# Commit créé hors hooks (autre outil, rebase avec reword sans hooks…)
commit_sans_hooks() { git -c core.hooksPath=/dev/null commit -q --allow-empty -m "$1"; }

@test "pre-push : message invalide dans la plage poussee refuse, commit designe" {
    git switch -q -c feat/x
    commit_sans_hooks "feat: correct"
    commit_sans_hooks "mauvais message sans type"
    bad="$(git rev-parse --short=7 HEAD)"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"Push refusé : message de commit non conforme"* ]] || false
    [[ "$output" == *"$bad « mauvais message sans type » : format attendu"* ]] || false
    [[ "$output" == *"git rebase -i $bad^"* ]] || false
    [ -z "$(git ls-remote --heads origin feat/x)" ]
}

@test "pre-push : commit fixup! pousse refuse, meme regle que la CI" {
    git switch -q -c feat/x
    git push -q origin feat/x
    commit_sans_hooks "fixup! chore: init"
    run git push -q origin feat/x
    [ "$status" -ne 0 ]
    [[ "$output" == *"commit à squasher"* ]] || false
}

@test "pre-push : commit deja sur le remote non recontrole" {
    git switch -q -c feat/x
    commit_sans_hooks "mauvais message"
    git push -q --no-verify origin feat/x
    commit_sans_hooks "fix: correct"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
}

@test "pre-push : repowarden.skip commit-msg laisse passer" {
    git switch -q -c feat/x
    commit_sans_hooks "mauvais message"
    git config repowarden.skip "secrets commit-msg"
    run git push -q origin feat/x
    [ "$status" -eq 0 ]
}

@test "pre-push : rien a pousser, message exact" {
    git switch -q -c feat/x
    git push -q origin feat/x
    run git push origin feat/x
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rien à pousser"* ]] || false
    [[ "$output" != *"suppression"* ]] || false
}

@test "commit-msg : HEAD detachee, aide propre sans conseil de branche" {
    git switch -q --detach
    run git commit -q --allow-empty -m "essai"
    [ "$status" -ne 0 ]
    [[ "$output" == *"HEAD détachée"* ]] || false
    [[ "$output" != *"nomme ta branche"* ]] || false
    REPOWARDEN_LANG=en run git commit -q --allow-empty -m "essai"
    [[ "$output" == *"Detached HEAD"* ]] || false
    [[ "$output" != *"name your branch"* ]] || false
}
