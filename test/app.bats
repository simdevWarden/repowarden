#!/usr/bin/env bats
# GitHub App des workflows (bin/app) : gh simulé, navigateur simulé (le clic
# « Create » de GitHub renvoie vers la page locale avec un code)

load helpers

APP="$BATS_TEST_DIRNAME/../bin/app"

setup() {
    require node
    require curl
    setup_repo
    initial_commit
    F="$BATS_TEST_TMPDIR/gh"
    mkdir -p "$F/bin"
    cat >"$F/bin/gh" <<'GH'
#!/usr/bin/env bash
# gh simulé : variables et secrets du dépôt dans $FAKE, journal dans $FAKE/log
echo "$*" >>"$FAKE/log"
case "$1 $2" in
    "repo view") echo moi/projet ;;
    "api users/moi") echo User ;;
    "variable get") cat "$FAKE/var.$3" 2>/dev/null || exit 1 ;;
    "variable set") n="$3"; while [ $# -gt 0 ]; do [ "$1" = --body ] && printf '%s' "$2" >"$FAKE/var.$n"; shift; done ;;
    "secret list") for f in "$FAKE"/secret.*; do [ -e "$f" ] && echo "${f##*/secret.}	2026-10-10"; done ;;
    "secret set") cat >"$FAKE/secret.$3" ;;
    "api -X")
        [ "$4" = "app-manifests/c0de/conversions" ] || exit 1
        cat "$FAKE/conversion.json" ;;
    # App existante sous ce nom (orpheline d'un essai interrompu)
    "api apps/"*) [ "$(cat "$FAKE/app_existe" 2>/dev/null)" = "${2#apps/}" ] && echo "${2#apps/}" ;;
    "api repos/moi/projet/installation")
        # au nom de l'App : jeton signé (en-tête.charge.signature), App installée
        [[ "$*" =~ Authorization:\ Bearer\ [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+ ]] || exit 1
        echo "${BASH_REMATCH[0]}" >"$FAKE/jwt"
        [ -e "$FAKE/installee" ] || exit 1 ;;
esac
exit 0
GH
    chmod +x "$F/bin/gh"
    # Réponse de GitHub à la conversion : vraie clé RSA (le jeton de l'App est signé avec)
    node -e '
        const { privateKey } = require("crypto").generateKeyPairSync("rsa", { modulusLength: 2048 });
        process.stdout.write(JSON.stringify({ id: 7, slug: "repowarden-moi", client_id: "Iv1.abc",
            pem: privateKey.export({ type: "pkcs1", format: "pem" }) }));
    ' >"$F/conversion.json"
    # Navigateur : page locale → état lu dans le formulaire → retour de GitHub
    # avec le code ; page d'installation → App installée
    cat >"$F/bin/navigateur" <<'NAV'
#!/usr/bin/env bash
case "$1" in
    http://127.0.0.1:*)
        page="$(curl -s "$1")"
        echo "$page" >"$FAKE/page"
        etat="$(sed -n 's/.*state=\([0-9a-f]*\).*/\1/p' <<<"$page")"
        curl -s "${1%/}/fin?code=c0de&state=$etat" >/dev/null ;;
    */installations/new) touch "$FAKE/installee" ;;
esac
NAV
    chmod +x "$F/bin/navigateur"
    # poste normal, y compris quand les tests tournent dans un conteneur
    export PATH="$F/bin:$PATH" FAKE="$F" REPOWARDEN_OPEN="$F/bin/navigateur" REPOWARDEN_CONTENEUR=0
}

@test "app init : App creee (manifest, permissions minimales), identifiants ranges sans etre affiches, installee" {
    run "$APP" init
    [ "$status" -eq 0 ]
    # formulaire envoye a GitHub : compte personnel, manifest sans webhook ni administration
    grep -q 'action="https://github.com/settings/apps/new?state=' "$F/page"
    grep -q '&quot;hook_attributes&quot;:{&quot;url&quot;:&quot;https://github.com/moi/projet&quot;,&quot;active&quot;:false}' "$F/page"
    grep -q '&quot;pull_requests&quot;:&quot;write&quot;' "$F/page"
    ! grep -q 'administration' "$F/page"
    [ "$(cat "$F/var.REPOWARDEN_APP_CLIENT_ID")" = Iv1.abc ]
    [ "$(cat "$F/var.REPOWARDEN_APP_SLUG")" = repowarden-moi ]
    [ "$(cat "$F/var.REPOWARDEN_APP_ID")" = 7 ]
    grep -q "BEGIN RSA PRIVATE KEY" "$F/secret.REPOWARDEN_APP_KEY"
    [[ "$output" != *"PRIVATE KEY"* ]] || false
    [[ "$output" == *"repowarden-moi installée sur moi/projet"* ]] || false
    # installation verifiee au nom de l'App, jeton emis par son client
    node -e 'const p=JSON.parse(Buffer.from(process.argv[1].split(".")[1],"base64url"));if(p.iss!=="Iv1.abc")process.exit(1)' \
        "$(sed 's/.*Bearer //' "$F/jwt")"
}

