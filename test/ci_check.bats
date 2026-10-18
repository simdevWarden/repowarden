#!/usr/bin/env bats
# ci/check.sh : mêmes règles que les hooks, en CI

load helpers

CHECK="$BATS_TEST_DIRNAME/../ci/check.sh"

setup() {
    setup_repo
    # contexte CI : pas de hooks (prepare-commit-msg corrigerait les messages testés)
    mkdir -p "$BATS_TEST_TMPDIR/nohooks"
    git config core.hooksPath "$BATS_TEST_TMPDIR/nohooks"
    git config --unset repowarden.skip # contexte CI : aucune config locale
    initial_commit
    BASE_SHA="$(git rev-parse HEAD)"
    git switch -q -c feat/x
    export REPOWARDEN_BASE="$BASE_SHA" REPOWARDEN_BRANCH=feat/x
    # check.sh met REPOWARDEN_BIN (défaut ~/.local/bin) en tête du PATH : un
    # ruff installé là par pipx passerait avant les faux outils des tests
    mkdir -p "$BATS_TEST_TMPDIR/repowarden-bin"
    export REPOWARDEN_BIN="$BATS_TEST_TMPDIR/repowarden-bin"
    # isole des variables CI de l'environnement d'exécution
    unset GITHUB_ACTIONS GITHUB_BASE_REF GITHUB_HEAD_REF GITHUB_REF_NAME CI_COMMIT_BRANCH \
        CI_MERGE_REQUEST_SOURCE_BRANCH_NAME CI_MERGE_REQUEST_DIFF_BASE_SHA \
        CI_MERGE_REQUEST_TARGET_BRANCH_NAME REPOWARDEN_TARGET
}

@test "ci : commits conformes" {
    git commit -q --no-verify --allow-empty -m "feat: a"
    git commit -q --no-verify --allow-empty -m "fix(api): b"
    run "$CHECK" commits
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 commit(s) conforme(s)"* ]] || false
}

@test "ci : commit non conforme refuse" {
    git commit -q --no-verify --allow-empty -m "feat: a"
    git commit -q --no-verify --allow-empty -m "wip"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"« wip »"* ]] || false
}

@test "ci : fixup! refuse (a squasher avant merge)" {
    git commit -q --no-verify --allow-empty -m "fixup! feat: a"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"squasher"* ]] || false
}

@test "ci : nom de branche" {
    run "$CHECK" branch
    [ "$status" -eq 0 ]
    REPOWARDEN_BRANCH=Mauvais run "$CHECK" branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"feat/mauvais"* ]] || false
}

@test "ci : branche detectee depuis les variables GitLab" {
    unset REPOWARDEN_BRANCH
    CI_COMMIT_BRANCH=Mauvais run "$CHECK" branch
    [ "$status" -ne 0 ]
    CI_MERGE_REQUEST_SOURCE_BRANCH_NAME=fix/ok run "$CHECK" branch
    [ "$status" -eq 0 ]
}

@test "ci : tag, pas de verification de branche" {
    unset REPOWARDEN_BRANCH
    CI_COMMIT_TAG=v1.0.0 CI_COMMIT_BRANCH="" run "$CHECK" branch
    [ "$status" -eq 0 ]
}

@test "ci : format non conforme refuse, dossier de travail restaure" {
    require ruff
    printf 'x  =  1\n' >a.py
    git add a.py
    git commit -q --no-verify -m "feat: a"
    run "$CHECK" format
    [ "$status" -ne 0 ]
    [[ "$output" == *"a.py : non formaté"* ]] || false
    [ -z "$(git status --porcelain)" ]
}

@test "ci : format conforme" {
    require ruff
    printf 'x = 1\n' >a.py
    git add a.py
    git commit -q --no-verify -m "feat: a"
    run "$CHECK" format
    [ "$status" -eq 0 ]
}

@test "ci : tests des projets touches" {
    require make
    printf 'test:\n\t@echo ci-make && exit 1\n' >Makefile
    git add Makefile
    git commit -q --no-verify -m "build: make"
    run "$CHECK" tests
    [ "$status" -ne 0 ]
    [[ "$output" == *"ci-make"* ]] || false
}

@test "ci : secrets detectes" {
    require gitleaks
    printf 'token = ghp_%s\n' "4Rk9vQ2xLm7TzP0aWc3Ny8BdHs5Ju1Ef6GiX" >config.ini # factice
    git add config.ini
    git commit -q --no-verify -m "feat: config"
    run "$CHECK" secrets
    [ "$status" -ne 0 ]
}

@test "ci : skip via .repowarden.conf versionne" {
    git commit -q --no-verify --allow-empty -m "wip"
    printf '[repowarden]\n\tskip = commit-msg\n' >.repowarden.conf
    git add .repowarden.conf
    git commit -q --no-verify -m "chore: conf"
    run "$CHECK" commits
    [ "$status" -eq 0 ]
    [[ "$output" == *"Désactivé par .repowarden.conf"* ]] || false
}

@test "ci : mode strict, outil manquant = echec" {
    printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >package.json
    printf 'const a=1\n' >a.js
    git add -A
    git commit -q --no-verify -m "feat: js"
    run env PATH="$(dirname "$(command -v git)"):/usr/bin:/bin" REPOWARDEN_STRICT=true "$CHECK" format
    [ "$status" -ne 0 ]
    [[ "$output" == *"prettier introuvable"* ]] || false
}

@test "ci : annotations GitHub" {
    git commit -q --no-verify --allow-empty -m "wip"
    GITHUB_ACTIONS=true run "$CHECK" commits
    [[ "$output" == *"::error title=repowarden::"* ]] || false
}

@test "ci : verification inconnue" {
    run "$CHECK" nimporte
    [ "$status" -ne 0 ]
}

@test "ci : formateur en erreur (syntaxe) -> echec" {
    require ruff
    printf 'def f(:\n' >casse.py
    git add casse.py
    git commit -q --no-verify -m "feat: casse"
    run "$CHECK" format
    [ "$status" -ne 0 ]
}

@test "ci : titre de PR conforme / non conforme (message du commit en squash)" {
    git commit -q --no-verify --allow-empty -m "feat: a"
    REPOWARDEN_PR_TITLE="feat(api): ajoute la route" run "$CHECK" commits
    [ "$status" -eq 0 ]
    [[ "$output" == *"Titre de la PR conforme"* ]] || false
    REPOWARDEN_PR_TITLE="Ajout de la route" run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"Titre de la PR « Ajout de la route »"* ]] || false
}

@test "ci : requirements.txt sans tests (ex. outils de doc) -> pas d'exigence pytest en strict" {
    mkdir -p docs
    printf 'mkdocs==1.6.1\n' >docs/requirements.txt
    printf '# Doc\n' >docs/index.md
    git add -A
    git commit -q --no-verify -m "docs: site"
    run env REPOWARDEN_STRICT=true PATH="$(dirname "$(command -v git)"):/usr/bin:/bin" "$CHECK" tests
    [ "$status" -eq 0 ]
    [[ "$output" == *"Python : aucun test"* ]] || false
    [[ "$output" != *"pytest absent"* ]] || false
}

@test "ci : suffixe (#NN) d'un merge squash non compte dans les 72 caracteres" {
    # 67 caractères écrits + « (#31) » ajouté par GitHub = 73
    git commit -q --no-verify --allow-empty -m "docs(securite): vérification SLSA corrigée, piège du dossier déplacé (#31)"
    run "$CHECK" commits
    [ "$status" -eq 0 ]
    git commit -q --no-verify --allow-empty -m "docs: $(printf 'a%.0s' {1..70})"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
}

@test "longueur : caracteres et non octets, meme en locale C (Git Bash Windows)" {
    source "$HOOKS/lib/common.sh"
    LC_ALL=C authored_length "docs(securite): vérification SLSA corrigée, piège du dossier déplacé"
    [ "$REPLY" -eq 68 ]
    authored_length "fix: àéèùçôîï (#12)"
    [ "$REPLY" -eq 13 ]
}

@test "ci : flux develop, cibles de PR autorisees" {
    git config repowarden.integrationBranch develop
    git config repowarden.allowedBranches "main develop release/* release-please--* dependabot/*"
    for paire in feat/x:develop develop:main release/1.2.0:develop hotfix/crash:develop \
        dependabot/maven/x:develop release-please--branches--main:main; do
        REPOWARDEN_BRANCH="${paire%%:*}" REPOWARDEN_TARGET="${paire#*:}" run "$CHECK" branch
        [ "$status" -eq 0 ] || { echo "devrait passer : $paire"; echo "$output"; return 1; }
    done
}

@test "ci : flux develop, instantane de livraison (livraison/vX.Y.Z) admis vers main, meme avec allowedBranches" {
    git config repowarden.integrationBranch develop
    git config repowarden.allowedBranches "main develop"
    REPOWARDEN_BRANCH=livraison/v4.4.0 REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    # vers develop : refusee (un instantane ne va que vers main)
    REPOWARDEN_BRANCH=livraison/v4.4.0 REPOWARDEN_TARGET=develop run "$CHECK" branch
    [ "$status" -ne 0 ]
    # toute autre source vers main reste refusee
    REPOWARDEN_BRANCH=release/4.4.0 REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -ne 0 ]
}

@test "ci : flux develop, seul develop entre dans main (hotfix et release compris)" {
    git config repowarden.integrationBranch develop
    for b in hotfix/crash release/1.2.0 fix/x; do
        REPOWARDEN_BRANCH="$b" REPOWARDEN_TARGET=main run "$CHECK" branch
        [ "$status" -ne 0 ] || { echo "devrait être refusée vers main : $b"; return 1; }
    done
}

@test "ci : branche develop presente mais flux non declare -> travail refuse vers main" {
    git update-ref refs/remotes/origin/develop HEAD
    REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"la branche develop existe mais .repowarden.conf ne déclare pas"* ]] || false
    [[ "$output" == *"integrationBranch = develop"* ]] || false
    # develop elle-même, ou une autre cible : rien à signaler
    REPOWARDEN_BRANCH=develop REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -eq 0 ]
    git config repowarden.mainBranch trunk
    REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -eq 0 ]
    git config --unset repowarden.mainBranch
    # le statut le signale aussi
    run "$BATS_TEST_DIRNAME/../bin/statut"
    [[ "$output" == *"flux develop → main n'est pas déclaré"* ]] || false
    # flux déclaré : règles du flux develop, plus d'alerte
    git config repowarden.integrationBranch develop
    REPOWARDEN_TARGET=develop run "$CHECK" branch
    [ "$status" -eq 0 ]
    run "$BATS_TEST_DIRNAME/../bin/statut"
    [[ "$output" != *"n'est pas déclaré"* ]] || false
    # sans branche develop : projet « main seule », PR vers main admise
    git config --unset repowarden.integrationBranch
    git update-ref -d refs/remotes/origin/develop
    REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -eq 0 ]
}

