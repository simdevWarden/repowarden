#!/usr/bin/env bats
# Passage de repogarde à repowarden (bin/migrer) : projet tel que
# repowarden-demo avant sa migration, gh simulé pour --pr

load helpers

MIGRER="$BATS_TEST_DIRNAME/../bin/migrer"

setup() {
    setup_repo
    initial_commit
    export REPOWARDEN_MAJEURE=4
    printf '# Réglages repogarde du projet\n[repogarde]\n    # Version minimale de repogarde\n    version = 3.5.0\n    lang = fr\n' >.repogarde.conf
    mkdir -p .github/workflows .repogarde
    printf '#!/bin/sh\necho hook\n' >.repogarde/pre-commit
    cat >.github/workflows/repogarde.yml <<'YML'
name: repogarde
on: [pull_request]
permissions: {}
jobs:
  repogarde:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: SimBienvenueHoulBoumi/repogarde@v3
        with:
          strict: true
        env:
          TOKEN: ${{ secrets.REPOGARDE_APP_KEY }}
YML
    cat >.github/workflows/tickets.yml <<'YML'
on: [pull_request_target]
permissions: {}
jobs:
  tickets:
    uses: SimBienvenueHoulBoumi/repogarde/.github/workflows/tickets.yml@feat/tickets
    permissions: { issues: write, pull-requests: write, statuses: write }
    with:
      repogarde-ref: feat/tickets
      integration-branch: main
YML
    cat >.github/workflows/release.yml <<'YML'
on: [push]
jobs:
  release:
    uses: SimBienvenueHoulBoumi/repogarde/.github/workflows/release-auto.yml@v3
    # with:
    #   workflows: repogarde.yml
YML
    printf 'Voir [repogarde](https://github.com/SimBienvenueHoulBoumi/repogarde)\n' >README.md
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "chore: projet sous repogarde" # préparation, hors hooks
}

@test "migrer : configuration, workflows et anciens noms remplaces (cas repowarden-demo)" {
    run "$MIGRER"
    [ "$status" -eq 0 ]
    # configuration renommée (suivie par git), section et version à jour
    [ ! -e .repogarde.conf ] && [ -f .repowarden.conf ]
    grep -q '^\[repowarden\]$' .repowarden.conf
    grep -q '^    version = 4$' .repowarden.conf
    ! grep -q repogarde .repowarden.conf
    [ -x .repowarden/pre-commit ] && [ ! -e .repogarde ]
    # action et workflows réutilisables : nouveau dépôt, version majeure
    w=.github/workflows
    [ ! -e $w/repogarde.yml ] && [ -f $w/repowarden.yml ]
    grep -q '^name: repowarden$' $w/repowarden.yml
    grep -q '^  repowarden:$' $w/repowarden.yml
    grep -q 'uses: simdevWarden/repowarden@v4$' $w/repowarden.yml
    grep -q 'uses: actions/checkout@v7$' $w/repowarden.yml
    grep -q 'secrets.REPOWARDEN_APP_KEY' $w/repowarden.yml
    grep -q 'uses: simdevWarden/repowarden/.github/workflows/tickets.yml@v4$' $w/tickets.yml
    grep -q 'uses: simdevWarden/repowarden/.github/workflows/release-auto.yml@v4$' $w/release.yml
    grep -q '#   workflows: repowarden.yml' $w/release.yml
    # entrée retirée ; contents: write ajouté au job, pas au workflow
    ! grep -q 'ref:' $w/tickets.yml
    grep -q 'permissions: { contents: write, issues: write' $w/tickets.yml
    grep -q '^permissions: {}$' $w/tickets.yml
    # événements du modèle : PR brouillon préremplie au premier push
    grep -qE '^  push:$' $w/tickets.yml
    grep -q 'types: \[opened, labeled, assigned, closed\]' $w/tickets.yml
    grep -q 'integration-branch: main' $w/tickets.yml
    [[ "$output" == *"repowarden tickets init"* ]] || false
    ! grep -rqi repogarde .github
    # à faire à la main : secret à recréer, README à relire (non modifié)
    [[ "$output" == *"REPOWARDEN_APP_KEY"* ]] || false
    [[ "$output" == *"README.md"* ]] || false
    grep -q repogarde README.md
    [[ "$output" == *"repowarden proteger"* ]] || false
    # relance : rien à faire
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "chore: migration"
    run "$MIGRER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rien à migrer"* ]] || false
    [ -z "$(git status --porcelain)" ]
}

@test "migrer : hooks lefthook residuels signales, deplaces seulement avec --hooks" {
    printf '#!/bin/sh\ncall_lefthook run pre-commit\n' >.git/hooks/pre-commit
    printf '#!/bin/sh\necho perso\n' >.git/hooks/post-merge
    run "$MIGRER"
    [[ "$output" == *"Hooks lefthook résiduels dans .git/hooks ( pre-commit)"* ]] || false
    [ -f .git/hooks/pre-commit ]
    run "$MIGRER" --hooks
    [ "$status" -eq 0 ]
    [ ! -e .git/hooks/pre-commit ] && [ -f .git/hooks-lefthook/pre-commit ]
    # hook propre au projet, sans lefthook : jamais touché
    [ -f .git/hooks/post-merge ]
}

