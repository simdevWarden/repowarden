#!/usr/bin/env bats
# ci/release-tag.sh : tag publié sur npm, le dernier vX.Y.Z joignable depuis HEAD
# (préversions et vX.Y exclues). Dépôt jetable, pas de réseau.

load helpers

SCRIPT="$BATS_TEST_DIRNAME/../ci/release-tag.sh"

setup() {
    setup_repo
    mkdir -p "$BATS_TEST_TMPDIR/nohooks"
    git config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
    git config --unset repowarden.skip
    initial_commit
}

# Commit vide suivant, pour poser des tags sur des commits distincts
commit_suivant() {
    git commit -q --allow-empty -m "fix: $1"
}

@test "release-tag : v4 et v4.17.5 sur le même commit -> v4.17.5" {
    git tag v4
    git tag v4.17.5
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "v4.17.5" ]
}

@test "release-tag : préversion plus récente non retenue -> dernier stable" {
    git tag v4.17.5
    commit_suivant "préversion"
    git tag v4.17.6-next.1
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "v4.17.5" ]
}

@test "release-tag : v4.17 seul non retenu -> erreur, rien à publier" {
    git tag v4.17
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"aucun tag vX.Y.Z"* ]] || false
}