@test "app init : relance -> rien de recree ; --administration -> permission demandee" {
    run "$APP" init
    [ "$status" -eq 0 ]
    : >"$F/log"
    run "$APP" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"déjà configurée"* ]] || false
    [[ "$output" == *"non vérifiée"* ]] || false
    ! grep -q "app-manifests" "$F/log"
    rm -f "$F"/var.* "$F"/secret.*
    run "$APP" init --administration
    grep -q '&quot;administration&quot;:&quot;write&quot;' "$F/page"
}

@test "app init --bot : App du bot (workflows, administration), identifiants a part, toutes les installations" {
    run "$APP" init --bot
    [ "$status" -eq 0 ]
    grep -q '&quot;name&quot;:&quot;repowarden-bot-moi&quot;' "$F/page"
    grep -q '&quot;administration&quot;:&quot;write&quot;' "$F/page"
    grep -q '&quot;workflows&quot;:&quot;write&quot;' "$F/page"
    [ "$(cat "$F/var.REPOWARDEN_BOT_CLIENT_ID")" = Iv1.abc ]
    grep -q "BEGIN RSA PRIVATE KEY" "$F/secret.REPOWARDEN_BOT_KEY"
    # l'App des workflows du dépôt n'est pas touchée
    [ ! -e "$F/var.REPOWARDEN_APP_CLIENT_ID" ] && [ ! -e "$F/secret.REPOWARDEN_APP_KEY" ]
    [[ "$output" == *"All repositories"* ]] || false
    [[ "$output" == *"REPOWARDEN_BOT_CLIENT_ID"* ]] || false
}

@test "app init : retour de GitHub avec un mauvais etat -> refuse, rien de range" {
    cat >"$F/bin/navigateur" <<'NAV'
#!/usr/bin/env bash
case "$1" in
    */installations/new) touch "$FAKE/installee"; exit 0 ;;
esac
curl -s "${1%/}/fin?code=c0de&state=faux" >/dev/null
curl -s "${1%/}/fin?code=c0de&state=$(sed -n 's/.*state=\([0-9a-f]*\).*/\1/p' <<<"$(curl -s "$1")")" >/dev/null
NAV
    run "$APP" init
    # le faux etat est ignore ; seul le bon retour est accepte
    [ "$(grep -c "app-manifests" "$F/log")" -eq 1 ]
}

@test "app init dans un conteneur sans redirection de ports -> marche a suivre, rien d'ouvert ni de cree" {
    export REPOWARDEN_CONTENEUR=1
    run "$APP" init --bot
    [ "$status" -eq 1 ]
    [[ "$output" == *"Conteneur détecté"* ]] || false
    [[ "$output" == *"npx repowarden app init --repo moi/projet --bot"* ]] || false
    [ ! -e "$F/page" ]
    ! grep -q "app-manifests" "$F/log"
    ! ls "$F"/var.* "$F"/secret.* 2>/dev/null
}

@test "app init dans VS Code Dev Containers (ports rediriges) -> creation normale" {
    unset REPOWARDEN_CONTENEUR
    export REMOTE_CONTAINERS=true
    run "$APP" init
    [ "$status" -eq 0 ]
    [ "$(cat "$F/var.REPOWARDEN_APP_CLIENT_ID")" = Iv1.abc ]
}

@test "app init : page locale jamais consultee -> arret au delai, marche a suivre, rien de cree" {
    printf '#!/usr/bin/env bash\nexit 0\n' >"$F/bin/navigateur"
    export REPOWARDEN_APP_DELAI=1
    run "$APP" init --nom essai
    [ "$status" -eq 1 ]
    [[ "$output" == *"non consultée en 1 s"* ]] || false
    [[ "$output" == *"npx repowarden app init --repo moi/projet --nom essai"* ]] || false
    ! grep -q "app-manifests" "$F/log"
    ! ls "$F"/var.* "$F"/secret.* 2>/dev/null
}

@test "app init : relance, App configuree mais desinstallee -> pas de succes annonce, lien d'installation" {
    run "$APP" init
    [ "$status" -eq 0 ]
    # désinstallée du dépôt ; la relance n'a pas la clé privée
    rm -f "$F/installee"
    run "$APP" init
    [ "$status" -eq 0 ]
    [[ "$output" == *"déjà configurée"* ]] || false
    [[ "$output" != *"utilisent désormais l'App"* ]] || false
    [[ "$output" != *"installée sur moi/projet"* ]] || false
    [[ "$output" == *"non vérifiée"*"https://github.com/apps/repowarden-moi/installations/new"* ]] || false
}

@test "app init : nom d'App deja pris -> echec avec la marche a suivre, aucune page ouverte" {
    echo repowarden-moi >"$F/app_existe"
    run "$APP" init
    [ "$status" -eq 1 ]
    [[ "$output" == *"repowarden-moi"* ]] || false
    [[ "$output" == *"--nom"* ]] || false
    [[ "$output" == *"https://github.com/settings/apps"* ]] || false
    [ ! -e "$F/page" ]
    ! grep -q "app-manifests" "$F/log"
    # autre nom : création normale
    run "$APP" init --nom autre-nom
    [ "$status" -eq 0 ]
    grep -q '&quot;name&quot;:&quot;autre-nom&quot;' "$F/page"
}