@test "migrer : les deux noms presents -> rien ecrase, signale" {
    printf '[repowarden]\n    lang = en\n' >.repowarden.conf
    run "$MIGRER"
    [ "$status" -eq 0 ]
    [[ "$output" == *".repogarde.conf et .repowarden.conf existent tous les deux"* ]] || false
    grep -q 'lang = en' .repowarden.conf
    [ -f .repogarde.conf ]
}

@test "migrer : version majeure du tag flottant de la version installee, valeur invalide refusee" {
    unset REPOWARDEN_MAJEURE
    # le dépôt repowarden courant donne une version : vN publié existe
    # (clone sans tags : version inconnue, cas vérifié par le test suivant)
    source "$BATS_TEST_DIRNAME/../hooks/lib/ui.sh"
    repowarden_version_r "$BATS_TEST_DIRNAME/.."
    [ "$REPLY" != 0.0.0-dev ] || skip "clone de repowarden sans tags : git fetch --tags"
    run "$MIGRER"
    [ "$status" -eq 0 ]
    grep -qE 'uses: simdevWarden/repowarden@v[1-9][0-9]*$' .github/workflows/repowarden.yml
    REPOWARDEN_MAJEURE=x run "$MIGRER"
    [ "$status" -ne 0 ]
}

@test "migrer : version inconnue (clone sans tags) -> marche a suivre, rien de modifie" {
    unset REPOWARDEN_MAJEURE
    # Copie de repowarden sans .git : version 0.0.0-dev de package.json
    copie="$BATS_TEST_TMPDIR/repowarden-sans-tags"
    mkdir -p "$copie"
    cp -R "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../hooks" "$BATS_TEST_DIRNAME/../package.json" "$copie/"
    # Chemin réel, comme migrer l'affiche (macOS : /var → /private/var)
    copie="$(cd "$copie" && pwd -P)"
    avant="$(git status --porcelain)"
    run "$copie/bin/migrer"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Version de repowarden inconnue (clone sans tags) : git -C $copie fetch --tags"* ]] || false
    [ "$(git status --porcelain)" = "$avant" ]
}

@test "migrer --pr : branche, commit conventionnel, push et PR ; rien si une PR est ouverte" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$1 $2" in
    "pr list") [ -n "${GH_PR_OPEN:-}" ] && echo 12 ;;
esac
exit 0
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    git -c core.hooksPath=/dev/null push -q -u origin main
    # arbre modifié : refusé
    echo x >>README.md
    run "$MIGRER" --pr
    [ "$status" -ne 0 ]
    git checkout -q README.md
    run "$MIGRER" --pr
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = chore/migration-repowarden-v4 ]
    [ "$(subject)" = "chore(migration): passage de repogarde à repowarden v4" ]
    git ls-remote --exit-code origin refs/heads/chore/migration-repowarden-v4 >/dev/null
    grep -q "^pr create --head chore/migration-repowarden-v4 --title chore(migration): passage" "$GH_LOG"
    [[ "$output" == *"PR de migration ouverte"* ]] || false
    # PR déjà ouverte : rien
    git switch -q main
    : >"$GH_LOG"
    GH_PR_OPEN=1 run "$MIGRER" --pr
    [ "$status" -eq 0 ]
    [[ "$output" == *"déjà ouverte"* ]] || false
    ! grep -q "^pr create" "$GH_LOG"
    [ "$(git branch --show-current)" = main ]
}

@test "migrer --pr : projet deja migre -> aucune branche laissee" {
    git rm -q -r .repogarde.conf .repogarde .github README.md
    git -c core.hooksPath=/dev/null commit -q -m "chore: sans repogarde"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$BATS_TEST_TMPDIR/bin/gh"
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$MIGRER" --pr
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rien à migrer"* ]] || false
    [ "$(git branch --show-current)" = main ]
    ! git show-ref -q --verify refs/heads/chore/migration-repowarden-v4
}

@test "migrer : projet deja renomme, suivi des tickets perime -> evenements completes" {
    git rm -q -r .repogarde.conf .repogarde .github
    mkdir -p .github/workflows
    cat >.github/workflows/tickets.yml <<'YML'
name: tickets
on:
  pull_request_target:
    types: [opened, closed]
  issues:
    types: [opened, labeled]
permissions: {}
jobs:
  tickets:
    uses: simdevWarden/repowarden/.github/workflows/tickets.yml@v4
    with:
      integration-branch: develop
YML
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "chore: projet renommé"
    run "$MIGRER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"événements du suivi des tickets complétés"* ]] || false
    grep -qE '^  push:$' .github/workflows/tickets.yml
    grep -q 'integration-branch: develop' .github/workflows/tickets.yml
    [ "$(grep -c '^on:' .github/workflows/tickets.yml)" -eq 1 ]
    if command -v actionlint >/dev/null; then actionlint .github/workflows/tickets.yml; fi
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "chore: migration"
    run "$MIGRER"
    [[ "$output" == *"Rien à migrer"* ]] || false
}

