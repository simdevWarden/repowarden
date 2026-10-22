# Pourquoi repowarden ?

repowarden n'est pas un linter de plus. Les vérifications qu'il applique
existent déjà, souvent mieux faites, dans des outils spécialisés : commitlint
pour les messages, gitleaks pour les secrets, ruff ou prettier pour le
formatage, release-please pour les versions, les règles de protection de
GitHub pour le serveur. **repowarden les orchestre** et y ajoute ce qu'aucun de
ces outils ne fait seul : une chaîne **ticket → conception → PR → livraison**
imposée, y compris aux agents IA.

Cette page dit aussi quand un autre outil suffit. C'est le cas dès que le
besoin se limite à une vérification.

## Qui couvre quoi

| Outil | Ce qu'il couvre | Configuration par projet | Ce qui manque |
|---|---|---|---|
| **husky + commitlint** | Orchestration de hooks Git ; format des messages de commit (commitlint). | `package.json`, `.husky/`, `commitlint.config.*` | Nom de branche, secrets, formatage, tests au push, code mort, releases, tickets, garde-fou d'agent : à écrire soi-même dans les hooks. |
| **pre-commit** | Framework de hooks multi-langages ; plugins pour le message (`conventional-pre-commit`), les secrets (gitleaks), le formatage (ruff, prettier…), l'interdiction de commiter sur `main` (`no-commit-to-branch`), les tests au push (hook local). | `.pre-commit-config.yaml` | Nommage des branches, tickets, releases, garde-fou d'agent ; la CI et la protection serveur restent à câbler ; les environnements de hooks sont propres à chaque dépôt. |
| **lefthook** | Exécution rapide et parallèle de hooks Git, sur les mêmes événements que les hooks natifs. | `lefthook.yml` | Aucun contrôle fourni : tout est une commande à écrire (message, secrets, format, tests…). Ni tickets, ni releases, ni agents. |
| **gitleaks** | Détection de secrets dans l'historique, l'index ou une plage de commits. | `.gitleaks.toml`, intégration CI | Tout le reste : message, branche, format, tests, code mort, releases, tickets, agents. |
| **release-please** | Version suivante, changelog, tag et release à partir des Conventional Commits. | `release-please-config.json`, `.release-please-manifest.json`, workflow | Il **suppose** les messages conventionnels mais ne les impose pas ; aucun hook, aucune vérification de branche, de secret, de format ou de test ; pas de tickets ni d'agents. |
| **Protection de branches GitHub (rulesets)** | Côté serveur : PR obligatoire, checks requis, merge bloqué si la CI échoue, pas de push direct, pas de force push ni de suppression sur les branches protégées. | Réglages GitHub (rulesets), `CODEOWNERS` | Ne vérifie rien lui-même : il faut la CI, les hooks et les contrôles. Pas de retour local, pas de nommage de branches, pas de tickets, pas de garde-fou avant l'action d'un agent. |
| **Danger** | Règles de revue de PR en CI : titre et description, labels, changelog, mention d'un ticket, commentaires automatiques. | `Dangerfile` | Hooks Git, secrets, formatage, tests au push, releases ; le garde-fou d'agent. Danger observe la PR, il n'empêche pas le travail en amont. |
| **repowarden** | La chaîne complète : message, nom de branche, branche protégée, secrets, fichier `.env` non ignoré, formatage, tests au push, code mort nouveau, fonctions sans commentaire, releases, tickets, garde-fou des agents IA ; mêmes règles sur le poste, en CI et côté serveur. | `.repowarden.conf`, workflows `repowarden.yml`, `release.yml`, `tickets.yml`, `nettoyage.yml` | Il ne remplace ni les linters ni les formateurs : il les appelle. Tickets et releases sont orientés GitHub ; le garde-fou d'agent n'agit que si l'agent est branché ; les hooks locaux restent contournables (`--no-verify`), la CI fait foi. |

## Quand un autre outil suffit

- **Seul le format des messages** : commitlint (ou `conventional-pre-commit`).
  Pas besoin de tickets, de releases ni d'agents pour cela.
- **Seules les releases** : release-please, avec un workflow et ses deux
  fichiers JSON.
- **Seule la protection serveur** : les rulesets GitHub. Ils bloquent le merge
  et le push direct sans rien installer sur les postes.
