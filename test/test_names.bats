#!/usr/bin/env bats
# bats sous Windows ignore les tests dont le nom contient des caractères non ASCII

@test "noms de tests en ASCII (compatibilite bats Windows)" {
    run bash -c "grep -h '^@test' '$BATS_TEST_DIRNAME'/*.bats | LC_ALL=C grep -n '[^ -~]'"
    [ -z "$output" ] || { echo "Noms non ASCII :"; echo "$output"; return 1; }
}

@test "CI Windows : les filtres de languages.bats couvrent tous les tests" {
    command -v python3 >/dev/null || skip "python3 absent"
    run python3 - "$BATS_TEST_DIRNAME" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]).parent
ci = (root / ".github/workflows/ci.yml").read_text()
filters = [re.compile(f) for f in re.findall(r"files: test/languages\.bats, filter: '([^']+)'", ci)]
names = re.findall(r'^@test "([^"]+)"', (root / "test/languages.bats").read_text(), re.M)
missing = [n for n in names if not any(f.search(n) for f in filters)]
print("\n".join(missing))
sys.exit(1 if missing or not filters else 0)
PY
    [ "$status" -eq 0 ] || { echo "Tests jamais lancés sous Windows :"; echo "$output"; return 1; }
}

@test "CI Windows : chaque fichier de tests est reparti dans une partie" {
    command -v python3 >/dev/null || skip "python3 absent"
    run python3 - "$BATS_TEST_DIRNAME" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]).parent
ci = (root / ".github/workflows/ci.yml").read_text()
listed = set(re.findall(r"test/[\w-]+\.bats", ci))
# as_posix : chemins en "/" aussi sous Windows, comme dans ci.yml
missing = sorted(p.relative_to(root).as_posix() for p in (root / "test").glob("*.bats") if p.relative_to(root).as_posix() not in listed)
print("\n".join(missing))
sys.exit(1 if missing else 0)
PY
    [ "$status" -eq 0 ] || { echo "Fichiers jamais lancés sous Windows :"; echo "$output"; return 1; }
}

@test "release : aucune version ecrite dans les fichiers (portee par le tag, mode tag)" {
    cd "$BATS_TEST_DIRNAME/.."
    # Plus de release-please : un marqueur oublié ne serait jamais mis à jour
    run git grep -n "x-release-please" -- . ':!CHANGELOG.md' ':!test/test_names.bats'
    [ -z "$output" ] || { echo "$output"; return 1; }
    [ ! -e release-please-config.json ] && [ ! -e .release-please-manifest.json ]
}

@test "release : livraison regroupee (fenetre, file distincte), jamais a chaque merge" {
    cd "$BATS_TEST_DIRNAME/.."
    # Une demande d'approbation en attente ne doit pas bloquer les merges :
    # une file par déclencheur
    grep -q 'group: release-${{ github.ref_name }}-${{ github.event.schedule || github.event_name }}' .github/workflows/release.yml
    # La demande de livraison n'est lancée qu'en fenêtre, à la main, ou à chaque merge si demandé
    grep -q "github.event.schedule == inputs.delivery-schedule" .github/workflows/release-auto.yml
    grep -q 'delivery-schedule: "0 7 \* \* 5"' .github/workflows/release.yml
    grep -q -- '- cron: "0 7 \* \* 5"' .github/workflows/release.yml
    # La livraison porte sur un instantané figé de develop (l'approbation ne
    # devient pas caduque quand develop avance)
    grep -q 'branche="livraison/' .github/workflows/release-auto.yml
}

# Bloc d'un job de release.yml, de sa clé jusqu'au job suivant (lecture #510)
job_release() {
    awk -v cle="  $1:" '
        $0 == cle { dedans = 1; next }
        dedans && /^  [A-Za-z0-9_-]+:$/ { exit }
        dedans' "$BATS_TEST_DIRNAME/../.github/workflows/release.yml"
}