@test "migrer : release-auto sans issues: read -> ajoute (tickets lisibles sur un depot prive)" {
    git rm -q -r .repogarde.conf .repogarde .github
    mkdir -p .github/workflows
    printf 'on: [push]\npermissions: {}\njobs:\n  release:\n    uses: simdevWarden/repowarden/.github/workflows/release-auto.yml@v4\n    permissions: { contents: write, pull-requests: write, actions: write, checks: read, statuses: write }\n' \
        >.github/workflows/release.yml
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "chore: projet renommé"
    run "$MIGRER"
    [ "$status" -eq 0 ]
    grep -q 'statuses: write, issues: read }$' .github/workflows/release.yml
    grep -q '^permissions: {}$' .github/workflows/release.yml
    [[ "$output" == *"issues: read ajouté"* ]] || false
    git add -A && git -c core.hooksPath=/dev/null commit -q -m "chore: migration"
    run "$MIGRER"
    [[ "$output" == *"Rien à migrer"* ]] || false
}

@test "statut : anciens noms dans le projet -> repowarden migrer propose" {
    run "$BATS_TEST_DIRNAME/../bin/statut"
    [[ "$output" == *"Anciens noms repogarde dans ce projet : repowarden migrer"* ]] || false
    "$MIGRER" >/dev/null
    run "$BATS_TEST_DIRNAME/../bin/statut"
    [[ "$output" != *"repowarden migrer"* ]] || false
}

# Workflows du projet déjà migrés, avec $1 comme lignes uses: (une par job)
workflows_repowarden() {
    git rm -q -r .repogarde.conf .repogarde .github
    mkdir -p .github/workflows
    printf 'on: [push]\npermissions: {}\njobs:\n' >.github/workflows/ci.yml
    local u n=0
    for u in "$@"; do
        n=$((n + 1))
        printf '  j%s:\n    uses: %s\n' "$n" "$u" >>.github/workflows/ci.yml
    done
}

@test "statut : workflows repowarden d'un autre depot, sur une branche, majeure en retard -> lignes signalees" {
    workflows_repowarden \
        autre-compte/repowarden/.github/workflows/release-auto.yml@v4 \
        simdevWarden/repowarden/.github/workflows/tickets.yml@feat/tickets \
        "'simdevWarden/repowarden@v3'"
    run "$BATS_TEST_DIRNAME/../bin/statut"
    [[ "$output" == *".github/workflows/ci.yml:5 : repowarden appelé depuis un autre dépôt que le dépôt officiel (autre-compte/repowarden) ; attendu : simdevWarden/repowarden/.github/workflows/release-auto.yml@v4"* ]] || false
    [[ "$output" == *".github/workflows/ci.yml:7 : repowarden appelé sur une branche (@feat/tickets), cassé dès qu'elle disparaît ; attendu : simdevWarden/repowarden/.github/workflows/tickets.yml@v4"* ]] || false
    [[ "$output" == *".github/workflows/ci.yml:9 : repowarden appelé dans une majeure dépassée (@v3) ; attendu : simdevWarden/repowarden@v4"* ]] || false
    REPOWARDEN_LANG=en run "$BATS_TEST_DIRNAME/../bin/statut"
    [[ "$output" == *"ci.yml:7: repowarden called on a branch (@feat/tickets)"* ]] || false
}

@test "statut : workflows repowarden a jour (vN, vN.x.y, SHA, commentes, locaux) -> rien de signale" {
    workflows_repowarden \
        simdevWarden/repowarden/.github/workflows/release-auto.yml@v4 \
        simdevwarden/repowarden@v4.9.3 \
        simdevWarden/repowarden@0123456789abcdef0123456789abcdef01234567 \
        ./.github/workflows/local.yml
    printf '  # uses: simdevWarden/repowarden@v1\n' >>.github/workflows/ci.yml
    run "$BATS_TEST_DIRNAME/../bin/statut"
    [ "$status" -eq 0 ]
    [[ "$output" != *"repowarden appelé"* ]] || false
    [[ "$output" != *"corriger les lignes uses:"* ]] || false
}

@test "statut : seule alerte une ligne uses: -> etape suivante, pas tout est pret" {
    workflows_repowarden simdevWarden/repowarden@main
    # Hooks et git cc de cette installation, dans ce dépôt seulement
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
    touch "$GIT_CONFIG_GLOBAL"
    git config alias.cc "!$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)/bin/commit"
    run "$BATS_TEST_DIRNAME/../bin/statut"
    [[ "$output" == *"corriger les lignes uses: signalées ci-dessus"* ]] || false
    [[ "$output" != *"Tout est prêt"* ]] || false
}
