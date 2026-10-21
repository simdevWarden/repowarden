#!/usr/bin/env bats
# Fonctions ajoutées sans commentaire juste au-dessus : signalées au
# pre-commit et en CI (ci/check.sh comments), sans jamais bloquer

load helpers

CHECK="$BATS_TEST_DIRNAME/../ci/check.sh"

setup() {
    setup_repo
    git config repowarden.skip "secrets format"
    initial_commit
    git switch -q -c feat/x
}

# Base commune : fonctions existantes non commentées (jamais signalées)
base_existante() {
    printf '#!/usr/bin/env bash\nvieille() {\n    :\n}\n' >outil.sh
    printf 'def ancienne():\n    pass\n' >app.py
    git add -A
    git commit -q --no-verify -m "chore: base"
}

@test "commentaires : pre-commit, fonction shell ajoutee sans commentaire -> signalee, commit passe" {
    base_existante
    printf '\n# Dit bonjour : premier contact avec l utilisateur\nbonne() { :; }\nmauvaise() { :; }\n' >>outil.sh
    git add outil.sh
    run git commit -q -m "feat: ajout"
    [ "$status" -eq 0 ]
    [[ "$output" == *"outil.sh:8 : fonction mauvaise sans commentaire juste au-dessus"* ]] || false
    [[ "$output" == *"1 fonction(s) ajoutée(s) sans commentaire"* ]] || false
    [[ "$output" != *"bonne"* ]] || false
    [[ "$output" != *"vieille"* ]] || false
}

@test "commentaires : pre-commit, script sans extension avec shebang -> signale" {
    base_existante
    mkdir -p bin
    printf '#!/bin/sh\nz() { :; }\n' >bin/outil
    printf 'q() { :; }\n' >notes.txt
    git add -A
    run git commit -q -m "feat: outil"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bin/outil:2 : fonction z sans"* ]] || false
    [[ "$output" != *"notes.txt"* ]] || false
}

@test "commentaires : pre-commit, fonctions commentees -> rien, seule la non commentee signalee" {
    base_existante
    printf '\n# Range les fichiers : evite les doublons\nrange() { :; }\n# shellcheck disable=SC2034\n# Vide le cache, sinon il grossit sans fin\nvide() { :; }\n# shellcheck disable=SC2034\ndirective() { :; }\n' >>outil.sh
    git add outil.sh
    run git commit -q -m "feat: commentees"
    [ "$status" -eq 0 ]
    # une directive d'outil seule n'explique rien
    [[ "$output" == *"outil.sh:12 : fonction directive sans"* ]] || false
    [[ "$output" == *"1 fonction(s) ajoutée(s) sans commentaire"* ]] || false
}

@test "commentaires : pre-commit, fonction existante modifiee ou deplacee -> jamais signalee" {
    base_existante
    printf '#!/usr/bin/env bash\nvieille () { echo change; }\nnouvelle() { :; }\n' >outil.sh
    git mv app.py ailleurs.py
    git add -A
    run git commit -q -m "refactor: retouche"
    [ "$status" -eq 0 ]
    [[ "$output" == *"outil.sh:3 : fonction nouvelle sans"* ]] || false
    [[ "$output" != *"vieille"* ]] || false
    [[ "$output" != *"ancienne"* ]] || false
}

@test "commentaires : pre-commit, Python -> docstring, commentaire ou decorateur reconnus" {
    base_existante
    cat >>app.py <<'PY'

@deco
def sans(a,
         b) -> int:
    return a


def avec():
    '''Docstring : ce que fait la fonction et pourquoi.'''


# Commentaire au-dessus du decorateur
@deco
async def commentee():
    pass
PY
    git add app.py
    run git commit -q -m "feat: python"
    [ "$status" -eq 0 ]
    [[ "$output" == *"app.py:5 : fonction sans sans commentaire"* ]] || false
    [[ "$output" != *"fonction avec "* ]] || false
    [[ "$output" != *"fonction commentee "* ]] || false
}

@test "commentaires : pre-commit, JavaScript et TypeScript" {
    base_existante
    cat >a.ts <<'TS'
export function f(a: number): number { return a }
/** Double la valeur : utilise par le panier */
export async function g() {}
const h = async (x: string): Promise<void> => {}
// Identite, pour les tests
const k = (x) => x
const v = 3
TS
    git add a.ts
    run git commit -q -m "feat: ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"a.ts:1 : fonction f sans"* ]] || false
    [[ "$output" == *"a.ts:4 : fonction h sans"* ]] || false
    [[ "$output" != *"fonction g "* ]] || false
    [[ "$output" != *"fonction k "* ]] || false
    [[ "$output" != *"fonction v "* ]] || false
}

@test "commentaires : skip = comments -> rien" {
    base_existante
    printf 'mauvaise() { :; }\n' >>outil.sh
    git add outil.sh
    run git commit -q -m "feat: ajout"
    [[ "$output" == *"fonction mauvaise sans"* ]] || false
    git config repowarden.skip "secrets format comments"
    printf 'autre() { :; }\n' >>outil.sh
    git add outil.sh
    run git commit -q -m "feat: autre"
    [ "$status" -eq 0 ]
    [[ "$output" != *"sans commentaire"* ]] || false
}

@test "commentaires : CI (check.sh comments) -> signale le nouveau code, sans echec" {
    mkdir -p "$BATS_TEST_TMPDIR/nohooks"
    git config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
    base_existante
    export REPOWARDEN_BASE="$(git rev-parse HEAD)" REPOWARDEN_BRANCH=feat/x
    printf 'mauvaise() { :; }\n' >>outil.sh
    git commit -q -am "feat: ajout"
    REPOWARDEN_STRICT=true run "$CHECK" comments
    [ "$status" -eq 0 ]
    [[ "$output" == *"outil.sh:5 : fonction mauvaise sans commentaire"* ]] || false
    [[ "$output" != *"vieille"* ]] || false

    printf '# Commentee : rien a signaler\nbonne() { :; }\n' >>outil.sh
    git commit -q -am "feat: bonne"
    export REPOWARDEN_BASE="$(git rev-parse HEAD~1)"
    run "$CHECK" comments
    [ "$status" -eq 0 ]
    [[ "$output" == *"Chaque fonction ajoutée est commentée"* ]] || false
}
