# Limites

- **Création de branche** : Git n'a pas de hook à ce moment-là ; le nom est vérifié au premier commit et au push. Pour l'imposer côté serveur : [règles côté serveur](ci.md#regles-cote-serveur).
- **Hooks locaux contournables** (`--no-verify`) et à installer sur chaque poste : la CI et la protection des branches font foi.
- **`core.hooksPath` local** (husky…) prioritaire sur l'installation globale : lancer `install.sh` dans le dépôt ou laisser l'outil existant gérer.
- **Projet [pre-commit](https://pre-commit.com)** avec l'installation globale : `pre-commit install` refuse (« Cowardly refusing to install hooks with `core.hooksPath` set ») et l'astuce qu'il propose désactive repowarden partout. Installer ses hooks dans `.git/hooks`, que repowarden lance à chaque commit avant ses propres vérifications (un hook pre-commit en échec bloque le commit) :

    ```bash
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0= pre-commit install
    ```

    La configuration git n'est pas modifiée : `core.hooksPath` est seulement masqué pour cette commande. Avant git 2.31 : `git config --local core.hooksPath ""`, puis `pre-commit install`, puis `git config --local --unset core.hooksPath`. `repowarden statut` signale un `.pre-commit-config.yaml` dont les hooks ne sont pas installés.
- **Chevauchement** : si le formatage et des modifications non stagées touchent les mêmes lignes, le commit est formaté mais le dossier de travail reste dans son état d'origine.
- **Langage non listé** : le décrire dans [la configuration](configuration.md) (`format`, `test`) ou [ajouter un fichier de langage](technologies.md#ajouter-un-langage).
- **Fichiers isolés** (hors projet) : formatés, mais sans tests.
- **`pre-push` hors de la branche courante** : tests dans un worktree temporaire, où seul `node_modules` est relié.
- **Premier lancement** sur Helm, Kubernetes ou Terraform : téléchargement des schémas et providers, ensuite en cache.
- **Dossier repowarden déplacé ou renommé** : Git ignore *sans aucun message* un `core.hooksPath` qui n'existe plus, et les hooks cessent de tourner. Relancer `install.sh` (avec `--global` si besoin) depuis le nouvel emplacement ; vérifier avec `git config --show-origin --get-all core.hooksPath` (un réglage local du dépôt l'emporte sur le global).

