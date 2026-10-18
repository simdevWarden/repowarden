#!/usr/bin/env bats
# Assistant de commit (git cc) : en-tête, corps, pied

load helpers

CC="$BATS_TEST_DIRNAME/../bin/commit"

setup() {
    setup_repo
    initial_commit
    git switch -q -c feat/panier
    echo x >a.txt
    git add a.txt
}

# Réponses, une par ligne : type, scope, majeur [, ce qui change], description,
# corps…, références, confirmation
answer() { printf '%s\n' "$@" | "$CC" 2>&1; }

@test "assistant : type et scope proposes d'apres la branche" {
    run answer "" "" "" "ajoute le panier" "" "" ""
    [ "$status" -eq 0 ]
    [ "$(subject)" = "feat(panier): ajoute le panier" ]
}

@test "assistant : corps et references dans le message" {
    run answer "" "" "" "ajoute le panier" "Le client garde ses articles." "" "Closes #12" ""
    [ "$status" -eq 0 ]
    git log -1 --format=%B >msg
    grep -qx 'Le client garde ses articles.' msg
    grep -qx 'Closes #12' msg
}

@test "assistant : choix du type par numero, sans scope" {
    run answer "2" "-" "" "corrige le total" "" "" ""
    [ "$(subject)" = "fix: corrige le total" ]
}

@test "assistant : changement majeur -> ! et BREAKING CHANGE" {
    run answer "" "" "o" "le format de sortie change" "change l'API du panier" "" "" ""
    [ "$(subject)" = "feat(panier)!: change l'API du panier" ]
    git log -1 --format=%B | grep -qx 'BREAKING CHANGE: le format de sortie change'
}

@test "assistant : changement majeur sans description reelle -> redemande" {
    run answer "" "" "o" "RAS" "court" "le format de sortie change" "change l'API" "" "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"10 caractères au moins"* ]] || false
    git log -1 --format=%B | grep -qx 'BREAKING CHANGE: le format de sortie change'
}

@test "assistant : premier commit du depot -> pas de question sur l'incompatibilite" {
    rm -rf .git
    git init -q -b main
    git config user.name test
    git config user.email test@example.com
    git config core.hooksPath /dev/null
    git add a.txt
    run answer "" "" "initialise le projet" "" "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Premier commit du dépôt"* ]] || false
    [ "$(subject)" = "feat: initialise le projet" ]
    # « - » sans scope proposé : aucun scope (et non « (-) »)
    rm -rf .git
    git init -q -b main
    git config user.name test
    git config user.email test@example.com
    git config core.hooksPath /dev/null
    git add a.txt
    run answer chore - "initialise le projet" "" "" ""
    [ "$(subject)" = "chore: initialise le projet" ]
}

@test "assistant : touches parasites (Echap, fleches) et point final ignores" {
    run answer $'1\033' $'\033[A' "" "ajoute le panier." "" "" ""
    [ "$status" -eq 0 ]
    [ "$(subject)" = "feat(panier): ajoute le panier" ]
}

@test "assistant : en anglais (REPOWARDEN_LANG=en), reponses y/yes acceptees" {
    export REPOWARDEN_LANG=en
    run answer "" "" "y" "the cart response is now an object" "change the cart API" "" "" "y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Type of change"* ]] || false
    [[ "$output" == *"Breaking change?"* ]] || false
    [[ "$output" == *"Commit created."* ]] || false
    [ "$(subject)" = "feat(panier)!: change the cart API" ]
}

@test "plateforme detectee : vocabulaire et exemples de references" {
    for cas in "git@github.com:a/b.git|github|PR|Closes #12" \
        "https://gitlab.interne.fr/a/b.git|gitlab|MR|Closes #12, !34" \
        "git@bitbucket.org:a/b.git|bitbucket|PR|PROJ-42" \
        "https://codeberg.org/a/b.git|gitea|PR|Closes #12" \
        "ssh://git.exemple.fr/a/b.git|other|PR|Closes #12"; do
        IFS='|' read -r url attendu pr refs <<<"$cas"
        git remote set-url origin "$url"
        (
            unset GITHUB_ACTIONS GITLAB_CI BITBUCKET_BUILD_NUMBER GITEA_ACTIONS FORGEJO_ACTIONS
            source "$HOOKS/lib/common.sh"
            [ "$FORGE|$FORGE_PR|$FORGE_REFS" = "$attendu|$pr|$refs" ] || { echo "$url -> $FORGE|$FORGE_PR|$FORGE_REFS"; exit 1; }
        )
    done
    git config repowarden.forge gitlab
    (unset GITHUB_ACTIONS; source "$HOOKS/lib/common.sh"; [ "$FORGE" = gitlab ])
}

