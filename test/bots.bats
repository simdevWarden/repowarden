#!/usr/bin/env bats
# Bots du dépôt configurés avec l'accord de l'utilisateur (bin/bots) : gh
# simulé, commandes enchaînées simulées, réponses sur l'entrée standard

load helpers

BOTS="$BATS_TEST_DIRNAME/../bin/bots"
INSTALL="$BATS_TEST_DIRNAME/../install.sh"

setup() {
    setup_repo
    initial_commit
    git remote set-url origin https://github.com/moi/projet.git
    F="$BATS_TEST_TMPDIR/f"
    mkdir -p "$F/bin" "$F/fakebin"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >>"$FAKE/log"
case "$*" in
    "auth status"*) exit "${GH_AUTH:-0}" ;;
    "repo view"*) echo moi/projet ;;
    "api repos/moi/projet --jq .permissions.admin") echo "${GH_ADMIN:-true}" ;;
    "api repos/moi/projet --jq .default_branch") echo main ;;
    # absente : comme le vrai gh, corps de la 404 sur la sortie standard
    "api repos/moi/projet/branches/develop"*)
        [ -n "${GH_DEVELOP:-}" ] && { echo develop; exit 0; }
        echo '{"message":"Branch not found","status":"404"}'
        exit 1 ;;
    # dépôt privé d'une offre gratuite : rulesets refusés en 403
    "api repos/moi/projet/rulesets"*)
        [ -z "${GH_RULESETS_403:-}" ] && { echo '[]'; exit 0; }
        echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}'
        echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2
        exit 1 ;;
    "variable get REPOWARDEN_APP_CLIENT_ID"*) [ -n "${GH_APP:-}" ] && echo Iv1.abc || exit 1 ;;
    "api repos/moi/projet/git/ref/heads/main"*) echo abc123 ;;
esac
exit 0
GH
    for c in tickets app proteger npm-publication; do
        printf '#!/usr/bin/env bash\necho "%s $*" >>"$FAKE/log"\n[ "${ECHEC:-}" != %s ]\n' "$c" "$c" >"$F/fakebin/$c"
    done
    chmod +x "$F/bin/gh" "$F/fakebin/"*
    export PATH="$F/bin:$PATH" FAKE="$F" REPOWARDEN_BIN="$F/fakebin" REPOWARDEN_INTERACTIF=1
}

# Réponses, une par ligne
repondre() { printf '%s\n' "$@" >"$F/reponses"; }
lancer() { run bash -c "\"$BOTS\" <\"$F/reponses\""; }

@test "bots : rien sans accord (non par defaut), ni sans terminal, gh ou droits d'admin" {
    repondre ""
    lancer
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucun bot configuré"* ]] || false
    [ ! -e .github ] && ! grep -q -- "-X POST" "$F/log"
    ! grep -qE "^(tickets|app|proteger|npm-publication) " "$F/log"
    REPOWARDEN_INTERACTIF="" run bash -c "\"$BOTS\" </dev/null"
    [[ "$output" == *"pas de terminal"*"repowarden bots"* ]] || false
    GH_ADMIN=false lancer
    [[ "$output" == *"droits d'administration"* ]] || false
    GH_AUTH=1 lancer
    [[ "$output" == *"gh auth login"* ]] || false
    # réglage forge : prioritaire sur la CI (GITHUB_ACTIONS) et sur le remote
    git config repowarden.forge gitlab
    lancer
    [[ "$output" == *"hors de GitHub"* ]] || false
}

