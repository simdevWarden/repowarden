#!/usr/bin/env bats
# repowarden npm-publication : premiere publication depuis le poste (npm
# conduit sa propre validation), puis publication de confiance. npm et gh sont
# simules par des scripts en tete du PATH qui journalisent leurs arguments ;
# node reste le vrai.

load helpers

PKG="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"

setup() {
    setup_repo
    printf '{\n  "name": "@own/paquet",\n  "version": "0.0.0-dev"\n}\n' >package.json
    initial_commit
    FAKE="$BATS_TEST_TMPDIR/fake"
    export CALLS="$BATS_TEST_TMPDIR/calls.log"
    export STATE="$BATS_TEST_TMPDIR/state"
    mkdir -p "$FAKE" "$STATE"
    : >"$CALLS"
    cat >"$FAKE/npm" <<'EOF'
#!/usr/bin/env bash
case "$1" in --version) echo 11.19.1; exit 0 ;; esac
echo "npm $* [cwd=$PWD]" >>"$CALLS"
case "$1" in
    whoami) echo testeur ;;
    profile) echo '{"tfa":{"mode":"auth-and-writes"}}' ;;
    view)
        [ -f "$STATE/publie" ] || { echo "npm error 404" >&2; exit 1; }
        if [ "$3" = version ]; then cat "$STATE/publie"; else echo "$2"; fi ;;
    pkg)
        v="${3#version=}"
        node -e 'const f="./package.json",p=require(f);p.version=process.argv[1];require("fs").writeFileSync(f,JSON.stringify(p,null,2))' "$v" ;;
    publish)
        v="$(node -p 'require("./package.json").version')"
        echo "publication version=$v [cwd=$PWD]" >>"$CALLS"
        [ -z "${NPM_PUBLISH_FAIL:-}" ] || { echo "npm error E401" >&2; exit 1; }
        echo "$v" >"$STATE/publie" ;;
    trust) [ "$2" = list ] && echo '[]' ;;
    token)
        [ "$2" = list ] && echo '[]'
        [ "$2" = create ] && exit 1 ;;
esac
exit 0
EOF
    cat >"$FAKE/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$CALLS"
case "$1 $2" in
    "release view")
        [ -z "${GH_RELEASE_ERR:-}" ] || { echo "$GH_RELEASE_ERR" >&2; exit 1; }
        [ -n "${GH_RELEASE:-}" ] || { echo "release not found" >&2; exit 1; }
        echo "$GH_RELEASE" ;;
    "repo clone")
        mkdir -p "$4"
        printf '{\n  "name": "@own/paquet",\n  "version": "0.0.0-dev"\n}\n' >"$4/package.json" ;;
    "secret list") ;;
    "repo view")
        [ -z "${GH_REPO_ABSENT:-}" ] || { echo "GraphQL: Could not resolve to a Repository" >&2; exit 1; }
        echo main ;;
esac
exit 0
EOF
    chmod +x "$FAKE/npm" "$FAKE/gh"
    export PATH="$FAKE:$PATH"
}

npm_publication() {
    run bash "$PKG/bin/npm-publish" --repo own/paquet "$@" </dev/null
}

# Aucun appel journalise ne correspond (un « ! grep » isole ne fait pas echouer un test)
absent() { ! grep -q "$1" "$CALLS"; }

@test "npm-publication : paquet absent, publie la derniere release depuis le poste" {
    export GH_RELEASE=v1.2.3
    npm_publication
    [ "$status" -eq 0 ]
    # Publication dans le clone du tag, à la version de la release
    grep -q "^gh repo clone own/paquet .* --branch v1.2.3" "$CALLS"
    ligne="$(grep '^publication ' "$CALLS")"
    [[ "$ligne" == "publication version=1.2.3 "* ]] || false
    [[ "$ligne" != *"[cwd=$REPO]" ]] || false
    grep -q '^npm publish --access public' "$CALLS"
    # Clone temporaire effacé
    clone="${ligne##*\[cwd=}"
    clone="${clone%\]}"
    [ ! -e "$clone" ]
    # Puis la publication de confiance et la variable
    grep -q '^npm trust github @own/paquet' "$CALLS"
    grep -q '^gh variable set REPOWARDEN_NPM' "$CALLS"
    # Ni jeton ni secret
    absent '^npm token create'
    absent '^gh secret set'
}

@test "npm-publication : aucune release, rien publie ni configure" {
    npm_publication
    [ "$status" -eq 0 ]
    [[ "$output" == *"release"* ]] || false
    absent '^npm publish'
    absent '^gh repo clone'
    absent '^gh variable set'
    absent '^npm trust github'
}

@test "npm-publication : echec de la publication, rien d'autre configure" {
    export GH_RELEASE=v1.2.3 NPM_PUBLISH_FAIL=1
    npm_publication
    [ "$status" -eq 1 ]
    grep -q '^npm publish' "$CALLS"
    absent '^npm trust github'
    absent '^gh variable set'
}

@test "npm-publication : --dry-run ne publie rien" {
    export GH_RELEASE=v1.2.3
    npm_publication --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"1.2.3"* ]] || false
    absent '^npm publish'
    absent '^gh variable set'
    absent '^npm trust github'
}

@test "npm-publication : paquet deja publie, ni clone ni publication" {
    export GH_RELEASE=v1.2.3
    echo 1.0.0 >"$STATE/publie"
    npm_publication
    [ "$status" -eq 0 ]
    absent '^gh repo clone'
    absent '^npm publish'
    grep -q '^npm trust github @own/paquet' "$CALLS"
    grep -q '^gh variable set REPOWARDEN_NPM' "$CALLS"
}

@test "npm-publication : depot mal forme, erreur avant toute action" {
    export GH_RELEASE=v1.2.3
    npm_publication --repo "own/paquet,"
    [ "$status" -eq 1 ]
    [[ "$output" == *"own/paquet,"* ]] || false
    [[ "$output" == *"propri"* ]] || false
    absent '^npm '
    absent '^gh '
}

@test "npm-publication : depot inaccessible, erreur avant toute action" {
    export GH_RELEASE=v1.2.3 GH_REPO_ABSENT=1
    npm_publication
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not resolve to a Repository"* ]] || false
    [[ "$output" == *"own/paquet"* ]] || false
    absent '^npm '
    absent '^gh release'
}

@test "npm-publication : erreur de gh release view, pas prise pour aucune release" {
    export GH_RELEASE_ERR="error connecting to api.github.com"
    npm_publication
    [ "$status" -eq 1 ]
    [[ "$output" == *"error connecting to api.github.com"* ]] || false
    [[ "$output" != *"Aucune release"* ]] || false
    absent '^npm publish'
    absent '^gh repo clone'
    absent '^gh variable set'
    absent '^npm trust github'
}
