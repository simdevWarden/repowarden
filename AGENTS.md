# Consignes pour les agents (et toute personne qui reprend le projet)

Ce fichier est la source des règles de travail sur repowarden. Il est court :
le détail est dans la doc, voir « Où trouver le reste ».

## Processus

1. **Tout part d'un ticket** (issue GitHub). Pas de modification sans ticket :
   tout changement, y compris un réglage GitHub, part d'un ticket créé avant.
2. **La conception est écrite dans le ticket avant le code** : ce qui change,
   fichiers touchés, hors périmètre (commentaire « Conception retenue »). Un
   écart en cours de route est d'abord noté sur le ticket.
3. **Prendre le ticket** (`repowarden ticket <n>`, qui l'assigne) : sa branche
   `type/<n>-sujet` est créée depuis `develop` et liée au ticket.
4. **Premier push** : la PR brouillon vers `develop` s'ouvre seule
   (`Ticket : #<n>` dans sa description, jamais `Closes #<n>`). Sortie du
   brouillon, elle se merge **seule en squash** quand la CI est verte.
5. **Seul `develop` entre dans `main`**, par la PR de livraison, **toujours
   avec une approbation humaine**. Le ticket est fermé à la release.
6. **Ces règles sont des contrôles** : la vérification `ticket` (exigée) refuse une PR sans conception écrite sur son ticket, qui cite plusieurs tickets, dont la branche ne porte pas le numéro du ticket, ou dont un commit cite un autre ticket.
7. **Un défaut, un ticket** : un défaut découvert devient un ticket ; s'il est
   lié à un ticket ouvert, il y est noté en « Ajout ». Le **gel** de la
   création de tickets est une décision du mainteneur, notée ici avec sa date
   et sa condition de levée ; seul le mainteneur le lève, en mettant cette
   ligne à jour. Pendant un gel, un défaut est noté sur le ticket existant le
   plus proche. État : **pas de gel** (levé le 21/10/2026 par le mainteneur).

## Commandes

```bash
repowarden ticket <n>                    # prendre un ticket, se placer sur sa branche
repowarden cc --dry-run -m "<description>" --type <type> --scope <portée> \
    --body "<pourquoi>" --refs "Ticket : #<n>"   # aperçu du message
repowarden cc -m "…" --type … --scope … --body "…" --refs "Ticket : #<n>"   # commit
```

- Messages en **français**, en-tête ≤ 72 caractères, **sans signature ni
  co-auteur d'agent**. Utiliser `repowarden cc` (paquet installé), pas un alias
  local ni `git commit -m`.
- **Toute nouvelle fonction** a, juste au-dessus, une à deux lignes qui disent
  ce qu'elle fait et **pourquoi**, sans paraphraser le code (pas de gros bloc).
  Le pre-commit et la CI signalent une fonction ajoutée sans commentaire.
- Avant chaque push, les mêmes vérifications que la CI :

```bash
shellcheck bin/* ci/*.sh ci/tickets/*.sh hooks/pre-commit hooks/prepare-commit-msg hooks/commit-msg hooks/pre-push hooks/post-checkout hooks/post-merge hooks/lib/*.sh hooks/lib/i18n/*.sh hooks/lang/*.sh install.sh
actionlint .github/workflows/*.yml
bats test/
```

- Shell compatible **bash 3.2** (macOS) : lancer aussi les tests touchés avec
  `/bin/bash` en tête du `PATH`. Un tableau vide sous `set -u` s'écrit
  `${t[@]+"${t[@]}"}`. Dans un test bats, une condition s'écrit
  `[[ … ]] || false` : sinon son échec n'arrête pas le test sous bash 3.2.
- Un nouveau test : vérifier qu'il **échoue sans le changement**.

## Interdits

- Push direct sur `main` ou `develop`, force push, amend d'un commit poussé.
- PR qui part de `main` ou de `develop`, sauf la livraison `develop` → `main`
  (le bot ferme les autres).
- Contourner une règle (`--admin`, exception de ruleset, `--no-verify`).
- Afficher, journaliser ou versionner un secret, un jeton ou une clé.

## Pièges connus

- **« Approve » dans l'interface GitHub** : peut partir en simple
  commentaire ; vérifier que la revue est bien « Approved »
  (`gh pr review <n> --approve`).
- **Bandeau « main had recent pushes — Compare & pull request »** après une
  livraison : à ignorer, aucun retour `main` → `develop` n'est nécessaire.
- **GitHub ferme un ticket lié au merge dans `develop`** : le suivi le rouvre
  en préprod ; c'est la release qui le ferme.
- **Jeton des Actions** : ce qu'il fait ne déclenche aucun autre workflow ;
  les automatismes passent par la GitHub App (`repowarden app init`).

## Où trouver le reste

- Contribuer (mise en place, conventions, ajouter un langage) : [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Tickets : [`docs/tickets.md`](docs/tickets.md)
- Versions et livraisons : [`docs/releases.md`](docs/releases.md)
- CI et vérifications : [`docs/ci.md`](docs/ci.md)
- Protection, GitHub App, industrialisation : [`docs/industrialisation.md`](docs/industrialisation.md)