@test "ci : flux develop, mauvaise cible refusee avec la correction" {
    git config repowarden.integrationBranch develop
    REPOWARDEN_TARGET=main run "$CHECK" branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"cible attendue develop"* ]] || false
    [[ "$output" == *"gh pr edit --base develop"* ]] || false
}

@test "ci : PR depuis une branche persistante -> jamais rouge (inversee sans objet, retour sans titre)" {
    git config repowarden.integrationBranch develop
    # develop vers une branche de travail, main vers autre que develop : sans objet
    for paire in develop:feat/184-x develop:release/1.0.0 main:feat/x; do
        REPOWARDEN_BRANCH="${paire%%:*}" REPOWARDEN_TARGET="${paire#*:}" run "$CHECK"
        [ "$status" -eq 0 ] || { echo "devrait passer : $paire"; echo "$output"; return 1; }
        [[ "$output" == *"sans objet"* && "$output" == *"git merge origin/develop"* ]] || false
    done
    # retour main -> develop : titre libre (merge commit), le reste verifie
    git commit -q --no-verify --allow-empty -m "fix: a"
    REPOWARDEN_BRANCH=main REPOWARDEN_TARGET=develop REPOWARDEN_PR_TITLE="Main" run "$CHECK" commits branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"titre de la PR n'est pas vérifié"* ]] || false
    # une PR de travail garde la verification du titre
    REPOWARDEN_TARGET=develop REPOWARDEN_PR_TITLE="Main" run "$CHECK" commits
    [ "$status" -ne 0 ]
}

@test "ci : sans integrationBranch, toute cible acceptee" {
    REPOWARDEN_TARGET=develop run "$CHECK" branch
    [ "$status" -eq 0 ]
    [[ "$output" != *"Cible"* ]] || false
}

# --- ci/fix-pr.sh (entrée fix-pr de l'action) : gh simulé ----------------------

FIX="$BATS_TEST_DIRNAME/../ci/fix-pr.sh"

# Faux gh : journalise ses arguments ; « pr list » renvoie $GH_DUP (doublon)
fake_gh() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
[ "$1 $2" = "pr list" ] && echo "${GH_DUP:-}"
exit 0
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export GITHUB_ENV="$BATS_TEST_TMPDIR/github_env" PR=7
    : >"$GH_LOG"
    : >"$GITHUB_ENV"
}

# main et develop sur le remote, branche feat/x avec un commit
flux_develop() {
    git config repowarden.integrationBranch develop
    git push -q origin HEAD:main HEAD:develop
    git fetch -q origin
    git commit -q --allow-empty -m "feat(panier): ajoute le panier"
    export HEAD=feat/x HEAD_SHA="$(git rev-parse HEAD)"
}

@test "fix-pr : PR vers main recible vers develop, titre conforme garde" {
    fake_gh
    flux_develop
    BASE=main TITLE="feat: panier" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "pr edit 7 --base develop" "$GH_LOG"
    ! grep -q -- "--title" "$GH_LOG"
    grep -q "^REPOWARDEN_FIXED_TARGET=develop$" "$GITHUB_ENV"
    grep -q "^REPOWARDEN_FIXED_BASE=$BASE_SHA$" "$GITHUB_ENV"
}

@test "fix-pr : doublon ferme au lieu d'etre recible" {
    fake_gh
    flux_develop
    GH_DUP=3 BASE=main TITLE="feat: panier" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "pr close 7 --comment Doublon de #3" "$GH_LOG"
    ! grep -q -- "--base" "$GH_LOG"
    grep -q "^REPOWARDEN_PR_CLOSED=true$" "$GITHUB_ENV"
}

@test "fix-pr : titre non conforme remplace par le commit unique" {
    fake_gh
    flux_develop
    BASE=develop TITLE="Feat/x" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "pr edit 7 --title feat(panier): ajoute le panier" "$GH_LOG"
    grep -q "^REPOWARDEN_FIXED_TITLE=feat(panier): ajoute le panier$" "$GITHUB_ENV"
}

@test "fix-pr : plusieurs commits -> celui au plus fort impact de version" {
    fake_gh
    flux_develop
    git commit -q --allow-empty -m "test: panier"
    git commit -q --allow-empty -m "fix: arrondi"
    export HEAD_SHA="$(git rev-parse HEAD)"
    BASE=develop TITLE="Ajout du panier" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "^REPOWARDEN_FIXED_TITLE=feat(panier): ajoute le panier$" "$GITHUB_ENV"
}

@test "fix-pr : pied BREAKING CHANGE -> ! ajoute au titre" {
    fake_gh
    flux_develop
    git commit -q --allow-empty -m "fix: format" -m "BREAKING CHANGE: nouveau format"
    export HEAD_SHA="$(git rev-parse HEAD)"
    BASE=develop TITLE="wip" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "^REPOWARDEN_FIXED_TITLE=feat(panier)!: ajoute le panier$" "$GITHUB_ENV"
}

@test "fix-pr : aucun commit conforme -> titre deduit de la branche" {
    fake_gh
    git config repowarden.integrationBranch develop
    git push -q origin HEAD:main HEAD:develop
    git fetch -q origin
    git commit -q --no-verify --allow-empty -m "wip"
    export HEAD=feat/ajout-du-panier HEAD_SHA="$(git rev-parse HEAD)"
    BASE=develop TITLE="Ajout du panier" run "$FIX"
    [ "$status" -eq 0 ]
    grep -q "^REPOWARDEN_FIXED_TITLE=feat: ajout du panier$" "$GITHUB_ENV"
}

@test "titres deduits des branches" {
    source "$BATS_TEST_DIRNAME/../hooks/lib/common.sh"
    git config repowarden.integrationBranch develop
    cfg_load
    for paire in "hotfix/crash-login:fix: crash login" "release/1.2.0:chore(release): 1.2.0" \
        "develop:chore(release): livrer develop sur main" "wip:chore: wip" \
        "feature/a_b:feat: a b"; do
        suggest_pr_title_r "${paire%%:*}"
        [ "$REPLY" = "${paire#*:}" ] || { echo "${paire%%:*} -> « $REPLY »"; return 1; }
    done
    suggest_pr_title_r "feat/$(printf 'mot-%.0s' {1..30})fin"
    header_valid "$REPLY" || { echo "trop long : $REPLY"; return 1; }
}

# --- bin/proteger (protection GitHub d'après .repowarden.conf) : gh simulé --------

PROTEGER="$BATS_TEST_DIRNAME/../bin/proteger"

# Faux gh : branches existantes = $GH_BRANCHES ; journalise les appels
fake_gh_repo() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
# rulesets refusés (dépôt privé, compte gratuit) si $GH_RULESETS_403
if [ -n "${GH_RULESETS_403:-}" ] && [[ "$*" == *"repos/moi/projet/rulesets"* ]]; then
    echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}'
    echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2
    exit 1
fi
case "$*" in
    "repo view"*) echo moi/projet ;;
    "api user --jq .login") echo moi ;;
    "api repos/moi/projet --jq .owner.type") echo "${GH_OWNER_TYPE:-User}" ;;
    "api repos/moi/projet --jq .default_branch") echo "${GH_DEFAULT_BRANCH:-main}" ;;
    # merge automatique relu après le PATCH : ignoré par GitHub si $GH_AUTO_MERGE=false
    "api repos/moi/projet --jq .allow_auto_merge") echo "${GH_AUTO_MERGE:-true}" ;;
    # réglages du dépôt : réglages du squash avec le squash désactivé refusés
    # (422, comme GitHub sur le dépôt d'essai), ou tout refus si $GH_REFUSE_PATCH
    "api -X PATCH repos/moi/projet "*)
        if [ -n "${GH_REFUSE_PATCH:-}" ] ||
            [[ "$*" == *"allow_squash_merge=false"*"squash_merge_commit_title"* ]]; then
            echo '{"message":"Validation Failed","status":"422"}'
            echo "gh: Validation Failed (HTTP 422)" >&2
            exit 1
        fi ;;
    # création / mise à jour : ruleset reçu journalisé ; refusé (422) si son
    # nom est $GH_REFUSE, avec la réponse de GitHub sur la sortie standard
    "api -X POST repos/moi/projet/rulesets"* | "api -X PUT repos/moi/projet/rulesets/"*)
        r="$(cat)"; echo "$r" >>"$GH_LOG"
        # exception GitHub Actions refusée dans l'organisation si $GH_REFUSE_INTEGRATION
        if [ -n "${GH_REFUSE_INTEGRATION:-}" ] && [[ "$r" == *'"actor_type": "Integration"'* ]]; then
            echo '{"message":"Validation Failed","errors":["Actor GitHub Actions integration must be part of the ruleset source or owner organization"],"status":"422"}'
            exit 1
        fi
        if [ -n "${GH_REFUSE:-}" ] && [[ "$r" == *"\"name\": \"$GH_REFUSE\""* ]]; then
            echo '{"message":"Validation Failed","errors":["Invalid rule 'creation': bypass actor not allowed"],"status":"422"}'
            echo "gh: Validation Failed (HTTP 422)" >&2
            exit 1
        fi ;;
    # personnes ayant l'écriture = $GH_WRITERS (vide : inconnu)
    "api repos/moi/projet/collaborators"*) echo "${GH_WRITERS:-}" ;;
    "api users/"*) case "$2" in users/moi) echo 101 ;; users/alice) echo 102 ;; *) exit 1 ;; esac ;;
    "api orgs/acme/teams/release --jq .id") echo 900 ;;
    "api orgs/"*) exit 1 ;;
    # branche renommée : GitHub redirige master vers main
    "api repos/moi/projet/branches/master"*) echo main ;;
    "api repos/moi/projet/branches/"*) [[ " $GH_BRANCHES " == *" ${2##*/} "* ]] && echo "${2##*/}" ;;
    # rulesets existants = $GH_RULESETS (JSON), filtrés comme le ferait gh
    "api repos/moi/projet/rulesets --jq "*) jq -r "$4" <<<"${GH_RULESETS:-[]}" ;;
    # un ruleset par son id, filtré comme le ferait gh
    "api repos/moi/projet/rulesets/"*) jq -c --argjson id "${2##*/}" '.[] | select(.id == $id)' <<<"${GH_RULESETS:-[]}" | jq -r "$4" ;;
    # étiquette urgent présente si $GH_LABEL_URGENT
    "api repos/moi/projet/labels/urgent"*) [ -n "${GH_LABEL_URGENT:-}" ] || exit 1 ;;
esac
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
}