@test "release : le job preversion appelle release-auto sans livraison" {
    p="$(job_release preversion)"
    [ -n "$p" ] || { echo "job preversion absent de release.yml"; return 1; }
    grep -q '^    uses: ./.github/workflows/release-auto.yml$' <<<"$p"
    # Aucune approbation à attendre ici : la livraison part du job release
    grep -q '^      delivery-environment: ""$' <<<"$p"
    grep -q '^      issues: read' <<<"$p"
    grep -q '^      app-client-id: ${{ vars.REPOWARDEN_APP_CLIENT_ID }}$' <<<"$p"
    [ -z "$(grep -n 'delivery-auto' <<<"$p")" ] || { echo "delivery-auto dans preversion :"; echo "$p"; return 1; }
    # Sur main, seule la release stable tourne : la préversion part de develop
    grep -q "^    if: github.ref_name == 'develop'" <<<"$p"
}

@test "release : le job release attend la preversion et ne la republie pas" {
    r="$(job_release release)"
    grep -q '^    needs: preversion$' <<<"$r"
    # Sur main, preversion sauté : la release stable tourne aussi
    grep -q "^    if: \${{ !cancelled() && needs.preversion.result != 'failure' }}" <<<"$r"
    grep -q '^      preversion: ""$' <<<"$r"
    grep -q '^    uses: ./.github/workflows/release-auto.yml$' <<<"$r"
    grep -q '^      delivery-environment: production$' <<<"$r"
    # Les suites de la version stable (main) ne dependent que de release
    for j in docs npm sign tag-major; do
        grep -q '^    needs: release$' <<<"$(job_release "$j")"
    done
    grep -q '^    needs: \[release, sign\]$' <<<"$(job_release provenance)"
}

@test "release : npm-next publie la preversion sans attendre l'approbation" {
    n="$(job_release npm-next)"
    [ -n "$n" ] || { echo "job npm-next absent de release.yml"; return 1; }
    grep -q '^    needs: preversion$' <<<"$n"
    grep -q "needs.preversion.outputs.prerelease_created == 'true'" <<<"$n"
    grep -q 'needs.preversion.outputs.prerelease_tag' <<<"$n"
    # Surtout pas needs release : qui attend la livraison approuvée (#510)
    [ -z "$(grep -n 'needs\.release\.' <<<"$n")" ] || { echo "npm-next depend encore de release :"; echo "$n"; return 1; }
}

@test "release : tickets en preprod sur la preversion, done sur la release" {
    p="$(job_release tickets-preprod)"
    [ -n "$p" ] || { echo "job tickets-preprod absent de release.yml"; return 1; }
    grep -q '^    needs: preversion$' <<<"$p"
    grep -q "needs.preversion.outputs.prerelease_created == 'true'" <<<"$p"
    grep -q 'needs.preversion.outputs.prerelease_tag' <<<"$p"
    grep -q '^      app-key: ${{ secrets.REPOWARDEN_APP_KEY }}$' <<<"$p"
    t="$(job_release tickets)"
    grep -q '^    needs: release$' <<<"$t"
    grep -q "needs.release.outputs.release_created == 'true' || needs.release.outputs.delivered_without_version != ''" <<<"$t"
    # La preversion est traitée par tickets-preprod : plus ici
    [ -z "$(grep -n 'prerelease' <<<"$t")" ] || { echo "tickets attend encore une preversion :"; echo "$t"; return 1; }
}

@test "release : chaque job post-release garde !cancelled et needs.release.result == 'success' (#514)" {
    # #514 : sur main, preversion est saute : GitHub saute aussi ses descendants sans !cancelled()
    for j in docs npm tag-major sign provenance tickets; do
        b="$(job_release "$j")"
        [ -n "$b" ] || { echo "job $j absent de release.yml"; return 1; }
        grep -q "^    if: \${{ !cancelled() && needs.release.result == 'success' &&" <<<"$b" || { echo "garde manquante dans $j :"; echo "$b"; return 1; }
    done
}