- **Seule la détection de secrets** : gitleaks, dans un hook pre-commit et en
  CI. C'est d'ailleurs ce que repowarden appelle.
- **Un seul langage, peu de règles** : pre-commit avec trois ou quatre plugins
  couvre le message, les secrets, le format et les tests au push. La valeur
  ajoutée de repowarden commence au-delà : nommage des branches, tickets,
  unification poste/CI/serveur, agents.
- **Pas de tickets, pas d'agents IA, une équipe qui connaît ses outils** : la
  différence se réduit à l'orchestration. Si pre-commit, release-please,
  gitleaks, Danger et les rulesets donnent déjà satisfaction, repowarden
  remplace surtout de la glue ; le coût de migration n'est pas toujours payé.

## Ce qui est propre à repowarden

1. **La chaîne imposée, pas seulement des contrôles.** Un ticket validé, une
   conception écrite, une branche `type/<n>-sujet`, une PR qui cite le ticket,
   une livraison qui ferme le ticket : chaque maillon est vérifié, et la CI
   refuse la PR qui en manque un. Voir [Tickets](tickets.md) et
   [Validation humaine](validation.md).
2. **Le garde-fou des agents IA.** Claude Code et opencode sont arrêtés
   **avant** l'action : modifier une branche protégée, travailler hors ticket,
   `git commit` sans `repowarden cc`, `--no-verify`, `git add .`, force push.
   Les hooks ne voient l'agent qu'au commit ; la CI qu'à la PR. Voir
   [Agents IA](agents.md).
3. **L'orchestration d'outils existants.** repowarden appelle gitleaks,
   actionlint, ruff, MegaLinter, les formateurs et les tests du projet ; il ne
   réécrit pas un linter. Un outil absent avertit sur le poste et devient
   bloquant en CI stricte ([CI](ci.md)).
4. **Les mêmes règles aux trois niveaux.** Un `.repowarden.conf` pour le poste
   et la CI, la protection serveur pour ce qui ne doit pas être contourné.
   Voir [En organisation](industrialisation.md).
5. **Les releases sans jeton.** La GitHub App publie la préversion, tient à
   jour la PR de livraison et la merge quand les checks sont verts, avec
   approbation humaine si le projet le demande ([Versions et releases](releases.md)).
   release-please fait les versions ; repowarden y ajoute la livraison et le
   suivi des tickets.

## La preuve, chiffres en main

