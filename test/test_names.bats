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
