#!/usr/bin/env bats
# Nommage des branches + protection de main

load helpers

setup() { setup_repo; initial_commit; }

@test "suggestion de nom de branche" {
    source "$HOOKS/lib/common.sh"
    [ "$(suggest_branch_name 'Mon_Truc')" = "feat/mon-truc" ]
    [ "$(suggest_branch_name 'Feat/Mon Truc')" = "feat/mon-truc" ]
    [ "$(suggest_branch_name 'bug/login')" = "fix/login" ]
    [ "$(suggest_branch_name 'doc/api')" = "docs/api" ]
    [ "$(suggest_branch_name 'wip/x')" = "feat/x" ]
}

@test "validite des noms de branche" {
    source "$HOOKS/lib/common.sh"
    for ok in feat/bean fix/user/login hotfix/x feat/a_b.c main master develop release/1.0; do
        branch_name_valid "$ok" || { echo "devrait être valide : $ok"; return 1; }
    done
    for ko in Feat/Bean wip/x test2 feat/ releases/x; do
        ! branch_name_valid "$ko" || { echo "devrait être invalide : $ko"; return 1; }
    done
}

@test "branches des bots acceptees par defaut (release-please, Dependabot, Renovate)" {
    source "$HOOKS/lib/common.sh"
    for ok in release-please--branches--main release-please--branches--main--components--app \
        dependabot/npm_and_yarn/vitest-5.0.3 renovate/lock-file-maintenance; do
        branch_name_valid "$ok" || { echo "devrait être valide : $ok"; return 1; }
    done
}

@test "repowarden.allowedBranches remplace les exceptions" {
    source "$HOOKS/lib/common.sh"
    git config repowarden.allowedBranches "main"
    cfg_load
    ! branch_name_valid develop
    branch_name_valid main
}

@test "post-checkout : avertit sans bloquer" {
    run git switch -c Mon_Truc
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nom de branche « Mon_Truc » non conforme"* ]] || false
    [[ "$output" == *"git branch -m feat/mon-truc"* ]] || false
    # aide courte : ni la liste des types, ni les exceptions (elles viennent au commit)
    [[ "$output" != *"Types"* ]] || false
    [ "$(printf '%s\n' "$output" | wc -l)" -le 5 ]
}

@test "pre-commit : refuse une branche mal nommee" {
    git switch -q -c Mon_Truc 2>/dev/null
    run git commit -q --allow-empty -m "feat: x"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Commit refusé : nom de branche non conforme"* ]] || false
    # la marche à suivre, jamais la désactivation de la règle
    [[ "$output" == *"git branch -m"* ]] || false
    [[ "$output" != *"repowarden.skip"* ]] || false
}

@test "pre-push : refuse une branche mal nommee" {
    git switch -q -c Bad 2>/dev/null
    git commit -q --no-verify --allow-empty -m "feat: x"
    run git push -q origin Bad
    [ "$status" -ne 0 ]
    [[ "$output" == *"Push refusé : nom de branche non conforme"* ]] || false
    [ -z "$(git ls-remote --heads origin Bad)" ]
}

@test "pre-push : suppression d'une branche mal nommee permise" {
    git switch -q -c Bad 2>/dev/null
    git commit -q --no-verify --allow-empty -m "feat: x"
    git push -q --no-verify origin Bad
    run git push -q origin --delete Bad
    [ "$status" -eq 0 ]
    [ -z "$(git ls-remote --heads origin Bad)" ]
}

@test "main : commit direct refuse apres le commit initial" {
    run git commit -q --allow-empty -m "fix: x"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Commit direct sur 'main' interdit"* ]] || false
    [[ "$output" != *"repowarden.skip"* ]] || false
}

@test "main : saut ponctuel git -c repowarden.skip, sans rien ecrire dans la config" {
    run git -c repowarden.skip="secrets protect-branch" commit -q --allow-empty -m "fix: x"
    [ "$status" -eq 0 ]
    [ "$(git config --get repowarden.skip)" = secrets ]
    run git commit -q --allow-empty -m "fix: y"
    [ "$status" -ne 0 ]
}

@test "main : repowarden.skip protect-branch l'autorise" {
    git config repowarden.skip "secrets protect-branch"
    run git commit -q --allow-empty -m "fix: x"
    [ "$status" -eq 0 ]
}

@test "pre-push : creation initiale de main permise, push direct ensuite refuse" {
    git push -q -u origin main
    git commit -q --no-verify --allow-empty -m "fix: x"
    run git push -q origin main
    [ "$status" -ne 0 ]
    [[ "$output" == *"Push direct refusé sur 'main'"* ]] || false
    [[ "$output" == *"git switch -c"* ]] || false
    [[ "$output" != *"repowarden.skip"* ]] || false
    [ "$(git rev-parse origin/main)" != "$(git rev-parse main)" ]
}

