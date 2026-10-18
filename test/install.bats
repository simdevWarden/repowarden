#!/usr/bin/env bats
# install.sh : installation, désinstallation sûre, purge

load helpers

INSTALL="$BATS_TEST_DIRNAME/../install.sh"

setup() {
    setup_repo
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
    touch "$GIT_CONFIG_GLOBAL"
    export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
}

@test "install : --uninstall retire les hooks repowarden du depot" {
    git config --unset core.hooksPath
    "$INSTALL" >/dev/null
    [ -n "$(git config --local --get core.hooksPath)" ]
    run "$INSTALL" --uninstall
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hooks repowarden retirés"* ]] || false
    [ -z "$(git config --local --get core.hooksPath || true)" ]
}

@test "install : --uninstall ne touche pas aux hooks d'un autre outil (husky)" {
    git config core.hooksPath .husky/_
    run "$INSTALL" --uninstall
    [ "$status" -eq 0 ]
    [[ "$output" == *"n'est pas repowarden : laissé intact"* ]] || false
    [ "$(git config --local --get core.hooksPath)" = ".husky/_" ]
}

@test "install : --uninstall reconnait un ancien emplacement disparu" {
    git config core.hooksPath /chemin/qui/n-existe/plus/repowarden/hooks
    run "$INSTALL" --uninstall
    [[ "$output" == *"Hooks repowarden retirés"* ]] || false
}

@test "install : --uninstall --global --purge supprime les caches" {
    "$INSTALL" --global >/dev/null
    mkdir -p "$XDG_CACHE_HOME/repowarden/kubeconform"
    run "$INSTALL" --uninstall --global --purge
    [ "$status" -eq 0 ]
    [ -z "$(git config --global --get core.hooksPath || true)" ]
    [ ! -d "$XDG_CACHE_HOME/repowarden" ]
    [[ "$output" == *'rm -rf'* ]] || false
}

@test "install : --scan liste les depots encore branches, sans les modifier" {
    "$INSTALL" >/dev/null # dépôt de test branché localement
    mkdir -p "$BATS_TEST_TMPDIR/autre"
    git init -q "$BATS_TEST_TMPDIR/autre/projet-lefthook"
    printf 'remotes:\n  - git_url: https://github.com/x/repowarden\n' >"$BATS_TEST_TMPDIR/autre/projet-lefthook/lefthook.yml"
    git init -q "$BATS_TEST_TMPDIR/autre/sans-rapport"
    printf 'pre-commit: {}\n' >"$BATS_TEST_TMPDIR/autre/sans-rapport/lefthook.yml"
    run "$INSTALL" --uninstall --global --purge --scan "$BATS_TEST_TMPDIR"
    [[ "$output" == *"$REPO  →  git -C"* ]] || false
    [[ "$output" == *"projet-lefthook (lefthook)"* ]] || false
    [[ "$output" != *"sans-rapport"* ]] || false
    [ -n "$(git config --local --get core.hooksPath)" ] # liste seulement
}

@test "install : --purge sans --uninstall refuse" {
    run "$INSTALL" --purge
    [ "$status" -ne 0 ]
}

@test "install : --lang enregistre la langue et l'applique aux messages" {
    git config --unset core.hooksPath
    run "$BATS_TEST_DIRNAME/../install.sh" --lang en
    [ "$status" -eq 0 ]
    [ "$(git config --local --get repowarden.lang)" = en ]
    [[ "$output" == *"Message language: English"* ]] || false
    [[ "$output" == *"Hooks enabled"* ]] || false
    run "$BATS_TEST_DIRNAME/../install.sh" --lang de
    [ "$status" -ne 0 ]
}

@test "version : projet qui demande une version plus recente -> avertissement et commande de mise a jour" {
    initial_commit
    git switch -q -c feat/version
    # Version installée connue, même dans un clone sans tags : copie publiée en 4.9.3
    copie="$BATS_TEST_TMPDIR/repowarden-4.9.3"
    mkdir -p "$copie"
    cp -R "$HOOKS" "$copie/"
    sed 's/"version": "[^"]*"/"version": "4.9.3"/' "$BATS_TEST_DIRNAME/../package.json" >"$copie/package.json"
    git config core.hooksPath "$copie/hooks"
    git config repowarden.version 99.0.0
    echo a >a.txt && git add a.txt
    run git commit -m "feat: a"
    [ "$status" -eq 0 ] # avertissement seulement : la CI fait foi
    [[ "$output" == *"demande repowarden 99.0.0 ou plus récent"* ]] || false
}