# Rulesets affichés par --dry-run → JSON (liste) dans $RULESETS
rulesets_json() {
    python3 -c 'import json,sys
d=json.JSONDecoder(); t=sys.stdin.read(); i=t.index("{"); out=[]
while i < len(t):
    if t[i] in " \n": i+=1; continue
    o,i=d.raw_decode(t,i); out.append(o)
print(json.dumps(out))' <<<"$(sed -n '/^{/,$p' <<<"$1")"
}

@test "proteger : flux main seul -> squash, branches supprimees au merge, tags reserves" {
    require python3
    fake_gh_repo
    GH_BRANCHES="main" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert len(r)==2; b,t=r; \
        assert b["name"]=="repowarden" and b["conditions"]["ref_name"]["include"]==["refs/heads/main"]; \
        assert b["rules"][2]["parameters"]["allowed_merge_methods"]==["squash"]; \
        assert b["rules"][3]["parameters"]["required_status_checks"][0]["context"]=="repowarden"; \
        assert b["rules"][3]["parameters"]["strict_required_status_checks_policy"] is True; \
        assert t["target"]=="tag" and t["conditions"]["ref_name"]["include"]==["refs/tags/v*"]' "$(rulesets_json "$output")"
    [[ "$output" == *"suppression auto des branches : true"* ]] || false
    [[ "$output" != *"branche par défaut"* ]] || false
}

@test "proteger : flux develop -> main en merge commit, develop squash seul, defaut develop" {
    require python3
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run --checks "repowarden, tests (ubuntu-latest)"
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert len(r)==4; m,d,t,e=r; \
        assert m["conditions"]["ref_name"]["include"]==["refs/heads/main"]; \
        assert m["rules"][2]["parameters"]["allowed_merge_methods"]==["merge"]; \
        assert d["name"]=="repowarden (develop)" and d["conditions"]["ref_name"]["include"]==["refs/heads/develop"]; \
        assert d["rules"][2]["parameters"]["allowed_merge_methods"]==["squash"]; \
        assert [c["context"] for c in d["rules"][3]["parameters"]["required_status_checks"]]==["repowarden","tests (ubuntu-latest)"]; \
        assert m["rules"][3]["parameters"]["strict_required_status_checks_policy"] is False; \
        assert d["rules"][3]["parameters"]["strict_required_status_checks_policy"] is False; \
        assert m["bypass_actors"]==[] and d["bypass_actors"]==[]; \
        assert m["rules"][2]["parameters"]["required_approving_review_count"]==0; \
        assert m["rules"][4]=={"type":"required_deployments","parameters":{"required_deployment_environments":["production"]}}; \
        assert m["rules"][2]["parameters"]["require_last_push_approval"] is False; \
        assert d["rules"][2]["parameters"]["required_approving_review_count"]==0; \
        assert len(d["rules"])==4; \
        assert e["reviewers"]==[{"type":"User","id":101}] and e["prevent_self_review"] is False; \
        assert t["name"]=="repowarden (tags)"' "$(rulesets_json "$output")"
    [[ "$output" == *"suppression auto des branches : false"* ]] || false
    [[ "$output" == *"branche par défaut : develop"* ]] || false
    [[ "$output" == *"livraison vers main : approbation du déploiement « production »"* ]] || false
    # sans workflow de nettoyage : avertissement ; avec : rien
    [[ "$output" == *"ajouter un workflow qui appelle nettoyage-branches.yml"* ]] || false
    mkdir -p .github/workflows
    printf 'jobs:\n  n:\n    uses: o/r/.github/workflows/nettoyage-branches.yml@v4\n' >.github/workflows/nettoyage.yml
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run --checks "repowarden"
    [[ "$output" != *"nettoyage-branches.yml"* ]] || false
    [[ "$output" == *"merge automatique des PR de travail vers develop : true"* ]] || false
    git config repowarden.autoMergeWork false
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [[ "$output" == *"merge automatique des PR de travail vers develop : false"* ]] || false
    git config repowarden.autoMergeWork peut-etre
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
    # deliveryApproval = review : revue de PR, ni règle de déploiement ni environnement
    git config --unset repowarden.autoMergeWork
    git config repowarden.deliveryApproval review
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run --checks "repowarden"
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert len(r)==3; m=r[0]; \
        assert m["rules"][2]["parameters"]["required_approving_review_count"]==1 and len(m["rules"])==4' \
        "$(rulesets_json "$output")"
    [[ "$output" == *"livraison vers main : 1 approbation(s) exigée(s)"* ]] || false
    git config repowarden.deliveryApproval peut-etre
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
    git config --unset repowarden.deliveryApproval
}

@test "proteger : livraison exigee sur la branche principale si release-auto est appele (flux develop)" {
    require python3
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); \
        assert all("livraison" not in [c["context"] for c in x["rules"][3]["parameters"]["required_status_checks"]] for x in r if x.get("target")=="branch")' \
        "$(rulesets_json "$output")"
    mkdir -p .github/workflows
    printf 'jobs:\n  r:\n    uses: o/r/.github/workflows/release-auto.yml@v4\n' >.github/workflows/release.yml
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [[ "$output" == *"vérification « livraison » exigée"* ]] || false
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); m,d=r[0],r[1]; \
        assert [c["context"] for c in m["rules"][3]["parameters"]["required_status_checks"]]==["repowarden","livraison"]; \
        assert [c["context"] for c in d["rules"][3]["parameters"]["required_status_checks"]]==["repowarden"]' \
        "$(rulesets_json "$output")"
}

@test "proteger : etiquette urgent creee si absente (flux develop), jamais en double" {
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    GH_BRANCHES="main develop" run "$PROTEGER"
    [ "$status" -eq 0 ]
    grep -q "^label create urgent" "$GH_LOG"
    : >"$GH_LOG"
    GH_LABEL_URGENT=1 GH_BRANCHES="main develop" run "$PROTEGER"
    ! grep -q "^label create" "$GH_LOG"
    # --dry-run : annoncee, pas creee
    : >"$GH_LOG"
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    ! grep -q "^label create" "$GH_LOG"
    [[ "$output" == *"urgent"* ]] || false
}

@test "proteger : etiquette urgent annoncee au futur en dry-run, creee sinon" {
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    # --dry-run : rien n'est cree, l'annonce est au futur
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [[ "$output" == *"étiquette « urgent » sera créée"* ]] || false
    [[ "$output" != *"étiquette « urgent » créée"* ]] || false
    # hors dry-run : l'etiquette est creee, annonce au present
    GH_BRANCHES="main develop" run "$PROTEGER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"étiquette « urgent » créée"* ]] || false
    [[ "$output" != *"sera créée"* ]] || false
    # meme cle, message anglais
    REPOWARDEN_LANG=en GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [[ "$output" == *"will be created"* ]] || false
}

@test "proteger --verifier : regles en ligne comparees a celles attendues" {
    require python3
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    # regles en ligne = regles attendues (ids ajoutes)
    export GH_RULESETS="$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); [x.__setitem__("id",i+1) for i,x in enumerate(r) if "name" in x]; print(json.dumps([x for x in r if "name" in x]))' "$(rulesets_json "$output")")"
    GH_BRANCHES="main develop" run "$PROTEGER" --verifier
    [ "$status" -eq 0 ]
    [[ "$output" == *"à jour"* ]] || false
    # en ligne : 1 approbation et pas de regle de deploiement (cas #267) -> ecart
    export GH_RULESETS="$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); m=r[0]; m["rules"][2]["parameters"]["required_approving_review_count"]=1; m["rules"]=m["rules"][:4]; print(json.dumps(r))' "$GH_RULESETS")"
    GH_BRANCHES="main develop" run "$PROTEGER" --verifier
    [ "$status" -ne 0 ]
    [[ "$output" == *"approbations=1"* && "$output" == *"approbations=0"* ]] || false
    [[ "$output" == *"repowarden proteger"* ]] || false
    # ruleset absent -> ecart
    GH_RULESETS='[]' GH_BRANCHES="main develop" run "$PROTEGER" --verifier
    [ "$status" -ne 0 ]
}

# Ancien ruleset (vérification repogarde exigée), au nom libre : $1 id, $2 nom, $3 branches (JSON)
ancien_ruleset() {
    printf '{"id": %s, "name": "%s", "target": "branch", "source_type": "Repository", "conditions": {"ref_name": {"include": %s, "exclude": []}}, "rules": [{"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "repogarde"}]}}]}' "$1" "$2" "$3"
}

@test "proteger : ancien ruleset exigeant repogarde repris quel que soit son nom" {
    require jq
    fake_gh_repo
    # ancien ruleset sur la branche par defaut, et un ruleset sans rapport (build)
    export GH_RULESETS="[$(ancien_ruleset 7 "Protection de main" '["~DEFAULT_BRANCH"]'),
        {\"id\": 9, \"name\": \"Autre\", \"target\": \"branch\", \"source_type\": \"Repository\",
         \"conditions\": {\"ref_name\": {\"include\": [\"refs/heads/main\"]}},
         \"rules\": [{\"type\": \"required_status_checks\", \"parameters\": {\"required_status_checks\": [{\"context\": \"build\"}]}}]}]"
    GH_BRANCHES="main" run "$PROTEGER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ancien ruleset « Protection de main » repris"* ]] || false
    # mis a jour en place (renomme), aucun second ruleset de branche, l'autre intact
    grep -q "^api -X PUT repos/moi/projet/rulesets/7 " "$GH_LOG"
    ! grep -q "rulesets/9" <(grep -- "-X" "$GH_LOG")
    [ "$(grep -c '^api -X POST repos/moi/projet/rulesets ' "$GH_LOG")" -eq 1 ] # tags seulement
}

@test "proteger : ancien ruleset en trop jamais supprime, marche a suivre, echec" {
    require jq
    fake_gh_repo
    export GH_RULESETS="[$(ancien_ruleset 7 "Protection de main" '["refs/heads/main"]'), $(ancien_ruleset 8 "Vieux" '["~ALL"]')]"
    GH_BRANCHES="main" run "$PROTEGER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ancien ruleset « Protection de main » repris"* ]] || false
    [[ "$output" == *"Ancien ruleset « Vieux » (id 8)"* ]] || false
    [[ "$output" == *"gh api -X DELETE repos/moi/projet/rulesets/8"* ]] || false
    ! grep -q "DELETE" <(grep "^api" "$GH_LOG")
    # --verifier : l'ancien ruleset compte comme un ecart
    GH_BRANCHES="main" run "$PROTEGER" --verifier
    [ "$status" -ne 0 ]
    [[ "$output" == *"Protection de main (id 7) : ancien ruleset"* ]] || false
}