@test "pre-push : protectedBranches s'applique a develop, pas aux autres branches" {
    git config repowarden.protectedBranches "main develop"
    git push -q -u origin main
    git switch -q -c develop
    git push -q -u origin develop
    git commit -q --no-verify --allow-empty -m "fix: x"
    run git push -q origin develop
    [ "$status" -ne 0 ]
    [[ "$output" == *"Push direct refusé sur 'develop'"* ]] || false
    git switch -q -c feat/x
    run git push -q -u origin feat/x
    [ "$status" -eq 0 ]
}

@test "pre-push : repowarden.skip protect-branch autorise le push sur main" {
    git push -q -u origin main
    git commit -q --no-verify --allow-empty -m "fix: x"
    git config repowarden.skip "secrets protect-branch"
    run git push -q origin main
    [ "$status" -eq 0 ]
}

# Simule le merge d'une PR côté serveur, puis la suppression de sa branche
server_merge_and_delete() {
    local tmp="$BATS_TEST_TMPDIR/serveur"
    git clone -q -b main "$REMOTE" "$tmp"
    git -C "$tmp" config core.hooksPath /dev/null
    git -C "$tmp" config user.name serveur
    git -C "$tmp" config user.email serveur@example.com
    git -C "$tmp" merge -q --no-ff "origin/$1" -m "Merge $1"
    git -C "$tmp" push -q origin main
    git -C "$tmp" push -q origin --delete "$1"
    rm -rf "$tmp"
}

push_branch() {
    git switch -q -c "$1"
    echo "$1" >"travail-${1//\//-}.txt"
    git add -A
    git commit -q -m "feat: travail sur $1"
    git push -q -u origin "$1"
}

@test "post-merge : branche mergee et supprimee sur le serveur -> supprimee en local" {
    git push -q -u origin main
    push_branch feat/x
    server_merge_and_delete feat/x
    git switch -q main
    run git pull -q
    [ "$status" -eq 0 ]
    [[ "$output" == *"Branche locale supprimée"*"feat/x"* ]] || false
    ! git show-ref -q --verify refs/heads/feat/x
}

@test "post-merge : branche supprimee mais non integree -> conservee" {
    git push -q -u origin main
    push_branch feat/y
    git push -q origin --delete feat/y # supprimée sans merge
    git switch -q main
    git commit -q --allow-empty -m "fix: autre travail" --no-verify
    git push -q origin main --no-verify
    git reset -q --hard HEAD~1
    run git pull -q
    [[ "$output" == *"feat/y : supprimée sur le serveur mais des modifications manquent"* ]] || false
    git show-ref -q --verify refs/heads/feat/y
}

@test "post-merge : desactivable (skip prune-branches)" {
    git config repowarden.skip "secrets prune-branches"
    git push -q -u origin main
    push_branch feat/z
    server_merge_and_delete feat/z
    git switch -q main
    git pull -q
    git show-ref -q --verify refs/heads/feat/z
}

# Simule un merge squash de la PR côté serveur, puis la suppression de sa branche
server_squash_and_delete() {
    local tmp="$BATS_TEST_TMPDIR/serveur"
    git clone -q -b main "$REMOTE" "$tmp"
    git -C "$tmp" config core.hooksPath /dev/null
    git -C "$tmp" config user.name serveur
    git -C "$tmp" config user.email serveur@example.com
    git -C "$tmp" merge -q --squash "origin/$1"
    git -C "$tmp" commit -q -m "feat: $1 (#1)"
    git -C "$tmp" push -q origin main
    git -C "$tmp" push -q origin --delete "$1"
    rm -rf "$tmp"
}

@test "post-merge : branche mergee en squash -> supprimee en local" {
    git push -q -u origin main
    git switch -q -c feat/sq
    echo a >a.txt && git add a.txt && git commit -q -m "feat: a"
    echo b >b.txt && git add b.txt && git commit -q -m "feat: b"
    git push -q -u origin feat/sq
    server_squash_and_delete feat/sq
    git switch -q main
    run git pull -q
    [ "$status" -eq 0 ]
    [[ "$output" == *"mergée en squash"*"feat/sq"* ]] || false
    ! git show-ref -q --verify refs/heads/feat/sq
}

@test "post-merge : squash puis travail local supplementaire -> conservee" {
    git push -q -u origin main
    git switch -q -c feat/sq2
    echo a >a.txt && git add a.txt && git commit -q -m "feat: a"
    git push -q -u origin feat/sq2
    server_squash_and_delete feat/sq2
    echo c >c.txt && git add c.txt && git commit -q --no-verify -m "feat: travail non poussé"
    git switch -q main
    run git pull -q
    git show-ref -q --verify refs/heads/feat/sq2
}

@test "en anglais : commit direct sur main et branche mal nommee expliques en anglais" {
    export REPOWARDEN_LANG=en
    run git commit -q --allow-empty -m "fix: x"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Direct commit on 'main' forbidden"* ]] || false
    [[ "$output" != *"repowarden.skip"* ]] || false
    git switch -q -c Bad 2>/dev/null
    git commit -q --no-verify --allow-empty -m "feat: x"
    run git push -q origin Bad
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid branch name"* ]] || false
    [[ "$output" == *"new feature"* ]] || false
    [[ "$output" != *"repowarden.skip"* ]] || false
}
