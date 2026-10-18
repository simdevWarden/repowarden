# Démarrage rapide

Trois parcours, selon l'usage. Le plus rapide pour essayer : **Sur mon poste**.

=== "Sur mon poste"

    Tous tes dépôts, sans rien ajouter aux projets ni à leur `package.json` :

    ```bash
    npm install -g repowarden     # 1. le paquet (yarn global add, pnpm add -g : idem)
    repowarden install --global           # 2. active les hooks : demande la langue, installe git cc
    repowarden                            # 3. vérifie : état du poste et étape suivante
    ```

    L'étape 2 est indispensable : par sécurité, le paquet n'exécute rien à l'installation (aucun script `postinstall`).

    Essai immédiat, dans n'importe quel dépôt :

    ```bash
    git switch -c feat/panier            # nom de branche vérifié
    git add . && git cc                  # assistant de commit (type, scope, description…)
    git push -u origin feat/panier       # tests des projets touchés avant l'envoi
    repowarden code-mort                  # nouveau code mort de la branche
    ```

    | Action | Commande |
    |---|---|
    | État du poste, étape suivante | `repowarden` (ou `repowarden statut`) |
    | Toutes les commandes | `repowarden --help` |
    | Vérifier | `git config --global core.hooksPath` → `…/repowarden/hooks` |
    | Mettre à jour | `npm update -g repowarden` (les hooks suivent) |
    | Tester la prochaine version | `npm install -g repowarden@next` (retour : `@latest`) |
    | Changer de langue | `repowarden install --global --lang en` |
    | Un seul dépôt | `cd mon-projet && repowarden install` |
    | Bots du dépôt GitHub (CI, releases, tickets, protection…) | `repowarden bots` (proposé par `repowarden install` dans un dépôt GitHub ; `--sans-bots` pour ne plus le voir) |
    | Désinstaller | `repowarden uninstall --global`, puis `npm uninstall -g repowarden` ([désinstallation complète](desinstallation.md)) |

    `npx` est refusé pour l'installation globale : son dossier temporaire peut être effacé à tout moment. Avec nvm, chaque version de Node a ses propres paquets globaux : relancer `repowarden install --global` après un changement de version.

    **Registre npm interne** (entreprise, proxy) : `npm install -g repowarden --registry <url>`, ou `registry=<url>` dans `~/.npmrc` ; voir [sources internes](industrialisation.md#8-sources-internes-reseau-ferme-nexus-artifactory).

    **Sans Node** : même résultat depuis un clone, mis à jour avec `git -C ~/repowarden pull` (les commandes deviennent `~/repowarden/install.sh`, `~/repowarden/bin/code-mort`…).

    ```bash
    git clone https://github.com/simdevWarden/repowarden.git ~/repowarden
    ~/repowarden/install.sh --global
    ```

=== "Un projet d'équipe"

    1. **Chaque personne** installe repowarden une fois sur son poste (onglet « Sur mon poste ») : `npm install -g repowarden`, puis `repowarden install --global`.

    2. **Le projet**, sur GitHub : `repowarden bots` (une personne avec les droits d'administration) propose chaque bot (CI, releases, nettoyage, tickets, GitHub App, protection, npm), montre ce qui sera créé ou modifié, puis attend la confirmation. Rien n'est fait sans accord, et un fichier existant n'est jamais écrasé. Sinon, à la main, il ajoute les modèles de [`templates/project/`](https://github.com/simdevWarden/repowarden/tree/main/templates/project) :

        | Fichier | Rôle |
        |---|---|
        | `.github/workflows/repowarden.yml` | CI GitHub : refait les vérifications sur chaque PR, elle fait foi (ajouter les `setup-*` des outils du projet) |
        | `.repowarden.conf` | réglages partagés, dont `version` : version minimale de repowarden attendue sur les postes |
        | `.github/workflows/release.yml` | [releases automatiques](releases.md) (optionnel) |
        | `gitlab-ci.yml` | pour GitLab, à fusionner dans `.gitlab-ci.yml` |

    3. **Rendre la CI obligatoire** pour merger : `repowarden proteger` (voir [En organisation](industrialisation.md)).

    Un poste dont repowarden est plus ancien que la `version` du projet est prévenu à chaque commit, avec la commande de mise à jour. Sans hooks, la CI refait de toute façon toutes les vérifications.

=== "Une organisation"

    Le [guide En organisation](industrialisation.md) couvre l'hébergement de repowarden, les versions, l'installation automatique sur les postes (Maven, Gradle, npm) et la protection des branches GitHub / GitLab.

=== "Contribuer à repowarden"

    ```bash
    git clone https://github.com/simdevWarden/repowarden.git && cd repowarden
    ./install.sh                         # repowarden se vérifie lui-même
    bats test/                           # tests (bats-core), aussi lancés au push
    ```

    Voir [Contribuer](contribuer.md).

## Prérequis

| Élément | Requis | Notes |
|---|---|---|
| git + bash | oui | macOS, Linux, Windows via [Git for Windows](https://gitforwindows.org) |
| Outils des langages utilisés | selon les projets | un outil absent est ignoré sur le poste |
| [gitleaks](https://github.com/gitleaks/gitleaks) | conseillé | `brew install gitleaks` · `apt install gitleaks` · `winget install gitleaks` |
| [GitHub CLI (`gh`)](https://cli.github.com) | facultatif | tickets et gestion du dépôt GitHub : `gh auth login -s workflow` (le scope `workflow` autorise la modification de `.github/workflows/`) |
