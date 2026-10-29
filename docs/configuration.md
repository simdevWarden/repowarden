# Configuration

Tout est optionnel : sans configuration, repowarden détecte les langages et applique les règles par défaut.

## Fichier `.repowarden.conf` (partagé)

Versionné à la racine du projet, au format `git config`, lu **par les hooks et par la CI** : une exception décidée en revue s'applique partout.

```ini
[repowarden]
    version = 3.1                       # version minimale de repowarden attendue sur les postes
    # Commandes personnalisées : remplacent la détection automatique
    format = npm run lint:fix --        # reçoit les fichiers stagés en arguments
    test = make ci                      # lancée à la racine ; fichiers modifiés sur l'entrée standard
    # Réglages
    skip = protect-branch python        # étapes, hooks ou langages désactivés
    protectedBranches = main develop    # commit et push directs interdits ; défaut : main master
    allowedBranches = main develop release/*
    exclude = vendor/* generated/*      # chemins ni formatés ni testés
    allowAgentSignatures = false        # agents IA (auteur, Co-Authored-By) refusés ; défaut false
    agentsTickets = false               # un agent IA peut créer un ticket (repowarden ticket nouveau) ; défaut false
    releaseUpdate = npm update -g mon-outil   # commande « Mettre à jour » des notes de version
    sensitiveFiles = .env .env.* *.pem  # noms signalés s'ils ne sont ni suivis ni ignorés (voir Hooks)
    # Bot d'organisation (repowarden bot)
    bot = auto                          # auto (défaut) : protection appliquée et PR de migration ; pr : PR seulement ; off : ignoré
    requiredChecks = repowarden,tests   # vérifications exigées posées par le bot ; défaut : celles en ligne
```

`version` : si repowarden est plus ancien sur un poste, les hooks le signalent avec la commande de mise à jour (`npm update -g repowarden`, ou `git pull` pour un clone). C'est un avertissement seulement : la CI vérifie chaque PR à sa propre version.

`agentsTickets` : à `true`, le garde-fou laisse un agent IA créer un ticket (`repowarden ticket nouveau`) ; par défaut, il le refuse et demande de signaler le défaut au mainteneur, qui le crée, ou de le noter sur le ticket en cours.

## Flux avec branche d'intégration (`develop`)

Par défaut, tout part de `main` et y revient par PR. Pour un flux à deux branches longues, où le travail s'intègre dans `develop` puis est livré sur `main` :

```ini
[repowarden]
    integrationBranch = develop     # active le flux
    mainBranch = main               # défaut : main
    protectedBranches = main develop
    allowedBranches = main develop release/* release-please--* dependabot/* renovate/*
```

La CI vérifie alors la cible de chaque PR :

| Branche de la PR                                   | Cible attendue      |
| -------------------------------------------------- | ------------------- |
| travail (`feat/…`, `fix/…`), bots (`dependabot/…`) | `develop`           |
| `develop`                                          | `main`              |
| `release/…`, `hotfix/…`                            | `develop`           |

Seul `develop` entre dans `main` : tout, correctif urgent compris, passe par ses préversions de test avant la production.

**Branche `develop` sans flux déclaré** : si `develop` existe mais que `integrationBranch` est absent, repowarden traiterait le projet comme « `main` seule ». La CI refuse alors une PR de travail vers `main`, et `repowarden statut` le signale : déclarer `integrationBranch = develop`, ou supprimer `develop`.

Une PR mal ciblée est refusée, avec la commande de correction (`gh pr edit --base develop`). Avec l'entrée `fix-pr: true` de l'action, elle est **reciblée automatiquement** (ou fermée si une PR de la même branche vise déjà la bonne cible), et un titre non conforme est remplacé : par le commit conforme au plus fort impact de version (incompatible, puis `feat`, puis `fix`/`perf` ; « ! » ajouté si un pied `BREAKING CHANGE` existe), sinon déduit de la branche.

## Réglages locaux (non partagés)

Prioritaires sur `.repowarden.conf` :

