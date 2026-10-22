# Déployer repowarden dans une organisation

repowarden impose les mêmes règles à tous les projets (messages de commit, nommage des branches, secrets, formatage, tests) à **trois niveaux** :

| Niveau | Rôle | Contournable ? |
|---|---|---|
| Poste développeur — hooks repowarden (installation globale) | Retour immédiat, corrections automatiques (formatage, préfixe de commit) | Oui (`--no-verify`) |
| CI — action GitHub / template GitLab | **Fait foi** : mêmes vérifications sur chaque merge request | Non |
| Serveur — protection des branches | Interdit de merger si la CI échoue, interdit le push direct sur `main` | Non |

Les hooks locaux font gagner du temps ; **la CI et la protection des branches garantissent les règles**.

## 1. Héberger repowarden

Le dépôt doit être **lisible par tous les développeurs et par la CI** :

- GitLab : importer/mirrorer le dépôt dans un groupe interne (ex. `outils/repowarden`) ;
- GitHub : dépôt public, ou interne à l'organisation.

Remplacer `simdevWarden/repowarden` par ce chemin dans les templates (`templates/`).

## 2. Versions et releases (automatiques)

Les projets peuvent obtenir les mêmes releases automatiques : voir [Versions et releases](releases.md). Ci-dessous, celles de repowarden lui-même.

Les numéros de version sont **calculés automatiquement** à partir des Conventional Commits par [release-please](https://github.com/googleapis/release-please) :

| Commits depuis la dernière release | Nouvelle version |
|---|---|
| `fix: …` | correctif : 1.4.**2** → 1.4.**3** |
| `feat: …` | fonctionnalité : 1.**4**.2 → 1.**5**.0 |
| `feat!: …` ou `BREAKING CHANGE:` dans le corps | majeure : **1**.4.2 → **2**.0.0 |

À chaque push sur `main`, le workflow `release` :

1. met à jour la PR « release x.y.z » (changelog + version dans les templates) ;
2. lance la CI sur cette PR et attend les vérifications obligatoires ;
3. la merge, crée le tag `vX.Y.Z` et la release, déplace le tag majeur `vX` et joint une archive signée.

**Aucun jeton à créer** : le workflow n'utilise que `GITHUB_TOKEN` (il déclenche la CI par `workflow_dispatch`, seul type d'événement autorisé à ce jeton). Prérequis : *Settings → Actions → General → Allow GitHub Actions to create and approve pull requests*.

Pour suspendre les releases automatiques : désactiver le workflow `release` (*Actions → release → Disable workflow*).

Politique conseillée pour les projets : **figer une version exacte** (`ref: v1.4.2`) et la monter volontairement (Renovate/Dependabot peuvent proposer la mise à jour). Une règle plus stricte = version majeure.

## 3. Poste développeur

Installer repowarden une fois par poste, pour tous les dépôts :

```bash
npm install -g repowarden   # registre interne : voir « Sources internes » plus bas
repowarden install --global
```