@test "proteger : sans rulesets, flux develop -> squash desactive (merge commit seul)" {
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    GH_RULESETS_403=1 GH_BRANCHES="main develop" run "$PROTEGER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"squash désactivé (merge commit seul)"* ]] || false
    grep -q "allow_squash_merge=false" "$GH_LOG"
    # squash désactivé : ni titre ni corps du squash (sinon PATCH refusé en 422)
    ! grep -q "squash_merge_commit" "$GH_LOG"
    [[ "$output" != *"Validation Failed"* ]] || false
    # avec rulesets : squash gardé (imposé par branche)
    : >"$GH_LOG"
    GH_BRANCHES="main develop" run "$PROTEGER"
    grep -q "allow_squash_merge=true .*squash_merge_commit_title=PR_TITLE" "$GH_LOG"
}

@test "proteger : reglages du depot refuses -> detail de GitHub, le reste applique, echec" {
    fake_gh_repo
    GH_REFUSE_PATCH=1 GH_BRANCHES="main" run "$PROTEGER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Réglages du dépôt (modes de merge, branche par défaut) : refusé par GitHub : Validation Failed"* ]] || false
    [[ "$output" == *"Protection incomplète"* ]] || false
    grep -q "^api -X PUT repos/moi/projet/actions/permissions/workflow" "$GH_LOG"
    grep -q "^api -X POST repos/moi/projet/rulesets" "$GH_LOG"
}

@test "proteger : merge automatique ignore par GitHub (prive, compte gratuit) -> signale" {
    fake_gh_repo
    # annoncé dès l'aperçu
    GH_RULESETS_403=1 GH_BRANCHES="main" run "$PROTEGER" --dry-run
    [[ "$output" == *"Merge automatique indisponible sur ce dépôt"* ]] || false
    # PATCH accepté mais allow_auto_merge resté faux : relu et signalé
    GH_RULESETS_403=1 GH_AUTO_MERGE=false GH_BRANCHES="main" run "$PROTEGER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Merge automatique demandé mais resté désactivé sur moi/projet"*"GitHub Pro / Team"* ]] || false
    grep -q "^api repos/moi/projet --jq .allow_auto_merge" "$GH_LOG"
    # livraison automatique : impossible, échec
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    git config repowarden.deliveryApproval auto
    GH_RULESETS_403=1 GH_AUTO_MERGE=false GH_BRANCHES="main develop" run "$PROTEGER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deliveryApproval = auto ne peut pas fonctionner sans merge automatique"* ]] || false
    [[ "$output" != *"Validation Failed"* ]] || false
    # merge automatique bien pris en compte : rien à signaler
    GH_BRANCHES="main develop" run "$PROTEGER"
    [[ "$output" != *"resté désactivé"* ]] || false
}

@test "proteger : tags refuses dans une organisation -> regle des comptes personnels, avertissement" {
    fake_gh_repo
    GH_OWNER_TYPE=Organization GH_REFUSE_INTEGRATION=1 GH_BRANCHES="main" run "$PROTEGER"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"exception « GitHub Actions » refusée dans cette organisation"* ]] || false
    # second envoi : sans l'exception GitHub Actions, création libre
    grep -q '"actor_type": "RepositoryRole"' "$GH_LOG"
    [[ "$output" != *"refusé par GitHub"* ]] || false
}

@test "proteger : rulesets indisponibles (prive, compte gratuit) -> message clair, reglages appliques" {
    fake_gh_repo
    GH_RULESETS_403=1 GH_BRANCHES="main" run "$PROTEGER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rulesets indisponibles pour moi/projet"*"GitHub Pro"* ]] || false
    grep -q "^api -X PATCH repos/moi/projet " "$GH_LOG"
    ! grep -q "^api -X POST repos/moi/projet/rulesets" "$GH_LOG"
    GH_RULESETS_403=1 GH_BRANCHES="main" run "$PROTEGER" --verifier
    [ "$status" -ne 0 ]
    [[ "$output" == *"Rulesets indisponibles"* ]] || false
}

@test "proteger : refus de GitHub affiche avec son detail, les autres rulesets appliques" {
    fake_gh_repo
    GH_REFUSE="repowarden" GH_BRANCHES="main" run "$PROTEGER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Ruleset « repowarden » refusé par GitHub : Validation Failed : Invalid rule"* ]] || false
    [[ "$output" == *"Protection incomplète"* ]] || false
    grep -q '"name": "repowarden (tags)"' "$GH_LOG"
}

@test "proteger : livraison approuvee par deploiement sans workflow qui le cree -> avertissement" {
    require python3
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    # aucun workflow de release avec delivery-environment : main serait bloquee
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"déploiement que rien ne crée"* ]] || false
    # workflow complet : rien a signaler
    mkdir -p .github/workflows
    printf 'on:\n  workflow_dispatch:\nconcurrency:\n  group: g\n  cancel-in-progress: ${{ github.event_name != %s }}\njobs:\n  r:\n    uses: o/r/.github/workflows/release-auto.yml@v4\n    with:\n      delivery-environment: production\n' "'push'" >.github/workflows/release.yml
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [[ "$output" != *"déploiement que rien ne crée"* ]] || false
    [[ "$output" != *"remplace celle en attente"* ]] || false
    # ancienne concurrence avec workflow_dispatch : une demande oubliee bloquerait les suivantes
    sed -i.bak 's/cancel-in-progress: .*/cancel-in-progress: false/' .github/workflows/release.yml
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [[ "$output" == *"remplace celle en attente"* ]] || false
    # revue de PR au lieu du deploiement : pas de regle de deploiement, pas d'avertissement
    rm -rf .github
    git config repowarden.deliveryApproval review
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [[ "$output" != *"déploiement que rien ne crée"* ]] || false
}

@test "proteger : concurrence en mode pr -> pas d'avertissement de livraison en attente" {
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    mkdir -p .github/workflows
    # mode pr : aucune demande de livraison, cancel-in-progress: false sans risque
    printf 'on:\n  workflow_dispatch:\nconcurrency:\n  group: g\n  cancel-in-progress: false\njobs:\n  r:\n    uses: o/r/.github/workflows/release-auto.yml@v4\n    with:\n      mode: pr\n' >.github/workflows/release.yml
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"remplace celle en attente"* ]] || false
}

@test "proteger : concurrence signalee seulement pour le mode tag avec delivery-environment" {
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    mkdir -p .github/workflows
    printf 'on:\n  workflow_dispatch:\nconcurrency:\n  group: g\n  cancel-in-progress: false\njobs:\n  r:\n    uses: o/r/.github/workflows/release-auto.yml@v4\n    with:\n      mode: pr\n' >.github/workflows/preversion.yml
    printf 'on:\n  workflow_dispatch:\nconcurrency:\n  group: g\n  cancel-in-progress: false\njobs:\n  r:\n    uses: o/r/.github/workflows/release-auto.yml@v4\n    with:\n      delivery-environment: production\n' >.github/workflows/livraison.yml
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *".github/workflows/livraison.yml : une demande de livraison"* ]] || false
    [[ "$output" != *".github/workflows/preversion.yml : une demande de livraison"* ]] || false
}

@test "proteger : livraison automatique -> verifications exigees gardees, ni deploiement ni environnement" {
    require python3
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    git config repowarden.deliveryApproval auto
    mkdir -p .github/workflows
    printf 'jobs:\n  r:\n    uses: o/r/.github/workflows/release-auto.yml@v4\n    with:\n      delivery-auto: true\n' >.github/workflows/release.yml
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); m=r[0]; \
        assert m["conditions"]["ref_name"]["include"]==["refs/heads/main"]; \
        assert [c["context"] for c in m["rules"][3]["parameters"]["required_status_checks"]]==["repowarden","livraison"]; \
        assert m["rules"][2]["parameters"]["allowed_merge_methods"]==["merge"]; \
        assert m["rules"][2]["parameters"]["required_approving_review_count"]==0; \
        assert len(m["rules"])==4 and {x["type"] for x in m["rules"]}>={"deletion","non_fast_forward"}; \
        assert not any("reviewers" in x for x in r)' "$(rulesets_json "$output")"
    [[ "$output" == *"livraison vers main : automatique"* ]] || false
    [[ "$output" != *"déploiement que rien ne crée"* ]] || false
    [[ "$output" != *"delivery-auto: true"* ]] || false
    # relectures configurees : gardees sur main
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run --relecteurs 1
    python3 -c 'import json,sys; m=json.loads(sys.argv[1])[0]; \
        assert m["rules"][2]["parameters"]["required_approving_review_count"]==1' "$(rulesets_json "$output")"
    # aucun workflow avec delivery-auto : avertissement (merge a la main)
    rm -rf .github
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"delivery-auto: true"* ]] || false
    # merge automatique coupe : incompatible, refuse
    git config repowarden.autoMergeWork false
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"autoMergeWork"* ]] || false
}

@test "release-auto : livraison automatique armee par l'App, sortie delivery_pr exposee" {
    local wf="$BATS_TEST_DIRNAME/../.github/workflows/release-auto.yml"
    # entree, defaut false (l'approbation humaine reste le defaut)
    grep -A10 '^      delivery-auto:$' "$wf" | grep -m1 'default:' | grep -q 'default: false'
    # sortie du workflow
    grep -q 'delivery_pr:$' "$wf"
    grep -q 'value: ${{ jobs.tag.outputs.delivery_pr }}' "$wf"
    # etape d'armement : jeton de l'App seulement, merge commit automatique
    local etape
    etape="$(awk '/- name: Livraison automatique$/ { j = 1 } j && /- name: / && !/Livraison automatique$/ { j = 0 } j' "$wf")"
    [ -n "$etape" ]
    [[ "$etape" == *"inputs.delivery-auto"* ]] || false
    [[ "$etape" == *'GH_TOKEN: ${{ steps.app.outputs.token }}'* ]] || false
    [[ "$etape" != *"github.token"* ]] || false
    [[ "$etape" == *'gh pr merge "$PR" --auto --merge'* ]] || false
    [[ "$etape" == *"::warning::"* ]] || false
    # deux modes exclusifs : erreur explicite ; job livraison (approbation) inchange
    grep -q 'delivery-auto et delivery-environment' "$wf"
    grep -q 'Approbation humaine' "$wf"
}

@test "proteger : approbation des changements non attribues posee explicitement (false par defaut, reglable)" {
    require python3
    fake_gh_repo
    git config repowarden.integrationBranch develop
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); \
        assert all(x["rules"][2]["parameters"]["require_extra_approval_for_unattributed_changes"] is False for x in r if x.get("target")=="branch")' \
        "$(rulesets_json "$output")"
    [[ "$output" == *"changements non attribués : false"* ]] || false
    git config repowarden.unattributedApproval true
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); \
        assert all(x["rules"][2]["parameters"]["require_extra_approval_for_unattributed_changes"] is True for x in r if x.get("target")=="branch")' \
        "$(rulesets_json "$output")"
    git config repowarden.unattributedApproval peut-etre
    GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
}