```bash
git config repowarden.skip true                    # désactive tout
git config repowarden.skip "pre-push"              # désactive un hook
git config repowarden.skip "protect-branch,format" # désactive des étapes
git config repowarden.skip "node"                  # désactive un langage
```

**Sauter une étape une seule fois**, sans rien changer à la configuration : `git -c repowarden.skip=<valeur> <commande>`.

```bash
git -c repowarden.skip=tests push                   # ce push sans les tests
git -c repowarden.skip=protect-branch commit -m "…" # ce commit sur une branche protégée
```

Les messages de refus donnent la marche à suivre (créer une branche, la renommer…), jamais la commande pour désactiver la règle : sauter une étape reste un choix délibéré, à faire ponctuellement.

## Ce qui peut être désactivé (`skip`)

| Catégorie          | Valeurs                                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| Hooks              | `pre-commit`, `prepare-commit-msg`, `commit-msg`, `pre-push`, `post-checkout`, `post-merge`      |
| Étapes             | `branch-name`, `protect-branch`, `secrets`, `sensitive-files`, `format`, `tests`, `deadcode`, `comments`, `prune-branches` |
| Langages et outils | `maven`, `gradle`, `node`, `python`, `go`, `helm`, `docker`… (nom du fichier dans `hooks/lang/`) |
| Tout               | `true`                                                                                           |

## Hooks propres au projet

Un script exécutable `.repowarden/<hook>` (ou `.git/hooks/<hook>`) est lancé en plus, avant les vérifications communes. C'est là que se déclarent les commandes propres au projet (lefthook n'est plus pris en charge depuis repowarden 4 : un hook installé par lefthook dans `.git/hooks` est ignoré, avec un avertissement).

## Affichage

Tous les messages de repowarden (hooks, CI, assistant `git cc`, installation) suivent la même charte : `✔` succès en vert, `✖` erreur en rouge, `⚠` avertissement en jaune, `ℹ` information en bleu, `▶` étape en cours en cyan, aides en gris atténué.

Les couleurs s'affichent dans un terminal et dans les logs de l'action GitHub. Elles sont désactivées par `NO_COLOR=1`, par `TERM=dumb` ou quand la sortie est redirigée (fichier, tube) ; `FORCE_COLOR=1` les impose.

## Langue des messages

Français ou anglais, choisi **une fois à l'installation** (question posée, ou `./install.sh --global --lang en`) et enregistré dans `repowarden.lang`. Ordre de priorité :

| Où | Langue utilisée |
|---|---|
| Poste | `REPOWARDEN_LANG`, sinon `repowarden.lang` (installation), sinon `lang` de `.repowarden.conf`, sinon la langue du système |
| CI | `REPOWARDEN_LANG`, sinon `lang` de `.repowarden.conf` (langue de l'équipe), sinon anglais |
| Bot des tickets (`tickets.yml`) | entrée `lang` du workflow, sinon `lang` du `.repowarden.conf` de la branche par défaut (lu par l'API), sinon anglais |

## Plateforme (GitHub, GitLab, Bitbucket, Gitea)

repowarden reconnaît la plateforme et adapte son vocabulaire (PR ou MR) et ses exemples (`Closes #12`, `!34` sur GitLab, `PROJ-42` sur Bitbucket) : réglage `forge`, sinon variables de la CI (GitHub Actions, GitLab CI, Bitbucket Pipelines, Gitea / Forgejo Actions), sinon adresse du remote `origin`. Un GitLab auto-hébergé dont l'adresse ne contient pas « gitlab » se déclare :

```ini
[repowarden]
    forge = gitlab        # github, gitlab, bitbucket, gitea
```

## Sources internes (proxy, Nexus, Artifactory)

Sans accès direct à Internet, ou pour passer par les dépôts de l'entreprise : les outils des projets (Maven, Gradle, npm, pip, Go…) utilisent leur propre configuration (`settings.xml`, `.npmrc`…), et repowarden peut récupérer ses outils de CI via un miroir (`REPOWARDEN_DOWNLOAD_MIRROR`), empreintes vérifiées. Détail : [En organisation, sources internes](industrialisation.md#8-sources-internes-reseau-ferme-nexus-artifactory).
