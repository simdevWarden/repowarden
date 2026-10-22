#!/usr/bin/env bats
# Secrets refusés au pre-commit : fichier, ligne, règle et marche à suivre,
# jamais la valeur. gitleaks simulé (rapport au format de gitleaks 8.30), plus
# un test avec le vrai gitleaks s'il est installé.

load helpers

# Rapport JSON de gitleaks (--report-format json, --redact) : une fuite par
# argument « fichier|ligne|règle », chemin déjà échappé comme le fait Go
rapport() {
    local premier=1 f l r
    echo "["
    for x in "$@"; do
        IFS='|' read -r f l r <<<"$x"
        [ "$premier" = 1 ] || echo " },"
        premier=0
        printf ' {\n  "RuleID": "%s",\n  "StartLine": %s,\n  "Match": "REDACTED",\n  "Secret": "REDACTED",\n  "File": "%s",\n  "Tags": [],\n  "Fingerprint": "%s:%s:%s"\n' \
            "$r" "$l" "$f" "$f" "$r" "$l"
    done
    [ "$premier" = 1 ] || echo " }"
    echo "]"
}

# gitleaks simulé : écrit $BATS_TEST_TMPDIR/rapport.json à --report-path et
# sort avec GITLEAKS_CODE (42 : fuite), journal sur stderr
fake_gitleaks() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gitleaks" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
    [ "$1" = --report-path ] && cp "$BATS_TEST_TMPDIR/rapport.json" "$2"
    shift
done
echo "journal de gitleaks" >&2
exit "${GITLEAKS_CODE:-0}"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/gitleaks"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

setup() {
    setup_repo
    initial_commit
    git switch -q -c feat/x
    git config --unset repowarden.skip
    echo "x" >a.txt
    git add a.txt
}

@test "secrets : fuite -> fichier, ligne, regle et marche a suivre, commit refuse" {
    fake_gitleaks
    rapport "config/app.ini|3|github-pat" >"$BATS_TEST_TMPDIR/rapport.json"
    GITLEAKS_CODE=42 run git commit -q -m "feat: config"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Secret détecté : commit refusé."* ]] || false
    [[ "$output" == *"config/app.ini:3 (github-pat)"* ]] || false
    [[ "$output" == *"Que faire :"*"révoquer"* ]] || false
    [[ "$output" == *".gitleaksignore"*"config/app.ini:github-pat:3"* ]] || false
    [[ "$output" != *"REDACTED"* ]] || false
    [[ "$output" != *"journal de gitleaks"* ]] || false
    [ -z "$(git log --format=%s main..)" ]
}

@test "secrets : plusieurs fuites, chemins echappes par JSON relus tels quels" {
    fake_gitleaks
    rapport 'a&b \"c\".ini|1|github-pat' 'd\\e<f>.env|12|generic-api-key' >"$BATS_TEST_TMPDIR/rapport.json"
    GITLEAKS_CODE=42 run git commit -q -m "feat: config"
    [ "$status" -ne 0 ]
    [[ "$output" == *'a&b "c".ini:1 (github-pat)'* ]] || false
    [[ "$output" == *'d\e<f>.env:12 (generic-api-key)'* ]] || false
    [[ "$output" == *'d\e<f>.env:generic-api-key:12'* ]] || false
}

@test "secrets : rapport illisible -> commande a lancer, sans rien deviner" {
    fake_gitleaks
    echo "format inconnu" >"$BATS_TEST_TMPDIR/rapport.json"
    GITLEAKS_CODE=42 run git commit -q -m "feat: config"
    [ "$status" -ne 0 ]
    [[ "$output" == *"rapport de gitleaks illisible"*"gitleaks git --pre-commit --staged --redact"* ]] || false
    [[ "$output" == *"Que faire :"* ]] || false
}

@test "secrets : gitleaks en echec -> refus, jamais presente comme une fuite" {
    fake_gitleaks
    echo "[]" >"$BATS_TEST_TMPDIR/rapport.json"
    GITLEAKS_CODE=1 run git commit -q -m "feat: config"
    [ "$status" -ne 0 ]
    [[ "$output" == *"gitleaks en échec (code 1)"* ]] || false
    [[ "$output" == *"journal de gitleaks"* ]] || false
    [[ "$output" != *"Secret détecté"* ]] || false
}

@test "secrets : aucune fuite -> commit accepte, aucun fichier temporaire laisse" {
    fake_gitleaks
    echo "[]" >"$BATS_TEST_TMPDIR/rapport.json"
    export TMPDIR="$BATS_TEST_TMPDIR/tmp"
    mkdir -p "$TMPDIR"
    run git commit -q -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" != *"journal de gitleaks"* ]] || false
    [ -z "$(ls -A "$TMPDIR")" ]
}

# SANS_GITLEAKS = PATH sans aucun dossier qui contient gitleaks
sans_gitleaks() {
    local d
    SANS_GITLEAKS=""
    while IFS= read -r d; do
        [ -x "$d/gitleaks" ] || SANS_GITLEAKS="$SANS_GITLEAKS${SANS_GITLEAKS:+:}$d"
    done <<<"$(tr ':' '\n' <<<"$PATH")"
}