@test "bots : flux main, un accord par bot, apercu puis application" {
    # global, flux 1, ci, release, tickets, app (non), protection, confirmation
    repondre o 1 o o o n o o
    lancer
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aperçu"* && "$output" == *".github/workflows/repowarden.yml : créé"* ]] || false
    grep -q 'branches: \[main\]' .github/workflows/repowarden.yml
    ! grep -q 'fix-pr' .github/workflows/repowarden.yml
    grep -q 'release-auto.yml@v4' .github/workflows/release.yml
    grep -q 'issues: read' .github/workflows/release.yml
    ! grep -q 'app-client-id' .github/workflows/release.yml
    [ ! -e .github/workflows/nettoyage.yml ]
    grep -q "^tickets init --repo moi/projet$" "$F/log"
    grep -q "^proteger --repo moi/projet$" "$F/log"
    ! grep -q "^app " "$F/log"
    ! git config -f .repowarden.conf --get repowarden.integrationBranch
    [[ "$output" == *"commiter par une PR"* ]] || false
    # aucun langage reconnu : modèle générique, strict commenté, et c'est dit
    [[ "$output" == *"langage non reconnu : modèle générique"* ]] || false
    grep -q '^        #   strict: true' .github/workflows/repowarden.yml
    ! grep -q 'setup-python' .github/workflows/repowarden.yml
    if command -v actionlint >/dev/null; then actionlint .github/workflows/*.yml; fi
}

@test "bots : CI d'un projet Python -> setup-python, ruff vulture pytest, strict actif" {
    printf '[project]\nname = "x"\n' >pyproject.toml
    # global, flux 1, ci, release (non), tickets (non), app (non), protection (non), confirmation
    repondre o 1 o n n n n o
    lancer
    [ "$status" -eq 0 ]
    [[ "$output" == *"outillage de la CI : python"* ]] || false
    w=.github/workflows/repowarden.yml
    grep -q 'actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0' "$w"
    grep -q 'python-version: "3.12"' "$w"
    grep -q 'run: pip install ruff==0.16.10 vulture==2.16 pytest==9.1.1' "$w"
    ! grep -q 'requirements.txt' "$w"
    grep -q '^          strict: true' "$w"
    grep -q 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' "$w"
    if command -v actionlint >/dev/null; then actionlint "$w"; fi
}

@test "bots : CI Node, Go, Java -> outillage par langage, strict seulement s'il est complet" {
    printf '{ "name": "x", "private": true, "devDependencies": { "prettier": "3.6.2" } }\n' >package.json
    : >package-lock.json
    printf 'module x\n\ngo 1.24\n' >go.mod
    printf '<project><build><plugins><plugin>spotless</plugin></plugins></build></project>\n' >pom.xml
    # global, flux 2 (develop existe), ci, release (non), nettoyage (non), tickets (non), app (non), protection (non), confirmation
    repondre o 2 o n n n n n o
    GH_DEVELOP=1 lancer
    [ "$status" -eq 0 ]
    w=.github/workflows/repowarden.yml
    grep -q 'actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0' "$w"
    grep -q 'cache: npm' "$w" && grep -q 'run: npm ci' "$w"
    grep -q 'actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0' "$w"
    grep -q 'go-version-file: go.mod' "$w"
    grep -q 'actions/setup-java@de7274f081f381c8f8158605e0321c36c376e2e6 # v6.0.1' "$w"
    grep -q 'cache: maven' "$w"
    grep -q '^          strict: true' "$w" && grep -q 'fix-pr: "true"' "$w"
    if command -v actionlint >/dev/null; then actionlint "$w"; fi
    # prettier absent, Gradle sans wrapper : strict commenté avec la raison
    rm -rf .github pom.xml go.mod package-lock.json
    printf '{ "name": "x", "private": true }\n' >package.json
    : >settings.gradle
    repondre o 2 o n n n n n o
    GH_DEVELOP=1 lancer
    grep -q 'run: npm install' "$w"
    grep -q 'gradle/actions/setup-gradle@3f5f9adaf7d9fecd50b5935e54106014257a94e6 # v6.4.0' "$w"
    grep -q 'cache: gradle' "$w"
    grep -q '^          # strict: true   # prettier absent de package.json, Spotless non configuré (Gradle) :' "$w"
    ! grep -q '^          strict: true' "$w"
    if command -v actionlint >/dev/null; then actionlint "$w"; fi
}

@test "bots : flux develop, develop creee avec accord, App deja la -> livraison par l'environnement" {
    # global, flux 2, créer develop, ci, release, nettoyage, tickets (non), protection,
    # livraison, rythme, préversion (Entrée), confirmation
    repondre o 2 o o o o n o "" "" "" o
    GH_APP=1 lancer
    [ "$status" -eq 0 ]
    [[ "$output" == *"seul develop entre dans main (livraison)"* ]] || false
    [[ "$output" == *"déjà configurée"* ]] || false
    grep -q "^gh api -X POST repos/moi/projet/git/refs -f ref=refs/heads/develop -f sha=abc123" "$F/log"
    [ "$(git config -f .repowarden.conf repowarden.integrationBranch)" = develop ]
    [ "$(git config -f .repowarden.conf repowarden.protectedBranches)" = "main develop" ]
    ! git config -f .repowarden.conf --get repowarden.deliveryApproval
    grep -q 'fix-pr: "true"' .github/workflows/repowarden.yml
    grep -q 'branches: \[main, develop\]' .github/workflows/repowarden.yml
    grep -q 'mode: tag' .github/workflows/release.yml
    grep -q 'delivery-environment: production' .github/workflows/release.yml
    grep -q 'nettoyage-branches.yml@v4' .github/workflows/nettoyage.yml
    ! grep -qE "^(tickets|app) " "$F/log"
    if command -v actionlint >/dev/null; then actionlint .github/workflows/*.yml; fi
}

@test "bots : flux develop sans App -> livraison validee par revue ; develop refusee -> flux main" {
    # global, flux 2 (develop existe), ci, release, nettoyage, tickets, app (non), protection,
    # livraison, rythme, préversion (Entrée), confirmation
    repondre o 2 o o o n n n "" "" "" o
    GH_DEVELOP=1 lancer
    [ "$status" -eq 0 ]
    [ "$(git config -f .repowarden.conf repowarden.deliveryApproval)" = review ]
    ! grep -q 'delivery-environment' .github/workflows/release.yml
    ! grep -q -- "-X POST" "$F/log"
    rm -rf .github .repowarden.conf
    : >"$F/log"
    # develop absente, création refusée : flux main
    repondre o 2 n o n n n n o
    lancer
    grep -q 'branches: \[main\]' .github/workflows/repowarden.yml
    [ ! -e .repowarden.conf ]
}

@test "bots : integrationBranch deja en place -> .repowarden.conf laisse tel quel" {
    printf '[repowarden]\n    integrationBranch = develop\n    protectedBranches = main develop\n    deliveryApproval = review\n' >.repowarden.conf
    cp .repowarden.conf "$F/avant"
    # global, flux 2 (develop existe), ci, release (non), nettoyage (non), tickets (non), app (non), protection (non), confirmation
    repondre o 2 o n n n n n o
    GH_DEVELOP=1 lancer
    [ "$status" -eq 0 ]
    cmp .repowarden.conf "$F/avant"
}

@test "bots : flux develop propose par defaut" {
    # global, flux (Entrée), ci, release, nettoyage, tickets, app, protection,
    # livraison, rythme, préversion (Entrée), confirmation
    repondre o "" o o n n n n "" "" "" o
    GH_DEVELOP=1 lancer
    [ "$status" -eq 0 ]
    [ "$(git config -f .repowarden.conf repowarden.integrationBranch)" = develop ]
}

@test "bots : fichier existant jamais ecrase, ecart signale ; confirmation refusee -> rien" {
    mkdir -p .github/workflows
    echo "# perso" >.github/workflows/repowarden.yml
    # global, flux 1, ci, release (non), tickets (non), app (non), protection (non), confirmation (non)
    repondre o 1 o n n n n n
    lancer
    [[ "$output" == *"repowarden.yml existe : gardé tel quel (écart avec le modèle"* ]] || false
    [[ "$output" == *"Aucun bot configuré"* ]] || false
    repondre o 1 o n n n n o
    lancer
    [ "$(cat .github/workflows/repowarden.yml)" = "# perso" ]
    [[ "$output" == *"repowarden.yml existe : gardé tel quel."* ]] || false
}

@test "bots : un bot en echec n'arrete pas les autres ; npm propose seulement pour un paquet public" {
    printf '{ "name": "x", "private": true }\n' >package.json
    # global, flux 1, ci (non), release (non), tickets, app (non), protection, confirmation
    repondre o 1 n n o n o o
    ECHEC=tickets lancer
    [ "$status" -ne 0 ]
    [[ "$output" == *"tickets : échec"* ]] || false
    grep -q "^proteger " "$F/log"
    [[ "$output" != *"Publication npm"* ]] || false
    printf '{ "name": "x" }\n' >package.json
    : >"$F/log"
    # ... protection (non), npm, confirmation
    repondre o 1 n n n n n o o
    lancer
    grep -q "^npm-publication --repo moi/projet$" "$F/log"
}

@test "install : bots proposes dans un depot GitHub, --sans-bots les fait taire" {
    REPOWARDEN_INTERACTIF="" run bash -c "\"$INSTALL\" </dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bots du dépôt non proposés (pas de terminal"* ]] || false
    run "$INSTALL" --sans-bots
    [[ "$output" == *"ne seront plus proposés"* ]] || false
    [ "$(git config --local repowarden.bots)" = off ]
    REPOWARDEN_INTERACTIF="" run bash -c "\"$INSTALL\" </dev/null"
    [[ "$output" != *"Bots du dépôt"* ]] || false
}

@test "bots : release.yml avec le job tickets (needs release, tag, App si presente)" {
    # flux main : global, flux 1, ci (non), release, tickets, app (non), protection (non), confirmation
    repondre o 1 n o o n n o
    lancer
    [ "$status" -eq 0 ]
    f=.github/workflows/release.yml
    grep -q '^  tickets:$' "$f"
    grep -q '^    needs: release$' "$f"
    grep -qF "if: needs.release.outputs.release_created == 'true' || needs.release.outputs.prerelease_created == 'true' || needs.release.outputs.delivered_without_version != ''" "$f"
    grep -q '^    uses: simdevWarden/repowarden/.github/workflows/tickets.yml@v4$' "$f"
    grep -q 'permissions: { contents: write, issues: write, pull-requests: write, statuses: write }' "$f"
    grep -qF 'tag: ${{ needs.release.outputs.tag_name || needs.release.outputs.prerelease_tag }}' "$f"
    grep -qF 'delivered-sha: ${{ needs.release.outputs.delivered_without_version }}' "$f"
    ! grep -q 'app-client-id' "$f"
    if command -v actionlint >/dev/null; then actionlint "$f"; fi
    rm -rf .github .repowarden.conf
    # flux develop, App déjà là : global, flux 2, ci (non), release, nettoyage (non), tickets, protection (non),
    # livraison, rythme, préversion (Entrée), confirmation
    repondre o 2 n o n o n "" "" "" o
    GH_DEVELOP=1 GH_APP=1 lancer
    [ "$status" -eq 0 ]
    [ "$(grep -c 'app-client-id: ${{ vars.REPOWARDEN_APP_CLIENT_ID }}' "$f")" -eq 2 ]
    sed -n '/^  tickets:$/,$p' "$f" | grep -qF 'app-key: ${{ secrets.REPOWARDEN_APP_KEY }}'
    if command -v actionlint >/dev/null; then actionlint "$f"; fi
    rm -rf .github .repowarden.conf
    # sans suivi des tickets : pas de job tickets (il échouerait sans les étiquettes)
    repondre o 1 n o n n n o
    lancer
    ! grep -q 'tickets.yml@' "$f"
}

@test "bots : livraison, reponses par defaut -> release.yml d'aujourd'hui, a l'octet pres" {
    # flux develop, App déjà là : global, flux 2, ci (non), release, nettoyage (non), tickets (non),
    # protection (non), livraison, rythme, préversion (Entrée), confirmation
    repondre o 2 n o n n n "" "" "" o
    GH_DEVELOP=1 GH_APP=1 lancer
    [ "$status" -eq 0 ]
    [[ "$output" == *"livraison approuvée par une personne"* ]] || false
    [[ "$output" == *"regroupé, préversion le soir"* && "$output" == *"préversion obligatoire avant"* ]] || false
    ! git config -f .repowarden.conf --get repowarden.deliveryApproval
    cat >"$F/attendu" <<'YAML'
# Releases, flux develop → main (mode tag) : préversion vX.Y.Z-next.N le
# soir si develop a changé ; le vendredi matin (ou à la main), une demande
# de livraison develop → main, qui publie le tag vX.Y.Z et la release.
name: release

on:
  push:
    branches: [main, develop]
  schedule:
    - cron: "0 19 * * *" # préversion du soir, si develop a changé
    - cron: "0 7 * * 5" # fenêtre de livraison : le vendredi matin
  workflow_dispatch: # à la main (et urgence) : préversion et demande de livraison

# Une file par branche et par déclencheur ; une demande manuelle ou planifiée
# remplace celle en attente ; un push n'annule jamais un run en cours
concurrency:
  group: release-${{ github.ref_name }}-${{ github.event.schedule || github.event_name }}
  cancel-in-progress: ${{ github.event_name != 'push' }}

permissions: {}

jobs:
  release:
    uses: simdevWarden/repowarden/.github/workflows/release-auto.yml@v4
    permissions: { contents: write, pull-requests: write, actions: write, checks: read, statuses: write, issues: read }
    with:
      mode: tag
      integration-branch: develop
      main-branch: main
      delivery-schedule: "0 7 * * 5" # même cron que la fenêtre ci-dessus
      delivery-environment: production # « Approve and deploy » valide la livraison
      app-client-id: ${{ vars.REPOWARDEN_APP_CLIENT_ID }} # la GitHub App merge la livraison approuvée
    secrets:
      app-key: ${{ secrets.REPOWARDEN_APP_KEY }}
YAML
    diff "$F/attendu" .github/workflows/release.yml
}

@test "bots : livraison automatique, a chaque ticket, preversion facultative -> entrees et deliveryApproval auto" {
    # flux develop, App déjà là : global, flux 2, ci (non), release, nettoyage (non), tickets (non),
    # protection (non), livraison auto, à chaque ticket, préversion (non), confirmation
    repondre o 2 n o n n n o o n o
    GH_DEVELOP=1 GH_APP=1 lancer
    [ "$status" -eq 0 ]
    f=.github/workflows/release.yml
    grep -q '^      delivery-auto: true' "$f"
    grep -q '^      preversion-on-push: true' "$f"
    grep -q '^      delivery-on-push: true' "$f"
    grep -q '^      preversion-obligatoire: false' "$f"
    grep -q 'app-client-id: ${{ vars.REPOWARDEN_APP_CLIENT_ID }}' "$f"
    # modes exclusifs ; plus de fenêtre de livraison ni de préversion du soir
    ! grep -q 'delivery-environment' "$f"
    ! grep -q 'delivery-schedule' "$f"
    ! grep -q 'cron:' "$f"
    [ "$(git config -f .repowarden.conf repowarden.deliveryApproval)" = auto ]
    [[ "$output" == *"deliveryApproval = auto"* && "$output" == *"livraison automatique (delivery-auto)"* ]] || false
    [[ "$output" == *"à chaque ticket, préversion et demande de livraison"* ]] || false
    [[ "$output" == *"version stable possible sans préversion"* ]] || false
    [[ "$output" != *"exige l'App"* ]] || false
    if command -v actionlint >/dev/null; then actionlint "$f"; fi
}

@test "bots : livraison automatique sans GitHub App -> avertissement, et dans l'apercu" {
    # global, flux 2 (develop existe), ci (non), release, nettoyage (non), tickets (non), app (non),
    # protection (non), livraison auto, rythme (Entrée), préversion (Entrée), confirmation
    repondre o 2 n o n n n n o "" "" o
    GH_DEVELOP=1 lancer
    [ "$status" -eq 0 ]
    [ "$(grep -c "le merge automatique exige l'App" <<<"$output")" -eq 2 ]
    f=.github/workflows/release.yml
    grep -q '^      delivery-auto: true' "$f"
    grep -q '^      delivery-schedule: "0 7 \* \* 5"' "$f"
    ! grep -q 'app-client-id' "$f"
    ! grep -q 'preversion-obligatoire' "$f"
    [ "$(git config -f .repowarden.conf repowarden.deliveryApproval)" = auto ]
    if command -v actionlint >/dev/null; then actionlint "$f"; fi
}

@test "bots : depot prive d'une offre gratuite -> explique avant les questions, pas de livraison automatique" {
    # flux develop, App déjà là : global, flux 2, ci (non), release, nettoyage (non), tickets (non),
    # protection, rythme (Entrée), préversion (Entrée), confirmation ; aucune question de livraison automatique
    repondre o 2 n o n n o "" "" o
    GH_RULESETS_403=1 GH_DEVELOP=1 GH_APP=1 lancer
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    # annoncé avant la première question : ce qui ne marchera pas, et les issues
    avant="${output%%Configurer les bots*}"
    [[ "$avant" == *"moi/projet est un dépôt privé d'une offre gratuite"* ]] || false
    [[ "$avant" == *"ni merge automatique"*"livraison automatique"*"rendre le dépôt public"*"GitHub Pro / Team"* ]] || false
    [[ "$output" != *"Livraison automatique ? (non"* ]] || false
    [[ "$output" == *"Livraison automatique non proposée"* ]] || false
    f=.github/workflows/release.yml
    ! grep -q 'delivery-auto' "$f"
    # ni environnement d'approbation (indisponible sur ce dépôt) : revue de la PR de livraison
    ! grep -q 'delivery-environment' "$f"
    [ "$(git config -f .repowarden.conf repowarden.deliveryApproval)" = review ]
    grep -q "^proteger --repo moi/projet$" "$F/log"
    # dépôt public ou offre payante : rien de tout cela
    rm -rf .github .repowarden.conf
    repondre o 2 n o n n o n "" "" o
    GH_DEVELOP=1 GH_APP=1 lancer
    [[ "$output" != *"offre gratuite"* && "$output" == *"Livraison automatique ? (non"* ]] || false
}