@test "proteger : relecture exigee (approbations, CODEOWNERS, pas d'auto-approbation du dernier push)" {
    require python3
    fake_gh_repo
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --relecteurs 2 --codeowners
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; b=json.loads(sys.argv[1])[0]; p=b["rules"][2]["parameters"]; \
        assert p["required_approving_review_count"]==2 and p["require_code_owner_review"] is True; \
        assert p["require_last_push_approval"] is True and p["dismiss_stale_reviews_on_push"] is True' "$(rulesets_json "$output")"
    [[ "$output" == *"contournement explicite"* ]] || false
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --relecteurs beaucoup
    [ "$status" -ne 0 ]
}

@test "proteger : dev solo -> aucune approbation par une autre personne exigee" {
    require python3
    fake_gh_repo
    GH_WRITERS=1 GH_BRANCHES="main" run "$PROTEGER" --dry-run --relecteurs 1
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; p=json.loads(sys.argv[1])[0]["rules"][2]["parameters"]; \
        assert p["required_approving_review_count"]==1 and p["require_last_push_approval"] is False' "$(rulesets_json "$output")"
    [[ "$output" == *"dépôt solo"* ]] || false
    # livraison en revue de PR : pas de minimum forcé à 1 en solo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    git config repowarden.deliveryApproval review
    GH_WRITERS=1 GH_BRANCHES="main develop" run "$PROTEGER" --dry-run
    python3 -c 'import json,sys; m=json.loads(sys.argv[1])[0]; \
        assert m["rules"][2]["parameters"]["required_approving_review_count"]==0' "$(rulesets_json "$output")"
    # plusieurs personnes : inchangé
    GH_WRITERS=2 GH_BRANCHES="main develop" run "$PROTEGER" --dry-run --relecteurs 1
    python3 -c 'import json,sys; p=json.loads(sys.argv[1])[0]["rules"][2]["parameters"]; \
        assert p["required_approving_review_count"]==1 and p["require_last_push_approval"] is True' "$(rulesets_json "$output")"
    [[ "$output" != *"dépôt solo"* ]] || false
}

@test "proteger : reglages lus dans .repowarden.conf" {
    require python3
    fake_gh_repo
    git config repowarden.requiredReviews 1
    git config repowarden.codeOwnerReview true
    GH_BRANCHES="main" run "$PROTEGER" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"approbations exigées : 1 ; revue des CODEOWNERS : true"* ]] || false
}

@test "proteger : environnement de deploiement approuve par des personnes" {
    require python3
    fake_gh_repo
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; e=json.loads(sys.argv[1])[-1]; \
        assert e["reviewers"]==[{"type":"User","id":101}] and e["prevent_self_review"] is False; \
        assert e["deployment_branch_policy"]["custom_branch_policies"] is True' "$(rulesets_json "$output")"
    [[ "$output" == *"environnement « production » : approbation de moi"* ]] || false
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production --approbateurs "moi alice"
    python3 -c 'import json,sys; e=json.loads(sys.argv[1])[-1]; \
        assert [r["id"] for r in e["reviewers"]]==[101,102] and e["prevent_self_review"] is True' "$(rulesets_json "$output")"
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production --approbateurs inconnu
    [ "$status" -ne 0 ]
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production --approbateurs "@acme/release moi"
    python3 -c 'import json,sys; e=json.loads(sys.argv[1])[-1]; \
        assert e["reviewers"]==[{"type":"Team","id":900},{"type":"User","id":101}]' "$(rulesets_json "$output")"
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --environnement production --approbateurs "@acme/inconnue"
    [ "$status" -ne 0 ]
}

@test "proteger : tags -> workflows seuls (organisation), ni deplaces ni supprimes (compte perso)" {
    require python3
    fake_gh_repo
    GH_OWNER_TYPE=Organization GH_BRANCHES="main" run "$PROTEGER" --dry-run
    python3 -c 'import json,sys; t=json.loads(sys.argv[1])[-1]; \
        assert [r["type"] for r in t["rules"]]==["creation","update","deletion"]; \
        assert t["bypass_actors"][0]["actor_type"]=="Integration"' "$(rulesets_json "$output")"
    GH_OWNER_TYPE=User GH_BRANCHES="main" run "$PROTEGER" --dry-run
    python3 -c 'import json,sys; t=json.loads(sys.argv[1])[-1]; \
        assert [r["type"] for r in t["rules"]]==["update","deletion"]; \
        assert t["bypass_actors"][0]["actor_type"]=="RepositoryRole"' "$(rulesets_json "$output")"
    [[ "$output" == *"compte personnel"* ]] || false
    GH_BRANCHES="main" run "$PROTEGER" --dry-run --sans-tags
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert all(x["target"]=="branch" for x in r)' "$(rulesets_json "$output")"
}

@test "proteger : rulesets de l'ancien nom (repogarde) repris et renommes, pas doubles" {
    require jq
    fake_gh_repo
    GH_BRANCHES="main" GH_RULESETS='[{"id":7,"name":"repogarde"},{"id":8,"name":"repogarde (tags)"}]' \
        run "$PROTEGER"
    [ "$status" -eq 0 ]
    grep -q "^api -X PUT repos/moi/projet/rulesets/7 " "$GH_LOG"
    grep -q "^api -X PUT repos/moi/projet/rulesets/8 " "$GH_LOG"
    ! grep -q "^api -X POST repos/moi/projet/rulesets" "$GH_LOG"
    # nouveau nom deja present : c'est lui qui est mis a jour
    : >"$GH_LOG"
    GH_BRANCHES="main" GH_RULESETS='[{"id":7,"name":"repogarde"},{"id":9,"name":"repowarden"}]' \
        run "$PROTEGER"
    grep -q "^api -X PUT repos/moi/projet/rulesets/9 " "$GH_LOG"
}

@test "proteger : branche d'integration absente -> arret avant toute modification, commande pour la creer" {
    fake_gh_repo
    git config repowarden.integrationBranch develop
    git config repowarden.protectedBranches "main develop"
    for mode in --dry-run ""; do
        : >"$GH_LOG"
        GH_BRANCHES="main" run "$PROTEGER" $mode
        [ "$status" -ne 0 ]
        [[ "$output" == *"« develop » absente"*"rien n'a été modifié"* ]] || false
        [[ "$output" == *"git push origin main:refs/heads/develop"* ]] || false
        ! grep -qE -- "-X (PATCH|PUT|POST)" "$GH_LOG"
    done
}

@test "proteger : aucune branche protegee existante -> erreur" {
    fake_gh_repo
    GH_BRANCHES="" run "$PROTEGER" --dry-run
    [ "$status" -ne 0 ]
    [[ "$output" == *"Aucune des branches"* ]] || false
}

@test "ci : agents IA -> auteur, committer ou signature refuses (commits et description de PR), bots acceptes" {
    GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com \
        git commit -q --no-verify --allow-empty -m "fix: par un agent"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"agent IA (Claude <noreply@anthropic.com>)"* ]] || false
    [[ "$output" != *"nouvelle fonctionnalité"* ]] || false
    # signature dans le message
    git reset -q --hard "$REPOWARDEN_BASE"
    git commit -q --no-verify --allow-empty -m "fix: a" -m "Co-Authored-By: Claude Opus <noreply@anthropic.com>"
    run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"signature d'agent IA dans le message"* ]] || false
    # description de PR (corps du commit en squash)
    git reset -q --hard "$REPOWARDEN_BASE"
    git commit -q --no-verify --allow-empty -m "fix: b"
    REPOWARDEN_PR_BODY=$'Corrige b.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)' run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"Description de la PR"* ]] || false
    # bots d'automatisation : acceptes
    git reset -q --hard "$REPOWARDEN_BASE"
    GIT_AUTHOR_NAME='github-actions[bot]' GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
        git commit -q --no-verify --allow-empty -m "chore: par le bot"
    run "$CHECK" commits
    [ "$status" -eq 0 ]
    # reglage : agents autorises
    GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL=noreply@anthropic.com \
        git commit -q --no-verify --allow-empty -m "fix: agent autorise"
    git config repowarden.allowAgentSignatures true
    run "$CHECK" commits
    [ "$status" -eq 0 ]
}

@test "ci : bots (Dependabot, Renovate) -> format exige, longueur libre" {
    long="fix(deps): bump org.apache.maven:apache-maven from 3.9.16 to 3.10.0 in the prod group"
    GIT_AUTHOR_EMAIL="49699333+dependabot[bot]@users.noreply.github.com" \
        git commit -q --no-verify --allow-empty -m "$long"
    REPOWARDEN_BRANCH=dependabot/maven/prod REPOWARDEN_PR_TITLE="$long" run "$CHECK" commits
    [ "$status" -eq 0 ]
    GIT_AUTHOR_EMAIL="29139614+renovate[bot]@users.noreply.github.com" \
        git commit -q --no-verify --allow-empty -m "Update dependency x"
    REPOWARDEN_BRANCH=renovate/x run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"« Update dependency x »"* ]] || false
}

@test "ci : humain -> longueur toujours limitee, aide sans force push en premier" {
    git commit -q --no-verify --allow-empty -m "fix(deps): bump org.apache.maven:apache-maven from 3.9.16 to 3.10.0 in the prod group"
    REPOWARDEN_PR_TITLE="fix(deps): bump org.apache.maven:apache-maven from 3.9.16 to 3.10.0 in the prod" run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"72 caractères"* ]] || false
    [[ "$output" == *"le corriger suffit"* ]] || false
}

# --- ci/version.sh (releases en mode tag) ----------------------------------------

VERSION="$BATS_TEST_DIRNAME/../ci/version.sh"

c() { git commit -q --no-verify --allow-empty -m "$1"; }

@test "version : aucun tag -> version initiale des le premier fix ou feat, rien sur chore" {
    c "chore: outillage"
    [ -z "$("$VERSION" next 2>/dev/null)" ]
    c "fix: a"
    [ "$("$VERSION" next 2>/dev/null)" = 0.1.0 ]
    [ "$(INITIAL_VERSION=1.0.0 "$VERSION" next 2>/dev/null)" = 1.0.0 ]
}

@test "version : depuis le tag le plus eleve, increment selon les commits" {
    git tag v1.4.2
    c "fix: a"
    [ "$("$VERSION" next 2>/dev/null)" = 1.4.3 ]
    c "feat: b"
    [ "$("$VERSION" next 2>/dev/null)" = 1.5.0 ]
    c "refactor!: c"
    [ "$("$VERSION" next 2>/dev/null)" = 2.0.0 ]
}

@test "version : les preversions (v1.5.0-next.2) ne servent pas de base" {
    git tag v1.4.2
    c "feat: b"
    git tag v1.5.0-next.2
    c "fix: c"
    [ "$("$VERSION" next 2>/dev/null)" = 1.5.0 ]
}

@test "version : BREAKING CHANGE en pied -> majeure" {
    git tag v1.0.0
    git commit -q --no-verify --allow-empty -m "fix: a" -m "BREAKING CHANGE: format change"
    [ "$("$VERSION" next 2>/dev/null)" = 2.0.0 ]
}

