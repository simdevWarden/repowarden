#!/usr/bin/env bats
# Tag publié sur npm en mode sans tag : la ligne TAG="$(git describe …)" de
# npm-publish.yml, lue dans le workflow lui-même (une copie pourrait diverger).
# Dernier vX.Y.Z joignable depuis HEAD ; préversions et vX.Y exclues.
# Dépôt jetable, pas de réseau.

load helpers

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/npm-publish.yml"

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

# Affiche la ligne de motif telle qu'écrite dans le workflow ; échoue si elle n'y est pas
ligne_motif() {
    local ligne
    ligne="$(grep -m1 -E '^[[:space:]]*TAG="\$\(git describe ' "$WORKFLOW" | sed -e 's/^[[:space:]]*//')"
    if [ -z "$ligne" ]; then
        echo "ligne TAG=\"\$(git describe …)\" introuvable dans npm-publish.yml" >&2
        return 1
    fi
    printf '%s\n' "$ligne"
}

# Exécute cette ligne comme GitHub (bash -e, pipefail) et affiche la valeur de TAG
release_a_publier() {
    local ligne
    ligne="$(ligne_motif)" || return 1
    bash -eo pipefail -c "$ligne; printf '%s' \"\$TAG\"" 2>/dev/null
}

@test "release-tag : la ligne de motif existe dans npm-publish.yml" {
    run ligne_motif
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "release-tag : v4 et v4.17.5 sur le meme commit -> v4.17.5" {
    git tag v4
    git tag v4.17.5
    run release_a_publier
    [ "$status" -eq 0 ]
    [ "$output" = "v4.17.5" ]
}

@test "release-tag : preversion plus recente non retenue -> dernier stable" {
    git tag v4.17.5
    commit_suivant "préversion"
    git tag v4.17.6-next.1
    run release_a_publier
    [ "$status" -eq 0 ]
    [ "$output" = "v4.17.5" ]
}

@test "release-tag : v4.17 seul non retenu -> erreur, rien a publier" {
    git tag v4.17
    run release_a_publier
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}