La version minimale attendue par un projet se déclare dans son `.repowarden.conf` (`version`) : un poste en retard est prévenu à chaque commit, avec la commande de mise à jour. Les commandes propres au projet se déclarent dans `.repowarden/<hook>` ([Configuration](configuration.md#hooks-propres-au-projet)).

Outils recommandés : `gitleaks` (secrets) et les formateurs des langages utilisés (voir [Technologies](technologies.md)).

Un poste sans hooks ne bloque personne : la CI refait toutes les vérifications et fait foi. `repowarden` (sans argument) affiche l'état du poste et l'étape suivante.

## 4. Adopter repowarden dans un projet

**Sur GitHub** : `repowarden bots`, lancé par une personne avec les droits d'administration (aussi proposé par `repowarden install`). Il demande le flux (`main` seule, ou `develop` → `main`, avec création de `develop` après accord), puis un accord par bot : CI (`repowarden.yml`, avec l'outillage des langages détectés à la racine — Python, Node, Java Maven / Gradle, Go — en versions figées, et `strict: true` quand le formatage et les tests sont outillés ; langage non reconnu : modèle générique à compléter), releases (`release.yml`, avec le job `tickets` si le suivi des tickets est choisi ou déjà en place), nettoyage (`nettoyage.yml`, flux develop), tickets (`repowarden tickets init`), GitHub App (`repowarden app init`), protection (`repowarden proteger`), npm (`repowarden npm-publication`, paquet public seulement). Dans le flux `develop` → `main`, avec les releases, trois questions sur la livraison ([détail](releases.md#livraison-approuvee-ou-automatique)) : automatique ou approbation humaine (défaut), rythme à chaque ticket ou regroupé (défaut), préversion obligatoire (oui par défaut) ; les réponses par défaut donnent le `release.yml` habituel. Il montre ensuite l'aperçu (fichiers créés, fichiers existants gardés avec leur écart avec le modèle, réglages modifiés) et attend la confirmation. Les fichiers écrits sont ensuite à commiter par une PR. Sans terminal, sans `gh` connecté ou sans droits d'administration, rien n'est proposé : une ligne dit pourquoi. `repowarden install --sans-bots` : plus jamais proposé.

**À la main**, copier depuis `templates/project/` :

| Fichier | Rôle |
|---|---|
| `.github/workflows/repowarden.yml` | CI GitHub (ajouter les `setup-*` des outils du projet) |
| `gitlab-ci.yml` | À fusionner dans `.gitlab-ci.yml` (choisir une image avec les outils du projet) |
| `.repowarden.conf` | Réglages partagés : exceptions de branches, étapes désactivées, commandes personnalisées |

`.repowarden.conf` est lu **par les hooks et par la CI** : une exception décidée en revue de code s'applique partout.

Avec `strict: true` (GitHub) / `REPOWARDEN_STRICT: "true"` (GitLab), un outil de formatage ou de test absent de l'image CI fait échouer la vérification au lieu d'être ignoré.

## 5. Protéger les branches (serveur)

### Merges en squash

Une PR = un commit sur `main`, dont le message est le **titre de la PR** : changelog propre, une ligne par PR. Réglages (*Settings → General → Pull Requests*) : autoriser uniquement *squash merging*, message par défaut *Pull request title*. La CI repowarden vérifie que ce titre suit Conventional Commits ; utiliser `!` dans le titre pour un changement majeur (`feat!: …`).

### Branches mergées : supprimées automatiquement

- Serveur — GitHub : *Settings → General → Automatically delete head branches* ; GitLab : *Settings → Merge requests → Enable "Delete source branch" option by default*.
- Flux `develop` : une branche `release/…` ou `hotfix/…` est mergée deux fois (vers `main` et `develop`) ; la suppression automatique de GitHub la supprimerait après le premier merge. Le workflow réutilisable `nettoyage-branches.yml` la conserve tant qu'une autre PR ouverte l'utilise (`repowarden proteger` désactive alors la suppression automatique) :

  ```yaml
  on:
    pull_request:
      types: [closed]
  jobs:
    nettoyage:
      uses: simdevWarden/repowarden/.github/workflows/nettoyage-branches.yml@v4
      permissions: { contents: write, pull-requests: read }
  ```

- Instantanés de livraison (mode tag avec `delivery-environment`) : le workflow `release-auto.yml` supprime lui-même une branche `livraison/vX.Y.Z` dont la version est publiée (tag stable ≥ X.Y.Z) ou dont la PR de livraison a été fermée sans fusion (demande remplacée ou refusée), à chaque run sur `develop` et après chaque release sur `main`, seulement si elle ne contient aucun commit absent de `develop`. La livraison en attente la plus récente et un instantané encore source d'une PR ouverte sont toujours conservés ; un instantané avec des commits propres est signalé (avertissement du run), à vérifier puis supprimer à la main.

- Postes : le hook `post-merge` de repowarden supprime, après un `git pull`, les branches locales dont la branche distante a disparu et dont toutes les modifications sont dans la branche courante (merge classique ou squash) ; une branche avec du travail non intégré est conservée.

### GitHub

**En une commande**, d'après `.repowarden.conf` (branches protégées, flux `develop`) — relançable sans risque, `--dry-run` pour voir avant d'appliquer :

```bash
repowarden proteger --checks "repowarden,build"   # vérifications séparées par des virgules ; gh connecté (admin)
```

Le script pose le ruleset « repowarden » (PR obligatoire, vérifications exigées à jour, ni suppression ni push forcé), les modes de merge (squash ; avec un flux `develop` : merge commit sur `main`, **squash seul** sur `develop` (un commit par PR de travail : les commits intermédiaires n'y entrent jamais), qui devient la branche par défaut ; dans ce flux, les PR n'ont pas à être à jour de leur cible : le merge commit d'une livraison n'existe que sur `main` et bloquerait sinon la livraison suivante), réserve les tags `v*` aux workflows (ruleset « repowarden (tags) »), prend le titre de PR comme message de commit et autorise GitHub Actions à créer des PR (releases automatiques).

Avec un flux `develop`, il crée aussi l'étiquette `urgent` si elle manque : son merge lance tout de suite la demande de livraison.

**Ancien ruleset** (posé à la main ou par repogarde, sous un autre nom, qui exige encore la vérification `repogarde`) : le script le **reprend** (mis à jour en place, donc renommé) plutôt que de créer un second ruleset à côté ; les branches ne sont jamais un instant sans protection. S'il en reste plusieurs sur les mêmes branches, les autres sont listés avec la commande pour les supprimer, jamais supprimés par le script, et la commande échoue. Un refus de GitHub affiche son détail (ruleset concerné, message, erreurs) ; les autres rulesets sont quand même appliqués.

**Limites de GitHub** : sur un dépôt **privé** d'un compte **gratuit**, GitHub refuse les rulesets. `proteger` applique alors les autres réglages et l'indique (rendre le dépôt public, ou passer à GitHub Pro / Team) ; `--verifier` échoue avec le même message. GitHub y ignore aussi, sans erreur, le **merge automatique** : `proteger` relit le réglage après l'avoir posé et le signale (échec si `deliveryApproval = auto`) ; PR de travail et livraison se mergent alors à la main. `repowarden bots` le détecte avant la première question, explique ce qui ne fonctionnera pas et ne propose pas la livraison automatique (livraison validée par la revue de sa PR). Un réglage refusé par GitHub est affiché avec son détail, les autres restant appliqués. Dans le flux `develop`, le mode de merge ne pouvant pas être imposé par branche, le squash est désactivé (merge commit seul) : une livraison squashée casserait l'historique de `main`. Dans une **organisation** où l'exception « GitHub Actions » est refusée sur le ruleset des tags, les tags sont protégés comme sur un compte personnel (ni déplacés ni supprimés, création libre), avec un avertissement.

**Règles à jour ?** Après une mise à jour de repowarden ou de `.repowarden.conf`, `repowarden proteger --verifier` compare les règles en ligne à celles que `proteger` poserait, sans rien modifier : chaque écart est listé (« en ligne » / « attendu »), ainsi que tout ancien ruleset qui exige encore `repogarde`, et la commande échoue. Passer les mêmes `--checks` qu'à l'application : la liste des vérifications exigées n'est pas dans `.repowarden.conf`, et sans `--checks` elle n'est pas comparée. Attention, `repowarden proteger` sans `--checks` ramène les vérifications exigées à la seule `repowarden`.

À la main : *Settings → Rules → Rulesets* (ou *Branches → Branch protection rules*) sur `main` :

- Require a pull request before merging
- Require status checks to pass → ajouter **`repowarden`**
- Block force pushes
- (optionnel) Restrict branch names / commit metadata avec les [expressions régulières](ci.md#regles-cote-serveur)

### GitHub App des workflows

Ce que fait le jeton des Actions ne déclenche **aucun autre workflow** : une PR brouillon ouverte par le suivi des tickets n'a pas de CI, et un merge automatique ne lancerait ni préversion ni livraison. Une GitHub App propre au dépôt lève cette limite :

```bash
repowarden app init                  # une fois : « Create », puis « Install »
repowarden app init --administration # + droit d'administration (configuration appliquée par la CI)
```

La commande ouvre la page de création de GitHub, préremplie : permissions minimales (contenu, PR, tickets, statuts), sans webhook. Elle range l'identifiant (variable `REPOWARDEN_APP_CLIENT_ID`) et la clé privée (secret `REPOWARDEN_APP_KEY`) sans les afficher, puis ouvre la page d'installation. Les workflows obtiennent ensuite un jeton d'une heure à chaque run ; sans l'App, ils reprennent le jeton des Actions. L'App suit les mêmes règles que tout le monde : aucune exception dans les rulesets.

- **Relance** : une App déjà configurée n'est pas recréée. Son installation n'est alors **pas vérifiable** (seule la clé privée de l'App, absente du poste, permet de lister ses installations) : la commande l'annonce « non vérifiée », avec le lien d'installation `https://github.com/apps/<slug>/installations/new`, sans message de succès.
- **App non installée** : l'étape « Jeton de l'App » des workflows échoue (`Not Found - get-a-repository-installation…`) ; une annotation le dit, avec le lien d'installation (`release-auto` : erreur ; suivi des tickets : avertissement, il continue avec le jeton des Actions).
- **Commentaires du bot** : un clic sur l'avatar ou le nom de l'App mène à une page 404 (GitHub ne donne pas de profil aux Apps). Les commentaires du suivi des tickets se terminent donc par une ligne discrète vers la page de l'App (`https://github.com/apps/<slug>`) et cette section ; sans l'App (jeton des Actions), pas de ligne.
- **Nom déjà pris** (souvent une App orpheline d'un essai interrompu : créée sur GitHub, identifiants jamais rangés) : la commande s'arrête avant la création. Relancer avec `--nom <autre nom>`, ou supprimer l'App orpheline (Settings → Developer settings → GitHub Apps).

**Dans un conteneur** (devcontainer sans redirection de ports, par exemple `docker run` ou `make shell`), la page locale de création (`127.0.0.1`) et le retour de GitHub ne sont pas joignables depuis le navigateur de l'hôte : la commande le détecte, s'arrête **sans rien créer** et indique la commande à lancer sur l'hôte (`npx repowarden app init --repo propriétaire/nom`). VS Code Dev Containers et Codespaces redirigent les ports d'eux-mêmes : création normale. Si ton navigateur joint le `127.0.0.1` du conteneur (réseau de l'hôte), `REPOWARDEN_CONTENEUR=0` passe outre. Une page non consultée dans les 3 minutes (`REPOWARDEN_APP_DELAI`, en secondes) arrête aussi la commande proprement.

### Bot d'organisation

Le bot tient à jour **tous les projets** d'une organisation, depuis un **dépôt de pilotage**. Chaque nuit, il passe sur chaque dépôt où son App est installée :

- **protection** : `repowarden proteger --verifier`, puis `repowarden proteger` si les règles sont périmées. Les vérifications exigées sont celles de `requiredChecks`, sinon celles déjà en ligne : le bot n'en retire jamais ;
- **migration** : `repowarden migrer --pr`. Le code des projets ne change que **par PR**, relue et vérifiée par la CI comme les autres ;
- **rapport** : un tableau (dépôt, mode, protection, migration) dans le résumé du run et dans **une issue unique** « Rapport du bot repowarden » du dépôt de pilotage, mise à jour à chaque passage.

**Quels projets ?** L'installation de l'App dit ce que le bot **peut** toucher. Il faut l'installer sur « All repositories » : un nouveau dépôt est alors couvert dès sa création. Le projet dit ce qu'il **veut**, dans son `.repowarden.conf` (versionné, changé par PR relue) :

| `bot` | Effet |
|---|---|
| `auto` (défaut) | protection appliquée, PR de migration |
| `pr` | PR de migration seulement ; protection périmée signalée dans le rapport |
| `off` | dépôt ignoré |

Un dépôt **sans** `.repowarden.conf` n'est jamais touché : il apparaît « non adopté » dans le rapport. Pour l'adopter : `repowarden install` ou `repowarden tickets init` dans le projet.

**Mise en place**, une fois, dans le dépôt de pilotage (par exemple `<organisation>/repowarden-pilote`) :

```bash
repowarden bot init          # écrit .github/workflows/bot.yml (chaque nuit + lancement manuel)
repowarden app init --bot    # App du bot : workflows et administration ; installer sur « All repositories »
```

Ensuite, *Actions → bot → Run workflow*, avec la case `dry-run` pour voir ce qui serait fait sans rien modifier.

**Garde-fous** : la clé de l'App n'existe que dans le dépôt de pilotage, et le workflow ne tourne que depuis sa branche par défaut. L'App n'a aucune exception dans les rulesets. Une erreur sur un projet (détail de GitHub dans le rapport) n'arrête pas les autres.

### GitLab

- *Settings → Repository → Protected branches* : `main` → *Allowed to push: No one*, *Allowed to merge: Developers*
- *Settings → Merge requests* : **Pipelines must succeed**
- (Premium) *Settings → Repository → Push rules* : regex de nom de branche et de message de commit ([expressions régulières](ci.md#regles-cote-serveur))

## 6. Ce que vérifie la CI

`ci/check.sh` compare la branche à sa base (merge request, push précédent ou branche par défaut) :

| Vérification | Échoue si |
|---|---|
| `commits` | un message ou le titre de la PR n'est pas Conventional Commits, dépasse 72 caractères (format seul pour les bots de dépendances), ou est un `fixup!`/`squash!` non squashé |
| `branch` | le nom de branche ne respecte pas `<type>/<sujet>` (hors exceptions) ; dans un [flux `develop`](configuration.md#flux-avec-branche-dintegration-develop), la PR vise la mauvaise branche (reciblée automatiquement avec `fix-pr`) |
| `secrets` | gitleaks trouve un secret dans les commits de la branche |
| `format` | un fichier modifié n'est pas formaté (le formateur est lancé, rien n'est committé) |
| `tests` | les tests d'un projet touché échouent (monorepo : seulement les projets modifiés) |
| `deadcode` | du code mort **prouvé** est introduit (inaccessible, inutilisé dans sa portée) ; les candidats avertissent seulement ([Code mort](code-mort.md)) |

Les erreurs apparaissent en annotations sur GitHub et dans le log du job sur GitLab, avec la commande de correction.

## 7. Poste avec l'installation globale repowarden

Avec `install.sh --global` ou `repowarden install --global`, les hooks s'appliquent à tous les dépôts du poste, sans rien ajouter aux projets.

Un projet encore configuré avec lefthook (repowarden 3) : depuis repowarden 4, lefthook n'est plus pris en charge. Un hook installé par lefthook dans `.git/hooks` est ignoré, avec un avertissement. Déplacer les commandes du projet dans `.repowarden/<hook>`, la version attendue dans `.repowarden.conf` (`version`), puis `lefthook uninstall` ([Désinstallation](desinstallation.md)).

## 8. Sources internes (réseau fermé, Nexus, Artifactory…)

repowarden ne télécharge pas les dépendances des projets : il lance leurs outils (`mvn`, `gradle`, `npm`, `pip`, `go`…), qui utilisent leur configuration habituelle, sur le poste comme en CI.

| Outil | Rediriger vers la source interne |
|---|---|
| Maven | `~/.m2/settings.xml` : `<mirrors>` |
| Gradle | `repositories { maven { url = uri("…") } }`, ou un script d'init dans `~/.gradle/init.d/` (plugins : `pluginManagement` dans `settings.gradle.kts`) |
| npm, yarn, pnpm | `.npmrc` : `registry=…` (y compris pour installer `repowarden`) |
| pip | `pip.conf` : `index-url` |
| Go | `GOPROXY` |
| MegaLinter (Docker) | miroir de registre configuré sur le runner |

Ce que repowarden récupère lui-même :

| Élément | Source interne |
|---|---|
| repowarden (installation par clone) | miroir Git interne du dépôt : URL du `git clone`, variable `REPOWARDEN_URL` du modèle GitLab |
| Action GitHub `repowarden@v4` (GitHub Enterprise Server) | dépôt synchronisé dans l'organisation ([actions-sync](https://docs.github.com/en/enterprise-server/admin/managing-github-actions-for-your-enterprise/managing-access-to-actions-from-githubcom/manually-syncing-actions-from-githubcom)), puis `uses: <organisation>/repowarden@v4` |
| Outils installés en CI (gitleaks, PMD, actionlint) | **recommandé** : déjà présents dans l'image du runner, rien n'est alors téléchargé ; sinon `REPOWARDEN_DOWNLOAD_MIRROR` |

`REPOWARDEN_DOWNLOAD_MIRROR` remplace `https://github.com` dans les téléchargements, par exemple un dépôt « generic » Artifactory ou Nexus en proxy des releases GitHub (`https://artifactory.exemple.fr/artifactory/github`). L'empreinte SHA-256 ne vient **jamais** du miroir : celles des versions par défaut sont figées dans repowarden ; pour une autre version, la fournir dans `GITLEAKS_SHA256` ou `ACTIONLINT_SHA256`, sinon le téléchargement est refusé. Un miroir compromis ne peut donc pas faire installer un binaire modifié.