@test "secrets : gitleaks absent -> avertissement avec l'installation, commit accepte" {
    sans_gitleaks
    PATH="$SANS_GITLEAKS" run git commit -q -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gitleaks absent"* ]] || false
    [[ "$output" == *"la CI (vérification secrets) fera le contrôle"*"Installation : "* ]] || false
}

# --- Fichier sensible ni suivi ni ignoré : signalé, jamais lu ni bloquant ----

@test "fichiers sensibles : .env non ignore -> avertissement et ligne .gitignore, commit accepte" {
    fake_gitleaks
    echo "API_KEY=valeur-tres-secrete" >.env
    mkdir -p outils
    echo "valeur-tres-secrete" >outils/set-npm-TOKEN.sh
    run git commit -q -m "feat: a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fichier sensible ni suivi ni ignoré"*"Lignes à ajouter à .gitignore"* ]] || false
    [[ "$output" == *"    .env"* ]] || false
    [[ "$output" == *"    outils/set-npm-TOKEN.sh"* ]] || false
    [[ "$output" != *"valeur-tres-secrete"* ]] || false
    [ "$(git log -1 --format=%s)" = "feat: a" ]
    # rien n'a été indexé à la place de l'utilisateur
    [ -z "$(git ls-files .env outils)" ]
}

@test "fichiers sensibles : ignore, .env.example ou suivi -> rien" {
    fake_gitleaks
    echo "x" >.env
    echo "x" >.env.example
    echo "x" >cle.pem
    printf '.env\n' >.gitignore
    echo "cle.pem" >>.git/info/exclude
    git add .gitignore
    git commit -q -m "chore: ignore"
    echo "x" >id_rsa_test
    git add id_rsa_test
    run git commit -q -m "feat: b"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Fichier sensible"* ]] || false
}

@test "fichiers sensibles : motifs regles par sensitiveFiles, skip sensitive-files" {
    fake_gitleaks
    echo "x" >.env
    echo "x" >prod.secrets.yml
    printf '[repowarden]\n\tsensitiveFiles = *.yml\n' >.repowarden.conf
    git add .repowarden.conf
    run git commit -q -m "feat: a"
    [[ "$output" == *"    prod.secrets.yml"* ]] || false
    [[ "$output" != *"    .env"* ]] || false
    git config repowarden.skip sensitive-files
    echo "y" >>a.txt
    git add a.txt
    run git commit -q -m "feat: b"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Fichier sensible"* ]] || false
}

@test "fichiers sensibles : messages en anglais" {
    fake_gitleaks
    echo "x" >.env
    REPOWARDEN_LANG=en run git commit -q -m "feat: a"
    [[ "$output" == *"Sensitive file neither tracked nor ignored"*"    .env"* ]] || false
}

@test "statut : fichier sensible signale, gitleaks absent -> installation en etape suivante" {
    local statut="$BATS_TEST_DIRNAME/../bin/statut"
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
    git config --global alias.cc "!bash \"$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)/bin/commit\""
    echo "API_KEY=valeur-tres-secrete" >.env
    garde_branche
    sans_gitleaks
    PATH="$SANS_GITLEAKS" run "$statut"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Fichier sensible ni suivi ni ignoré"*"    .env"* ]] || false
    [[ "$output" != *"valeur-tres-secrete"* ]] || false
    [[ "$output" == *"Étape suivante : "*"gitleaks"* ]] || false
    # gitleaks présent, .env ignoré : plus rien à signaler
    fake_gitleaks
    echo ".env" >.gitignore
    run "$statut"
    [[ "$output" != *"Fichier sensible"* ]] || false
    [[ "$output" == *"Tout est prêt"* ]] || false
}

@test "secrets : messages en anglais" {
    fake_gitleaks
    rapport "config/app.ini|3|github-pat" >"$BATS_TEST_TMPDIR/rapport.json"
    REPOWARDEN_LANG=en GITLEAKS_CODE=42 run git commit -q -m "feat: config"
    [ "$status" -ne 0 ]
    [[ "$output" == *"config/app.ini:3 (github-pat)"* ]] || false
    [[ "$output" == *".gitleaksignore"* ]] || false
    [[ "$output" != *"Que faire"* ]] || false
}

@test "secrets : vrai gitleaks -> fichier et ligne, valeur jamais affichee" {
    require gitleaks
    printf 'nom = x\ntoken = ghp_%s\n' "4Rk9vQ2xLm7TzP0aWc3Ny8BdHs5Ju1Ef6GiX" >config.ini # factice
    git add config.ini
    run git commit -q -m "feat: config"
    [ "$status" -ne 0 ]
    [[ "$output" == *"config.ini:2 (github-pat)"* ]] || false
    [[ "$output" != *"4Rk9vQ2xLm7TzP0aWc3Ny8BdHs5Ju1Ef6GiX"* ]] || false
}