@test "version : version inconnue (clone sans tags) -> aucune fausse alerte" {
    initial_commit
    git switch -q -c feat/version
    # Hooks d'une copie de repowarden sans .git : version 0.0.0-dev
    copie="$BATS_TEST_TMPDIR/repowarden-sans-tags"
    mkdir -p "$copie"
    cp -R "$HOOKS" "$BATS_TEST_DIRNAME/../package.json" "$copie/"
    git config core.hooksPath "$copie/hooks"
    git config repowarden.version 4
    echo a >a.txt && git add a.txt
    run git commit -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" != *"demande repowarden"* ]] || false
}

@test "version : version installee suffisante -> aucun message" {
    initial_commit
    git switch -q -c feat/version
    source "$HOOKS/lib/ui.sh"
    repowarden_version_r "$HOOKS/.."
    installed="$REPLY"
    for v in 1 "$installed" "v${installed%%.*}"; do
        git config repowarden.version "$v"
        echo "$v" >>a.txt && git add a.txt
        run git commit -m "feat: a"
        [ "$status" -eq 0 ]
        [[ "$output" != *"demande repowarden"* ]] || false
    done
}

# Faux dépôt de repowarden (racine d'une installation par clone), sans hooks
faux_repowarden() {
    RW="$BATS_TEST_TMPDIR/rw"
    git init -q -b main "$RW"
    rwgit() { git -C "$RW" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t "$@"; }
    rwgit commit -q --allow-empty -m "chore: init"
}

@test "version : racine de repowarden lue, meme avec le GIT_DIR d'un worktree du projet" {
    faux_repowarden
    rwgit tag v9.1.0
    initial_commit
    git tag v0.1.1
    source "$HOOKS/lib/ui.sh"
    # git exporte GIT_DIR aux hooks d'un worktree : il l'emportait sur -C
    export GIT_DIR="$REPO/.git" GIT_WORK_TREE="$REPO"
    repowarden_version_r "$RW"
    unset GIT_DIR GIT_WORK_TREE
    [ "$REPLY" = 9.1.0 ]
}

@test "version : release taguee sur le merge de main vue depuis develop, clone ancien non surestime" {
    faux_repowarden
    rwgit tag v1.0.0
    ancien="$(rwgit rev-parse HEAD)"
    rwgit switch -q -c develop
    # préversion égarée, plus haute mais plus ancienne : jamais retenue
    rwgit commit -q --allow-empty -m "chore: x"
    rwgit tag v9.0.0-next.1
    rwgit commit -q --allow-empty -m "feat: a"
    rwgit tag v1.1.0-next.1
    rwgit switch -q -c livraison/v1.1.0
    rwgit switch -q main
    rwgit merge -q --no-ff -m "chore(release): v1.1.0" livraison/v1.1.0
    rwgit tag v1.1.0
    rwgit switch -q develop
    rwgit commit -q --allow-empty -m "feat: b"
    source "$HOOKS/lib/ui.sh"
    repowarden_version_r "$RW"
    [ "$REPLY" = 1.1.0 ]
    rwgit switch -q --detach "$ancien"
    repowarden_version_r "$RW"
    [ "$REPLY" = 1.0.0 ]
}

@test "hooks : hook installe par lefthook ignore, meme avec une configuration lefthook" {
    initial_commit
    git switch -q -c feat/lefthook
    printf '#!/bin/sh\necho LEFTHOOK-LANCE\nlefthook run pre-commit "$@"\n' >.git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    printf 'pre-commit: {}\n' >lefthook.yml
    echo a >a.txt && git add a.txt lefthook.yml
    run git commit -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" != *"LEFTHOOK-LANCE"* ]] || false
    [[ "$output" == *"hook installé par lefthook, ignoré"* ]] || false
    [[ "$output" == *".repowarden/pre-commit"* ]] || false
}

@test "hooks : .repowarden/<hook> du projet lance a la place de lefthook" {
    initial_commit
    git switch -q -c feat/hook-projet
    mkdir -p .repowarden
    printf '#!/bin/sh\necho HOOK-PROJET-LANCE\n' >.repowarden/pre-commit
    chmod +x .repowarden/pre-commit
    echo a >a.txt && git add a.txt
    run git commit -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HOOK-PROJET-LANCE"* ]] || false
}