@test "version : livraison mergee en squash -> version annoncee par le titre" {
    git tag v1.0.0
    c "chore(release): v1.3.0"
    [ "$("$VERSION" next 2>/dev/null)" = 1.3.0 ]
}

@test "version : livraison squashee puis historiques reunis -> rien de recompte" {
    git tag v1.0.0
    git switch -q -c develop
    echo a >a; git add a; git commit -q --no-verify -m "feat: panier"
    echo b >b; git add b; git commit -q --no-verify -m "fix: arrondi"
    # livraison squashée sur main (dépôt sans rulesets), taguée
    git switch -q main
    git merge -q --squash develop >/dev/null
    git commit -q --no-verify -m "chore(release): v1.1.0 (#21)"
    git tag v1.1.0
    # historiques réunis par un merge commit de main dans develop
    git switch -q develop
    git merge -q --no-ff --no-edit main
    [ -z "$("$VERSION" next 2>/dev/null)" ]
    # travail suivant : seul lui compte
    echo c >c; git add c; git commit -q --no-verify -m "fix: suite"
    [ "$("$VERSION" next 2>/dev/null)" = 1.1.1 ]
    run "$VERSION" notes
    [[ "$output" == *"- fix: suite"* && "$output" != *"feat: panier"* ]] || false
}

@test "version : notes groupees, incompatibles en tete" {
    git tag v1.0.0
    c "feat: panier"
    c "fix(api): timeout"
    c "feat!: nouvelle API"
    c "docs: guide"
    run "$VERSION" notes
    [ "$status" -eq 0 ]
    [[ "$output" == *"### ⚠ Changements incompatibles"*"- feat!: nouvelle API"* ]] || false
    [[ "$output" == *"### Fonctionnalités"*"- feat: panier"* ]] || false
    [[ "$output" == *"### Corrections"*"- fix(api): timeout"* ]] || false
    [[ "$output" == *"### Maintenance"*"- docs: guide"* ]] || false
    [[ "$output" == *"_Depuis v1.0.0._"* ]] || false
}

@test "langue en CI : anglais par defaut, langue du projet si reglee" {
    git commit -q --no-verify --allow-empty -m "wip"
    REPOWARDEN_LANG= CI=true GIT_CONFIG_GLOBAL=/dev/null run "$CHECK" commits
    [ "$status" -ne 0 ]
    [[ "$output" == *"expected format <type>(<scope>)"* ]] || false
    printf '[repowarden]\n\tlang = fr\n' >.repowarden.conf
    REPOWARDEN_LANG= CI=true GIT_CONFIG_GLOBAL=/dev/null run "$CHECK" commits
    [[ "$output" == *"format attendu <type>(<scope>)"* ]] || false
}

@test "version : titres des notes dans la langue du projet" {
    git tag v1.0.0
    c "feat: panier"
    c "fix: arrondi"
    REPOWARDEN_LANG=en run "$VERSION" notes
    [[ "$output" == *"### Features"*"### Bug fixes"* ]] || false
    [[ "$output" == *"_Since v1.0.0._"* ]] || false
}

# Faux gh des notes : tickets #12 (feat), #13 (fix) et #14 (docs) ; PR de
# livraison mergée au commit demandé si $GH_LIVRAISON (sa description)
fake_gh_notes() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1 $2 $3" in
    "issue view 12") printf 'Panier : total affiché\ttype: feat\n' ;;
    "issue view 13") printf 'API : délai dépassé géré\ttype: fix\n' ;;
    "issue view 14") printf 'Guide : installation\ttype: docs\n' ;;
    "issue view "*) exit 1 ;;
    "api repos/{owner}/{repo}/commits/"*)
        [ -n "${GH_LIVRAISON:-}" ] || { echo ""; exit 0; }
        printf '%s\n' "$GH_LIVRAISON" ;;
esac
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "version : notes introduites par En bref, A faire, Mettre a jour et Tickets livres" {
    fake_gh_notes
    git tag v1.0.0
    git commit -q --no-verify --allow-empty -m "fix(api): timeout" -m "Ticket : #13"
    git commit -q --no-verify --allow-empty -m "feat: panier" -m "À faire : relancer repowarden proteger" -m "Ticket : #12"
    git commit -q --no-verify --allow-empty -m "docs: guide" -m "Ticket : #14"
    git commit -q --no-verify --allow-empty -m "feat: suite du panier" -m "Ticket : #12"
    git commit -q --no-verify --allow-empty -m "feat!: nouvelle API" -m "BREAKING CHANGE: /v1 retirée"
    printf '[repowarden]\n\treleaseUpdate = npm update -g mon-outil\n' >.repowarden.conf
    run "$VERSION" notes
    [ "$status" -eq 0 ]
    # fonctionnalités, puis corrections, puis le reste ; un ticket une seule fois
    [[ "$output" == *"### En bref"*"- Panier : total affiché (#12)"*"- API : délai dépassé géré (#13)"*"- Guide : installation (#14)"*"### À faire"* ]] || false
    [ "$(grep -c "(#12)" <<<"$output")" -eq 1 ]
    [[ "$output" == *"### À faire"*"- relancer repowarden proteger"*"- /v1 retirée"* ]] || false
    [[ "$output" == *"### Mettre à jour"*'`npm update -g mon-outil`'* ]] || false
    [[ "$output" == *"### Tickets livrés"*"#12, #13, #14"*"### ⚠ Changements incompatibles"* ]] || false
    [[ "$output" == *"### Fonctionnalités"*"- feat: panier"* ]] || false
}

@test "version : sans ticket, sans gh ni reglage -> notes sans introduction" {
    git tag v1.0.0
    c "feat: panier"
    run "$VERSION" notes
    [[ "$output" != *"En bref"* && "$output" != *"Mettre à jour"* && "$output" != *"Tickets livrés"* ]] || false
    # tickets cités mais gh absent ou muet : pas de partie tickets
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/gh"
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    git commit -q --no-verify --allow-empty -m "fix: b" -m "Ticket : #99"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$VERSION" notes
    [ "$status" -eq 0 ]
    [[ "$output" != *"En bref"* && "$output" != *"Tickets livrés"* ]] || false
    [[ "$output" == *"Tickets illisibles ( #99)"* ]] || false
}

@test "version : tickets illisibles (depot prive sans issues: read) -> avertissement, notes inchangees" {
    fake_gh_notes
    git tag v1.0.0
    git commit -q --no-verify --allow-empty -m "feat: panier" -m "Ticket : #12"
    git commit -q --no-verify --allow-empty -m "fix: b" -m "Ticket : #99"
    run bash -c "\"$VERSION\" notes 2>\"$BATS_TEST_TMPDIR/err\""
    [ "$status" -eq 0 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/err")" == *"::warning::Tickets illisibles ( #99)"*"issues: read"* ]] || false
    [[ "$output" != *"::warning::"* ]] || false
    [[ "$output" == *"- Panier : total affiché (#12)"* ]] || false
}

@test "version : release -> notes de la PR de livraison relue, sinon recalculees" {
    fake_gh_notes
    git tag v1.0.0
    c "feat: panier"
    # PR trouvée : sans la phrase d'en-tête ni le pied
    GH_LIVRAISON="$(printf 'Merger cette PR publie **v1.1.0**.\n\n### En bref\n\n- Corrigé à la relecture\n\n---\n_Tenue à jour (repowarden)._')" \
        run "$VERSION" notes-livraison HEAD
    [ "$status" -eq 0 ]
    [[ "$output" == *"- Corrigé à la relecture"* ]] || false
    [[ "$output" != *"Merger cette PR"* && "$output" != *"Tenue à jour"* && "$output" != *"feat: panier"* ]] || false
    # aucune PR : notes recalculées
    run "$VERSION" notes-livraison HEAD
    [[ "$output" == *"### Fonctionnalités"*"- feat: panier"* ]] || false
}

@test "workflows : release-auto demande issues: read (tickets des notes), repowarden l'accorde" {
    cd "$BATS_TEST_DIRNAME/.."
    awk '/^  tag:/ { j = 1 } j && /^  [a-z]+:$/ && !/^  tag:/ { j = 0 } j' .github/workflows/release-auto.yml | grep -q '^      issues: read'
    grep -A8 'uses: ./.github/workflows/release-auto.yml' .github/workflows/release.yml | grep -q 'issues: read'
}

@test "workflows reutilisables : git fetch et push authentifies (depots prives)" {
    # checkout sans identifiants persistés : un fetch anonyme échoue sur un dépôt privé
    run grep -nE '^\s+git (fetch|push)' "$BATS_TEST_DIRNAME"/../.github/workflows/release-auto.yml \
        "$BATS_TEST_DIRNAME"/../.github/workflows/tickets.yml "$BATS_TEST_DIRNAME"/../.github/workflows/bot.yml
    [ -z "$output" ] || { echo "sans identifiants :"; echo "$output"; return 1; }
    grep -q "credential.helper=!gh auth git-credential' fetch -q origin" "$BATS_TEST_DIRNAME"/../.github/workflows/release-auto.yml
}

# --- ci/livraison.sh (statut « livraison » de la PR de livraison) : gh simulé ----

LIVRAISON="$BATS_TEST_DIRNAME/../ci/livraison.sh"

# Faux gh : règles de develop = $GH_REGLES ; réglages du dépôt = $GH_REGLAGES
# (« allow_merge_commit delete_branch_on_merge ») ; statut posté journalisé
fake_gh_livraison() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
    "api repos/moi/projet/rules/branches/develop"*) echo "${GH_REGLES-deletion non_fast_forward pull_request}" ;;
    "api repos/moi/projet/rulesets") [ -z "${GH_RULESETS_403:-}" ] || { echo '{"message":"Upgrade to GitHub Pro","status":"403"}'; exit 1; } ;;
    "api repos/moi/projet --jq"*) echo "${GH_REGLAGES:-true false}" ;;
esac
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log" \
        GH_REPO=moi/projet INTEGRATION=develop ID=next OBLIGATOIRE=true
}

@test "livraison : en echec sans preversion de la version annoncee, livrable avec" {
    fake_gh_livraison
    git tag v1.0.0
    c "feat: panier"
    run "$LIVRAISON"
    [ "$status" -eq 0 ]
    [[ "$output" == failure*"v1.1.0 : aucune préversion v1.1.0-next.N"*"Run workflow sur develop"* ]] || false
    # publiée dans le même run, ou déjà taguée
    PREVERSION_CREEE=v1.1.0-next.3 run "$LIVRAISON"
    [[ "$output" == success*"v1.1.0 : préversion testée"* ]] || false
    git tag v1.1.0-next.2
    run "$LIVRAISON"
    [[ "$output" == success* ]] || false
    # préversion d'une autre version : ne compte pas
    c "feat!: refonte"
    run "$LIVRAISON"
    [[ "$output" == failure*"v2.0.0"* ]] || false
    # non exigée, ou maintenance seule : livrable
    OBLIGATOIRE=false run "$LIVRAISON"
    [[ "$output" == success*"non exigée"* ]] || false
}