@test "assistant : sur main, branche proposee aussitot ; oui/non invalide redemande" {
    git switch -q main
    git add a.txt
    run answer 3 exemple "" "suppression d'une ligne" n "corrige le helm ignore" "" "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"protégée"* ]] || false
    [[ "$output" == *"Réponds o (oui) ou n (non)"* ]] || false
    [ "$(git symbolic-ref --short HEAD)" = docs/exemple ]
    [ "$(subject)" = "docs(exemple): corrige le helm ignore" ]
    [ "$(git rev-parse main)" != "$(git rev-parse HEAD)" ]
}

@test "assistant : commit refuse par un hook -> message conserve" {
    mkdir -p .repowarden
    printf '#!/bin/sh\nexit 1\n' >.repowarden/pre-commit
    chmod +x .repowarden/pre-commit
    run answer "" "" "" "ajoute le panier" "" "" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"ton message est conservé"* ]] || false
    grep -qx "feat(panier): ajoute le panier" "$(git rev-parse --git-dir)/repowarden-message"
}

@test "assistant : scope invalide -> version corrigee proposee, Entree l'accepte" {
    run answer "" "Doc Test" "" "" "ajoute le panier" "" "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Proposé : doc-test"* ]] || false
    [ "$(subject)" = "feat(doc-test): ajoute le panier" ]
}

@test "assistant : branche sur main - type seul complete, nom approximatif corrige" {
    git switch -q main
    git add a.txt
    run answer "" test "feat" "" "ajoute le panier" "" "" ""
    [ "$status" -eq 0 ]
    [ "$(git symbolic-ref --short HEAD)" = feat/test ]
    git switch -q main
    echo y >b.txt
    git add b.txt
    run answer "" autre "Mon Essai" "" "" "ajoute autre chose" "" "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Proposé : feat/mon-essai"* ]] || false
    [ "$(git symbolic-ref --short HEAD)" = feat/mon-essai ]
}

@test "assistant : une ligne de ponctuation seule (;) termine le corps" {
    run answer "" "" "" "ajoute le panier" "Le client garde ses articles." ";" "" ""
    [ "$status" -eq 0 ]
    git log -1 --format=%B >msg
    grep -qx 'Le client garde ses articles.' msg
    ! grep -qx ';' msg
}

@test "assistant : en-tete trop long -> nouvelle saisie" {
    long="$(printf 'a%.0s' {1..80})"
    run answer "" "" "" "$long" "description courte" "" "" ""
    [[ "$output" == *"En-tête trop long"* ]] || false
    [ "$(subject)" = "feat(panier): description courte" ]
}

@test "assistant : rien de stage -> refus" {
    git reset -q
    run answer "" "" "" "x" "" "" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"Rien n'est stagé"* ]] || false
}