La mesure est reproductible : [`ci/preuve.sh`](https://github.com/simdevWarden/repowarden/blob/develop/ci/preuve.sh)
part de [repowarden-demo](https://github.com/simdevWarden/repowarden-demo/tree/83b6099c935a24b5aec56645c7a28d71dc80253b)
(commit `83b6099`, 17 octobre 2026) et monte deux copies du même projet Python :

- **assemblage classique** : pre-commit (`conventional-pre-commit`, gitleaks,
  ruff, `no-commit-to-branch`, pytest en `pre-push`), release-please et un
  workflow de CI ;
- **repowarden** : le `.repowarden.conf` et les workflows des modèles publiés
  (`repowarden.yml`, `release.yml`, `tickets.yml`, `nettoyage.yml`).

Les outils sont installés dans un dossier temporaire, jamais globalement.
Mesure faite le **22 octobre 2026** sur **Darwin arm64** (macOS), avec
**pre-commit 4.7.0**, **repowarden 4.11.1**, **ruff 0.16.10**,
**gitleaks 8.30.1**, **Python 3.14.6**, **Node 26.9.0** ; temps d'installation
en médiane de 3 passages, avec un cache de paquets propre à chaque passage.

### Configuration par projet

| Assemblage | Fichiers | Lignes | Lignes utiles (hors vides et commentaires) |
|---|---|---|---|
| Assemblage classique | 5 | 70 | 69 |
| repowarden | 5 | 181 | 108 |

repowarden demande **plus de lignes** : ses workflows `release`, `tickets` et
`nettoyage` n'ont pas d'équivalent dans l'assemblage classique, et les modèles
sont commentés. À périmètre strictement égal (message, secrets, format,
branche protégée, tests), l'écart se réduit.

### Temps d'installation d'un poste

| Assemblage | Médiane (s) | Versions |
|---|---|---|
| pre-commit + câblage d'un dépôt | 10,5 | pre-commit 4.7.0 |
| repowarden (npm) + hooks globaux | 1,3 | repowarden 4.11.1 |

Le temps classique comprend la création d'un environnement Python neuf,
l'installation de pre-commit et le câblage d'**un** dépôt (`pre-commit install`) ;
repowarden installe le paquet npm et active les hooks pour **tous** les dépôts.
Le réseau fait varier les deux chiffres de quelques secondes. Sur une machine
où Python et pre-commit sont déjà installés, le coût incrémental par dépôt est
plus faible ; l'écart mesure surtout la mise en place initiale.

### Le même jeu de commits fautifs

Chaque scénario est rejoué sur une copie neuve. « Bloqué » = le commit ou le
push échoue ; « averti » = il passe avec un avertissement ; « passé » = rien ne
le signale.

| Scénario | Assemblage classique | repowarden |
|---|---|---|
| Message non conforme | bloqué | bloqué |
| Commit direct sur `main` | bloqué | bloqué |
| Mauvais nom de branche | passé | bloqué |
| Secret dans un fichier stagé | bloqué | bloqué |
| `.env` ni suivi ni ignoré | passé | averti |
| Fichier mal formaté | bloqué (correction à re-stager) | passé (corrigé) |
| Test cassé au push | bloqué | bloqué |
| Message invalide découvert au push | passé | bloqué |
| Fonction ajoutée sans commentaire | passé | averti |
| Force push demandé par un agent | passé (aucun garde-fou) | bloqué |

### Comment lire ces résultats

- **Ce que les deux font aussi bien** : message conventionnel, secret,
  interdiction de commiter sur `main`, test cassé au push. Aucune surprise :
  repowarden appelle les mêmes outils, ou applique la même règle.
- **Le nom de branche** n'est pas vérifié par `no-commit-to-branch`, qui ne
  protège que les branches nommées ; il faut un script ou repowarden.
- **Le `.env` non ignoré** passe silencieusement dans l'assemblage classique.
  repowarden avertit sans bloquer : le fichier n'est ni suivi ni lu, mais un
  `git add .` le publierait.
- **Le formatage** : ruff corrige dans les deux cas. pre-commit s'arrête pour
  demander de re-stager ; repowarden re-stage le contenu corrigé et le commit
  passe en une fois.
- **Le message créé hors hooks** (autre outil, rebase, `--no-verify`) est vu
  par repowarden au push ; l'assemblage classique ne le revoit pas.
- **La fonction sans commentaire** est un avertissement propre à repowarden.
- **Le force push** : les rulesets GitHub bloquent le force push sur une
  branche **protégée**, côté serveur. Le scénario porte sur une branche de
  travail ; seul repowarden refuse la commande avant qu'elle parte.
- **Le secret classique** dépend d'une ligne de configuration :
  `gitleaks-system` du dépôt gitleaks n'a pas `pass_filenames: false`. Sans
  elle, pre-commit passe les noms de fichiers à gitleaks, qui sort 0 sans rien
  scanner. La mesure ajoute la ligne ; c'est un bon exemple de la fragilité
  d'un assemblage fait de pièces séparées.

### Limites de la mesure

- Un seul projet, en Python, sur macOS arm64. Les temps et les outils changent
  avec le langage, l'OS et le réseau.
- L'assemblage classique est **minimal et correctement configuré**, pas
  volontairement mauvais. Une équipe peut ajouter Danger, un bot de tickets et
  des règles de nommage : la couverture se rapproche, au prix de davantage de
  glue.
- Les règles serveur (rulesets) ne sont pas rejouées : elles ne s'appliquent
  qu'à un vrai dépôt GitHub. La colonne classique ne les inclut donc pas.
- Le test hors ligne [`test/preuve.bats`](https://github.com/simdevWarden/repowarden/blob/develop/test/preuve.bats)
  vérifie la colonne repowarden avec les hooks du dépôt, sans réseau ; il ne
  rejoue pas l'assemblage classique.

Pour refaire la mesure (réseau nécessaire) :

```bash
ci/preuve.sh
```

Le script affiche les tableaux ci-dessus en Markdown. `ci/preuve.sh --liste`
donne les scénarios ; `ci/preuve.sh --scenario <id>` en rejoue un seul, hors
ligne, avec les hooks du dépôt.