@test "livraison : protection du flux develop absente -> en echec, repowarden proteger" {
    fake_gh_livraison
    git tag v1.0.0
    git tag v1.1.0-next.1
    c "feat: panier"
    GH_REGLES="pull_request" run "$LIVRAISON"
    [[ "$output" == failure*"repowarden proteger"* ]] || false
    GH_REGLAGES="false false" run "$LIVRAISON"
    [[ "$output" == failure*"repowarden proteger"* ]] || false
    GH_REGLAGES="true true" run "$LIVRAISON"
    [[ "$output" == failure*"repowarden proteger"* ]] || false
    # rulesets indisponibles (privé, compte gratuit) : seule la règle manque, réglages bons
    GH_RULESETS_403=1 GH_REGLES="" run "$LIVRAISON"
    [[ "$output" == success* ]] || false
    GH_RULESETS_403=1 GH_REGLES="" GH_REGLAGES="true true" run "$LIVRAISON"
    [[ "$output" == failure*"repowarden proteger"* ]] || false
    # réglages non renvoyés par l'API (jeton sans droits) : pas de faux échec
    GH_REGLAGES="null null" run "$LIVRAISON"
    [[ "$output" == success* ]] || false
    # statut posté sur le commit, description limitée à 140 caractères
    : >"$GH_LOG"
    GH_REGLES="pull_request" run "$LIVRAISON" poster abc123
    grep -q "^api repos/moi/projet/statuses/abc123 -f state=failure -f context=livraison -f description=" "$GH_LOG"
    [[ "$output" == *"::warning::livraison"* ]] || false
}

# --- ci/instantanes.sh (instantanés livraison/* abandonnés) : gh simulé ---------

INSTANTANES="$BATS_TEST_DIRNAME/../ci/instantanes.sh"

# Faux gh : tags $GH_TAGS, instantanés $GH_INSTANTANES (versions) ; états des
# PR de livraison/vX dans $GH_DIR/pr-X, commits absents de develop dans
# $GH_DIR/avance-X (0 par défaut, « erreur » : API en échec) ; appels journalisés
fake_gh_instantanes() {
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/gh"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
    "api --paginate repos/o/r/git/matching-refs/tags/v "*)
        [ -z "${GH_ERREUR:-}" ] || exit 1
        for t in $GH_TAGS; do echo "refs/tags/$t"; done ;;
    "api --paginate repos/o/r/git/matching-refs/heads/livraison/v "*)
        for v in $GH_INSTANTANES; do echo "refs/heads/livraison/v$v"; done ;;
    "pr list --head livraison/v"*) cat "$GH_DIR/pr-${4#livraison/v}" 2>/dev/null || true ;;
    "api repos/o/r/compare/develop...livraison/v"*)
        a="$(cat "$GH_DIR/avance-${2##*/v}" 2>/dev/null || echo 0)"
        [ "$a" != erreur ] || exit 1
        echo "$a" ;;
esac
exit 0
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log" \
        GH_DIR="$BATS_TEST_TMPDIR/gh" GH_REPO=o/r INTEGRATION=develop
    : >"$GH_LOG"
}

supprimes() { sed -n 's#^api -X DELETE repos/o/r/git/refs/heads/##p' "$GH_LOG" | sort | paste -sd' ' -; }

@test "instantanes : version stable publiee ou PR fermee sans fusion -> supprime" {
    fake_gh_instantanes
    # 4.9.0 publiée (sa préversion ne compte pas) ; 4.9.1 en attente
    export GH_TAGS="v4.8.3 v4.9.0 v4.9.1-next.2" GH_INSTANTANES="4.8.4 4.9.0 4.9.1"
    echo "MERGED" >"$GH_DIR/pr-4.9.0"
    echo "OPEN" >"$GH_DIR/pr-4.9.1"
    run "$INSTANTANES"
    [ "$status" -eq 0 ]
    # 4.8.4 : sans PR, mais 4.9.0 publiée ; 4.9.0 : publiée
    [ "$(supprimes)" = "livraison/v4.8.4 livraison/v4.9.0" ]
    [[ "$output" == *"Instantané livraison/v4.8.4 supprimé (v4.9.0 publiée)"* ]] || false
    grep -qx "api repos/o/r/compare/develop...livraison/v4.8.4 --jq .ahead_by" "$GH_LOG"
    [[ "$output" == *"livraison/v4.9.1 conservée : livraison en attente la plus récente"* ]] || false
    # demande remplacée (PR fermée sans fusion), non publiée : supprimée
    export GH_TAGS="v4.9.0" GH_INSTANTANES="4.9.1 4.10.0"
    echo "CLOSED" >"$GH_DIR/pr-4.9.1"
    echo "OPEN" >"$GH_DIR/pr-4.10.0"
    : >"$GH_LOG"
    run "$INSTANTANES"
    [ "$(supprimes)" = "livraison/v4.9.1" ]
    [[ "$output" == *"supprimé (PR de livraison fermée sans fusion)"* ]] || false
}

@test "instantanes : en attente la plus recente, PR ouverte, commits propres -> conserves" {
    fake_gh_instantanes
    # 1.10.0 > 1.9.0 (comparaison numérique) : non publiée, la plus récente,
    # conservée même si sa PR est fermée
    export GH_TAGS="v1.9.0" GH_INSTANTANES="1.2.0 1.8.0 1.9.5 1.9.6 1.10.0"
    echo "CLOSED" >"$GH_DIR/pr-1.10.0"
    # publiée, mais encore source d'une PR ouverte
    echo "CLOSED OPEN" >"$GH_DIR/pr-1.2.0"
    # publiée, mais 2 commits absents de develop ; comparaison impossible
    echo 2 >"$GH_DIR/avance-1.8.0"
    echo "CLOSED" >"$GH_DIR/pr-1.9.5"
    echo erreur >"$GH_DIR/avance-1.9.5"
    # non publiée, sans PR, pas la plus récente : rien ne dit qu'elle est abandonnée
    run "$INSTANTANES"
    [ "$status" -eq 0 ]
    [ -z "$(supprimes)" ]
    [[ "$output" == *"livraison/v1.10.0 conservée : livraison en attente la plus récente"* ]] || false
    [[ "$output" == *"livraison/v1.2.0 conservée : PR de livraison ouverte"* ]] || false
    [[ "$output" == *"::warning::livraison/v1.8.0 conservée (v1.9.0 publiée) : 2 commit(s) absent(s) de develop"* ]] || false
    [[ "$output" == *"::warning::livraison/v1.9.5 conservée (PR de livraison fermée sans fusion) : ? commit(s)"* ]] || false
    ! grep -q "compare/develop...livraison/v1.9.6" "$GH_LOG"
    # aucune version publiée : seule une PR fermée compte
    export GH_TAGS="" GH_INSTANTANES="0.1.0 0.2.0"
    echo "CLOSED" >"$GH_DIR/pr-0.1.0"
    : >"$GH_LOG"
    run "$INSTANTANES"
    [ "$(supprimes)" = "livraison/v0.1.0" ]
    # API en échec : avertissement, rien supprimé, le run n'échoue pas
    GH_ERREUR=1 run "$INSTANTANES"
    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::Instantanés de livraison : tags illisibles"* ]] || false
}

@test "release-auto : instantanes nettoyes sur integration et principale, remplacement sans suppression directe" {
    local wf="$BATS_TEST_DIRNAME/../.github/workflows/release-auto.yml" etape
    etape="$(awk '/- name: Instantanés de livraison abandonnés$/ { j = 1 } j && /- name: / && !/abandonnés$/ { j = 0 } j' "$wf")"
    [[ "$etape" == *"inputs.delivery-environment != ''"* ]] || false
    [[ "$etape" == *"inputs.integration-branch"*"inputs.main-branch"* ]] || false
    [[ "$etape" == *"bash .repowarden-ci/ci/instantanes.sh"* ]] || false
    # après le tag et la release (version publiée) : étape placée après
    awk '/- name: Tag et release$/ { t = NR } /- name: Instantanés de livraison abandonnés$/ { i = NR } END { exit !(t && i > t) }' "$wf"
    # la demande remplacée garde son instantané jusqu'au contrôle (commits absents)
    run grep -n 'delete-branch' "$wf"
    [ -z "$output" ] || false
}

# --- Code mort (ci/check.sh deadcode) : outils simulés ---------------------------

# Faux ruff et vulture : signalent une ligne de chaque fichier Python listé
fake_python_tools() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/ruff" <<'T'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "ruff 0.0"; exit 0; }
for f in $(git ls-files '*.py'; git ls-files --others --exclude-standard '*.py'); do
    echo "$f:1:8: F401 [*] \`os\` imported but unused"
done
T
    cat >"$BATS_TEST_TMPDIR/bin/vulture" <<'T'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "vulture 0.0"; exit 0; }
for f in $(git ls-files '*.py'; git ls-files --others --exclude-standard '*.py'); do
    echo "$f:2: unused function 'aide' (60% confidence)"
done
T
    chmod +x "$BATS_TEST_TMPDIR/bin/ruff" "$BATS_TEST_TMPDIR/bin/vulture"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Base : ancien.py (code mort existant) ; branche : nouveau.py
python_dead_code() {
    echo "requests" >requirements.txt
    printf 'import os\ndef ancienne():\n    pass\n' >ancien.py
    git add -A
    git commit -q --no-verify -m "chore: base"
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    printf 'import os\ndef aide():\n    pass\n' >nouveau.py
    git add -A
    git commit -q --no-verify -m "feat: nouveau"
}

@test "code mort : seul le nouveau code compte, le prouve bloque" {
    fake_python_tools
    python_dead_code
    run "$CHECK" deadcode
    [ "$status" -ne 0 ]
    [[ "$output" == *"nouveau.py:1 : \`os\` imported but unused (code mort prouvé)"* ]] || false
    [[ "$output" == *"nouveau.py:2 : unused function 'aide' (60 %) (candidat"* ]] || false
    [[ "$output" != *"ancien.py"* ]] || false
    [[ "$output" == *"1 élément(s) de code mort prouvé"* ]] || false
}

@test "code mort : modes warn (rien ne bloque) et strict (candidats compris)" {
    fake_python_tools
    python_dead_code
    git config repowarden.deadcode warn
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    git config repowarden.deadcode strict
    git config repowarden.deadcodeIgnore "nouveau.py"
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucun nouveau code mort"* ]] || false
}