@test "release : le job provenance attend le succes de sign (#514)" {
    p="$(job_release provenance)"
    [ -n "$p" ] || { echo "job provenance absent de release.yml"; return 1; }
    # #514 : la provenance ne tourne que si sign a reussi
    grep -q "needs.sign.result == 'success'" <<<"$p" || { echo "needs.sign.result manquant :"; echo "$p"; return 1; }
}

@test "release : aucune configuration actionlint reduite au silence (#514)" {
    cd "$BATS_TEST_DIRNAME/.."
    # #514 : pas de regle actionlint qui reduirait les erreurs au silence
    [[ ! -e .github/actionlint.yaml ]] || false
    [[ ! -e .github/actionlint.yml ]] || false
}

@test "scripts : aucun tube vers grep -q ou head (SIGPIPE + pipefail = echec aleatoire)" {
    cd "$BATS_TEST_DIRNAME/.."
    # grep -q et head s'arrêtent avant la fin : la commande qui écrit reçoit
    # SIGPIPE et, avec pipefail, la condition échoue au hasard du timing
    run git grep -nE '\| *(grep -[a-zA-Z]*q|head)\b' -- ci hooks bin install.sh
    [ -z "$output" ] || { echo "$output"; return 1; }
    # awk qui sort avant la fin (exit) : même effet sur la commande qui écrit
    run git grep -nE '\| *awk [^|]*\bexit\b' -- ci hooks bin install.sh
    [ -z "$output" ] || { echo "$output"; return 1; }
    # Même chose quand le tube est coupé en fin de ligne
    run awk 'FNR == 1 { prev = "" } prev ~ /\|[ \t]*$/ && $0 ~ /^[ \t]*(grep -[a-zA-Z]*q|head)([ \t]|$)/ { print FILENAME ":" FNR } { prev = $0 }' \
        $(git ls-files ci hooks bin install.sh)
    [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "depot dans l'organisation : aucun lien vers l'ancien proprietaire (hors historique)" {
    cd "$BATS_TEST_DIRNAME/.."
    # CHANGELOG.md : historique ; la personne (licence, auteur, CODEOWNERS) reste citée
    ancien="simbienvenue""houlboumi" # découpé : ce test ne se trouve pas lui-même
    run git grep -n -i -e "$ancien/repowarden" -e "$ancien\.github\.io" -- . ':!CHANGELOG.md'
    [ -z "$output" ] || { echo "Liens vers l'ancien propriétaire :"; echo "$output"; return 1; }
    # Ancien dépôt, tous propriétaires (…/repogarde/.github/…, …/repogarde@v3, site) : GitHub
    # ne redirige pas les workflows réutilisables. Seuls l'historique, la doc
    # de migration et les projets à migrer de ses tests le citent
    ancien="repo""garde"
    run git grep -n -i -E -e "[A-Za-z0-9_.-]+/$ancien(@|/\.github/)" -e "github\.io/$ancien" -- . ':!CHANGELOG.md' ':!docs/migration-v4*.md' ':!test/migrer.bats'
    [ -z "$output" ] || { echo "Chemins vers l'ancien dépôt :"; echo "$output"; return 1; }
}

@test "tests : conditions [[ ]] protegees par || false (set -e ignore leur echec sous bash 3.2)" {
    # Sous bash < 4.1 (macOS), set -e n'arrête pas un test sur l'échec d'une
    # condition [[ … ]] : le test passerait à tort. Hors heredocs (scripts
    # factices), chaque ligne qui commence par [[ finit donc par || false.
    run awk '
        FNR == 1 { fin = "" }
        fin != "" { t = $0; sub(/^[ \t]+/, "", t); if (t == fin) fin = ""; next }
        /^[ \t]*\[\[/ && !/\|\| false[ \t]*$/ { print FILENAME ":" FNR ": " $0 }
        match($0, /<<-?[ \t]*["\047]?[A-Za-z_]+/) {
            fin = substr($0, RSTART, RLENGTH); gsub(/<<-?[ \t]*|["\047]/, "", fin)
        }' "$BATS_TEST_DIRNAME"/*.bats
    [ -z "$output" ] || { echo "Conditions [[ ]] sans || false :"; echo "$output"; return 1; }
}