@test "assistant : abandon a la confirmation" {
    before="$(git rev-parse HEAD)"
    run answer "" "" "" "ajoute le panier" "" "" "n"
    [ "$status" -ne 0 ]
    [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "assistant : alias git cc installe et retire, sans ecraser un alias existant" {
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
    touch "$GIT_CONFIG_GLOBAL"
    git config --unset core.hooksPath
    run "$BATS_TEST_DIRNAME/../install.sh"
    [[ "$output" == *"git cc"* ]] || false
    [[ "$(git config --local --get alias.cc)" == *"/bin/commit"* ]] || false
    "$BATS_TEST_DIRNAME/../install.sh" --uninstall >/dev/null
    [ -z "$(git config --local --get alias.cc || true)" ]
    git config alias.cc "commit -v"
    run "$BATS_TEST_DIRNAME/../install.sh"
    [[ "$output" == *"déjà utilisé"* ]] || false
    [ "$(git config --local --get alias.cc)" = "commit -v" ]
}

@test "catalogues : chaque cle existe en francais et en anglais" {
    cles() { grep -oE '^        [a-z_.0-9-]+\)' "$1" | tr -d ' )' | sort; }
    diff <(cles "$HOOKS/lib/i18n/fr.sh") <(cles "$HOOKS/lib/i18n/en.sh")
}

@test "assistant : --strict -> une reponse refusee arrete tout, rien n'est commite" {
    long="$(printf 'a%.0s' {1..80})"
    before="$(git rev-parse HEAD)"
    run bash -c "printf '%s\n' '' '' '' '$long' 'description courte' '' '' '' | '$CC' --strict 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"En-tête trop long"* ]] || false
    [[ "$output" == *"Abandon (--strict)"* ]] || false
    [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "assistant : sans question (-m), type et scope deduits de la branche" {
    run "$CC" -m "ajoute le panier" --body $'Le client garde ses articles.\nMeme apres deconnexion.' --refs "Closes #12"
    [ "$status" -eq 0 ]
    [[ "$output" != *"1/5"* ]] || false
    [ "$(subject)" = "feat(panier): ajoute le panier" ]
    git log -1 --format=%B >msg
    grep -qx 'Le client garde ses articles.' msg
    grep -qx 'Meme apres deconnexion.' msg
    grep -qx 'Closes #12' msg
}

@test "assistant : sans question, options --x=valeur, majeur et options de git commit transmises" {
    run "$CC" --no-verify --type=fix --scope - --breaking "le total est en centimes" -m "change le calcul du total"
    [ "$status" -eq 0 ]
    [ "$(subject)" = "fix!: change le calcul du total" ]
    git log -1 --format=%B | grep -qx 'BREAKING CHANGE: le total est en centimes'
}

@test "assistant : sans question, valeur refusee -> abandon, rien n'est commite" {
    before="$(git rev-parse HEAD)"
    run "$CC" --type inconnu -m "ajoute le panier"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Abandon (--strict)"* ]] || false
    run "$CC" --type feat
    [ "$status" -ne 0 ]
    [[ "$output" == *"la description est obligatoire"* ]] || false
    run "$CC" -m
    [ "$status" -ne 0 ]
    [[ "$output" == *"attend une valeur"* ]] || false
    [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "assistant : sans question sur main -> aucune branche creee, abandon" {
    git switch -q main
    run "$CC" -m "ajoute le panier"
    [ "$status" -ne 0 ]
    [ "$(git branch --show-current)" = main ]
    [ "$(subject)" = "chore: init" ]
}

@test "assistant : branche hors convention -> ni type ni scope proposes" {
    git config repowarden.allowedBranches "main wip/*"
    git switch -q -c wip/essai
    run answer "" "docs" "" "" "ajoute la note" "" "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Type obligatoire"* ]] || false
    [ "$(subject)" = "docs: ajoute la note" ]
    run "$CC" --dry-run -m "ajoute la note"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Type obligatoire"* ]] || false
}

@test "assistant : branche feat/12-sujet -> Ticket : #12 propose en reference" {
    git switch -q -c feat/12-panier
    run answer "" "" "" "ajoute le panier" "" "" ""
    [ "$status" -eq 0 ]
    git log -1 --format=%B | grep -qx 'Ticket : #12'
}

@test "assistant : type inconnu -> type le plus proche propose (interactif et --type)" {
    run answer "doc" "" "" "" "ajoute le panier" "" "" ""
    [[ "$output" == *"docs"* ]] || false
    [ "$(subject)" = "feat(panier): ajoute le panier" ]
    run "$CC" --dry-run -m "ajoute" --type doc
    [ "$status" -ne 0 ]
    [[ "$output" == *"docs"* ]] || false
}

@test "assistant : scope propose -> l'aide dit ce que fait Entree" {
    run answer "" "" "" "ajoute le panier" "" "" ""
    [[ "$output" == *"Entrée garde « panier »"* ]] || false
    [[ "$output" != *"chart ; Entrée pour aucun."* ]] || false
}

@test "assistant : exemple de references selon le flux (Ticket : #12 avec develop)" {
    run answer "" "" "" "ajoute le panier" "" "" ""
    [[ "$output" == *"Closes #12"* ]] || false
    git reset -q --soft HEAD~1
    git config repowarden.integrationBranch develop
    run answer "" "" "" "ajoute le panier" "" "" ""
    [[ "$output" == *"ex. Ticket : #12"* ]] || false
    [[ "$output" != *"Closes #12"* ]] || false
}

@test "tickets : la question de git cc n'est promise que si git cc la pose" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nexit 0\n' >"$BATS_TEST_TMPDIR/bin/gh"
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    git config repowarden.tickets true
    run git switch -c feat/autre
    [[ "$output" == *"Partir d'un ticket"* ]] || false
    [[ "$output" != *"git cc"* ]] || false
    git config repowarden.ticketAutoCreate true
    run git switch -c feat/encore
    [[ "$output" == *"réponds oui à git cc"* ]] || false
}