@test "code mort : outil absent -> signale, sans echec meme en mode strict" {
    # ruff et vulture « absents » : ils échouent à --version (portable, Windows compris)
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    for t in ruff vulture; do printf '#!/bin/sh\nexit 127\n' >"$BATS_TEST_TMPDIR/bin/$t"; chmod +x "$BATS_TEST_TMPDIR/bin/$t"; done
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    python_dead_code
    REPOWARDEN_STRICT=true run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"ruff / vulture absent"* ]] || false
}

# Faux ruff seul : rien à signaler (code sain), vulture échoue à --version
# (absent, même s'il serait installé sur la machine)
fake_ruff_only() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/ruff" <<'T'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "ruff 0.0"; exit 0; }
exit 0
T
    printf '#!/bin/sh\nexit 127\n' >"$BATS_TEST_TMPDIR/bin/vulture"
    chmod +x "$BATS_TEST_TMPDIR/bin/ruff" "$BATS_TEST_TMPDIR/bin/vulture"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Faux vulture seul (ruff absent) : rien à signaler (code sain)
fake_vulture_only() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/vulture" <<'T'
#!/usr/bin/env bash
[ "$1" = --version ] && { echo "vulture 0.0"; exit 0; }
exit 0
T
    printf '#!/bin/sh\nexit 127\n' >"$BATS_TEST_TMPDIR/bin/ruff"
    chmod +x "$BATS_TEST_TMPDIR/bin/ruff" "$BATS_TEST_TMPDIR/bin/vulture"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "code mort : ruff seul -> analyse partielle, pas de feu vert sans reserve" {
    fake_ruff_only
    python_dead_code
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"Python : vulture absent : fonctions et classes inutilisées non analysées (pip install vulture)."* ]] || false
    [[ "$output" == *"Aucun nouveau code mort dans ce qui a été analysé : analyse partielle, voir ci-dessus."* ]] || false
    [[ "$output" != *"Aucun nouveau code mort."* ]] || false
}

@test "code mort : vulture seul -> analyse partielle sur ruff signalee" {
    fake_vulture_only
    python_dead_code
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"Python : ruff absent : imports et variables inutilisés non analysés (pip install ruff)."* ]] || false
    [[ "$output" == *"Aucun nouveau code mort dans ce qui a été analysé : analyse partielle, voir ci-dessus."* ]] || false
    [[ "$output" != *"Aucun nouveau code mort."* ]] || false
}

@test "code mort : aucun outil -> analyse partielle, jamais un feu vert sans reserve" {
    # ruff et vulture « absents » : ils échouent à --version (portable, Windows compris)
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    for t in ruff vulture; do printf '#!/bin/sh\nexit 127\n' >"$BATS_TEST_TMPDIR/bin/$t"; chmod +x "$BATS_TEST_TMPDIR/bin/$t"; done
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    python_dead_code
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"ruff / vulture absent"* ]] || false
    [[ "$output" == *"Aucun nouveau code mort dans ce qui a été analysé : analyse partielle, voir ci-dessus."* ]] || false
    [[ "$output" != *"Aucun nouveau code mort."* ]] || false
}

@test "code mort : typescript seul -> analyse partielle sur knip signalee" {
    mkdir -p node_modules/.bin
    printf '#!/bin/sh\nexit 0\n' >node_modules/.bin/tsc
    chmod +x node_modules/.bin/tsc
    echo "node_modules/" >.gitignore
    echo "{}" >package.json
    echo "{}" >tsconfig.json
    git add -A
    git commit -q --no-verify -m "chore: base"
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    echo "export const a = 1;" >app.ts
    git add -A
    git commit -q --no-verify -m "feat: app"
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"JavaScript / TypeScript : knip absent : fichiers, exports et dépendances non référencés non analysés (npm i -D knip)."* ]] || false
    [[ "$output" == *"Aucun nouveau code mort dans ce qui a été analysé : analyse partielle, voir ci-dessus."* ]] || false
    [[ "$output" != *"Aucun nouveau code mort."* ]] || false
}

@test "code mort : sortie PMD (Java) interpretee" {
    mkdir -p "$BATS_TEST_TMPDIR/bin" src/a
    printf '#!/bin/sh\nprintf "src/a/A.java:3:\\tUnnecessaryImport:\\tUnused import x\\n"; exit 4\n' >"$BATS_TEST_TMPDIR/bin/pmd"
    chmod +x "$BATS_TEST_TMPDIR/bin/pmd"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    echo "<project/>" >pom.xml
    git add -A
    git commit -q --no-verify -m "chore: base"
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    printf 'package a;\n\nimport x;\nclass A {}\n' >src/a/A.java
    git add -A
    git commit -q --no-verify -m "feat: a"
    run "$CHECK" deadcode
    [ "$status" -ne 0 ]
    [[ "$output" == *"src/a/A.java:3 : Unused import x (code mort prouvé)"* ]] || false
}

# --- ci/notifier.sh (canal de l'équipe) : curl simulé ---------------------------

NOTIFIER="$BATS_TEST_DIRNAME/../ci/notifier.sh"

fake_curl() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/curl" <<'T'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = -d ] && { shift; printf '%s' "$1" >"$CURL_BODY"; }; shift; done
exit "${CURL_EXIT:-0}"
T
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" CURL_BODY="$BATS_TEST_TMPDIR/body.json"
}

@test "notification : format adapte a Slack, Discord, Teams ; texte echappe" {
    require python3
    fake_curl
    REPOWARDEN_WEBHOOK=https://hooks.slack.com/services/x run "$NOTIFIER" ci.notify.released 'acme/app' 'v1.2.0' 'https://x/"y"'
    [ "$status" -eq 0 ]
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert d["text"]=="🚀 acme/app v1.2.0 publiée : https://x/\"y\""' "$CURL_BODY"
    REPOWARDEN_WEBHOOK=https://discord.com/api/webhooks/x run "$NOTIFIER" ci.notify.failure acme/app https://run
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert d["content"].startswith("❌ acme/app")' "$CURL_BODY"
    REPOWARDEN_WEBHOOK=https://prod-01.westeurope.logic.azure.com/workflows/x run "$NOTIFIER" ci.notify.waiting acme/app 12 https://pr
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert "#12" in d["attachments"][0]["content"]["body"][0]["text"]' "$CURL_BODY"
}

@test "notification : sans adresse rien n'est envoye ; un echec d'envoi ne casse rien" {
    fake_curl
    rm -f "$CURL_BODY"
    REPOWARDEN_WEBHOOK= run "$NOTIFIER" ci.notify.released a v1 u
    [ "$status" -eq 0 ]
    [ ! -e "$CURL_BODY" ]
    CURL_EXIT=22 REPOWARDEN_WEBHOOK=https://hooks.slack.com/x run "$NOTIFIER" ci.notify.released a v1 u
    [ "$status" -eq 0 ]
    [[ "$output" == *"release non affectée"* ]] || false
}

@test "code mort : script isole sans fichier de projet -> analyse quand meme" {
    fake_python_tools
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    printf 'import os\ndef aide():\n    pass\n' >script.py
    git add -A
    git commit -q --no-verify -m "feat: script"
    run "$CHECK" deadcode
    [ "$status" -ne 0 ]
    [[ "$output" == *"script.py:1"*"(code mort prouvé)"* ]] || false
}

@test "code mort : aucun fichier analysable -> le dire, sans pretendre que tout va bien" {
    export REPOWARDEN_BASE="$(git rev-parse HEAD)"
    echo note >NOTES.txt
    git add -A
    git commit -q --no-verify -m "docs: note"
    run "$CHECK" deadcode
    [ "$status" -eq 0 ]
    [[ "$output" == *"rien à vérifier"* ]] || false
    [[ "$output" != *"Aucun nouveau code mort"* ]] || false
}

@test "code-mort : aucune modification -> message clair, pas aucun langage" {
    git update-ref refs/remotes/origin/main HEAD
    run "$BATS_TEST_DIRNAME/../bin/code-mort"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Aucune modification par rapport à origin/main"* ]] || false
    [[ "$output" != *"langage analysable"* ]] || false
}

# --- ci/merger-pr.sh : validation par la CI puis merge (gh simulé) --------------

fake_gh_merge() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
    "pr view "*"headRefName"*) echo main ;;
    "pr view "*"headRefOid"*) echo abc123 ;;
    "pr view "*"--json state"*) echo OPEN ;;
    "pr view "*"mergeStateStatus"*) echo CLEAN ;;
    "api repos/"*"/commits/"*) echo abc123 ;;
    "api repos/"*"/rules/branches/"*) echo repowarden ;;
    "run list "*) echo 101 ;;
    "run view 101 --json jobs"*) echo success ;;
    "run view 101 --json url"*) echo https://exemple/run/101 ;;
esac
exit 0
GH
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export GH_REPO=o/r WORKFLOWS=ci.yml BASE=develop GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"
    : >"$GH_LOG"
    : >"$GITHUB_OUTPUT"
}

@test "merger-pr : CI lancee, verifications reportees en statut, merge commit" {
    fake_gh_merge
    run bash "$BATS_TEST_DIRNAME/../ci/merger-pr.sh" 9 merge
    [ "$status" -eq 0 ]
    grep -qx "workflow run ci.yml --ref main" "$GH_LOG"
    grep -q "api repos/o/r/statuses/abc123 -f state=success -f context=repowarden" "$GH_LOG"
    grep -qx "pr merge 9 --merge --match-head-commit abc123" "$GH_LOG"
    grep -qx "merged=true" "$GITHUB_OUTPUT"
    # retour vers develop : la branche source (main) n'est jamais supprimée
    ! grep -q "api -X DELETE" "$GH_LOG"
}

@test "merger-pr : merge-auto false -> PR validee, laissee a un humain" {
    fake_gh_merge
    MERGE_AUTO=false run bash "$BATS_TEST_DIRNAME/../ci/merger-pr.sh" 9 squash
    [ "$status" -eq 0 ]
    ! grep -q "^pr merge" "$GH_LOG"
    grep -qx "waiting_pr=9" "$GITHUB_OUTPUT"
}

@test "code-mort : seuls des .md et .yml modifies -> pas d'analyse JavaScript" {
    git update-ref refs/remotes/origin/main HEAD
    printf '# Doc\n' >NOTES.md
    printf 'a: 1\n' >conf.yml
    run "$BATS_TEST_DIRNAME/../bin/code-mort"
    [ "$status" -eq 0 ]
    [[ "$output" != *"JavaScript"* ]] || false
}

@test "langue : scripts sans configuration complete -> lang du .repowarden.conf (meme en CI)" {
    printf '[repowarden]\n    lang = fr\n' >.repowarden.conf
    run env -u REPOWARDEN_LANG CI=true GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        bash -c "source '$HOOKS/lib/ui.sh'; source '$HOOKS/lib/i18n.sh'; echo \$REPOWARDEN_LANG"
    [ "$output" = fr ]
}
