# Tickets

Chaque changement part d'un **ticket** (issue GitHub) : **la branche découle du ticket**, et chaque étape de la vie du ticket fait avancer la branche et la PR, de l'idée à la production, sans suivi manuel.

## Le cycle d'un ticket

| Statut (étiquette) | Quand | Effet automatique |
|---|---|---|
| `statut: à valider` | ticket créé (à la main, ou `repowarden ticket nouveau`) | — |
| `statut: backlog` | un mainteneur pose l'étiquette **`validé`**, ou ouvre lui-même le ticket (validé d'office) | ticket prêt à être pris ; commentaire avec la commande pour le prendre |
| `statut: en cours` | quelqu'un s'assigne le ticket (ou `repowarden ticket N`), ou pousse un premier commit sur sa branche | à l'assignation : **branche `<type>/<n°>-<titre>` créée** depuis `develop` et **liée au ticket** (panneau *Development*), un ticket validé pour plus tard n'a donc pas de branche qui vieillit ; au premier push : **PR en brouillon** ouverte vers `develop`, titrée par l'**en-tête du premier commit** de la branche, `(#n)` final retiré (il devient le commit de squash ; s'il n'est pas conforme : titre du ticket, portée tirée de son préfixe, sigles gardés, aucun mot coupé), à la **description reprise du ticket** (critères en cases à cocher, commentaires de mainteneur titrés « Ajout » ou « Constat lié », résumé de la « Conception retenue » : ce qui change et hors périmètre, liste des commits, `Ticket : #n`), assignée à l'auteur du push (si c'est un bot, à l'assigné du ticket, sinon à personne ; un refus de GitHub n'est qu'un avertissement) ; **actualisée à chaque push** tant qu'elle est en brouillon, une section `## Réalisé` écrite à la main y étant gardée telle quelle |
| `statut: en relecture` | PR « Ready for review » | la CI tourne ; une revue « Request changes » ramène le ticket en cours |
| `statut: préprod` | PR mergée dans `develop` | branche supprimée ; commentaire à chaque préversion `vX.Y.Z-next.N` |
| `statut: done` | release sur `main`, ou livraison sans nouvelle version (ni `fix` ni `feat`) | ticket **fermé**, avec la version (ou « sans nouvelle version » et le commit livré) |

Un ticket **livré** (`préprod`, `done`) ne recule jamais : un événement de PR traité en retard (PR éditée après son merge), une branche réapparue ou une réassignation ne le ramènent pas en cours ou en relecture ; le suivi le signale par une notice.

**Une seule PR par branche** : les runs `push` d'une même branche passent l'un après l'autre (groupe de `concurrency` propre au dépôt et à la branche, le run en cours n'est jamais annulé), et la PR ouverte est recherchée à nouveau juste avant d'en créer une : deux push rapprochés n'ouvrent qu'une PR.

Ticket fermé comme **abandonné** (*not planned*) : sa PR est fermée et sa branche supprimée.

Ticket **terminé** (passé en `done` à la release, ou fermé à la main) dont la branche existe encore, parce que le travail est passé par une autre branche : elle est supprimée si elle n'a aucun commit absent de `develop` et qu'aucune PR ouverte n'en part. Sinon elle est gardée et le ticket le signale : rien n'est jamais perdu.

Tout est automatique, sauf la validation : c'est la seule décision humaine, et GitHub ne laisse poser l'étiquette `validé` qu'aux personnes ayant les droits sur le dépôt. Un ticket **ouvert par un mainteneur** (droits d'écriture : propriétaire, membre, collaborateur) est **validé d'office** : l'ouvrir est déjà sa décision ; chaque événement du ticket (étiquette, assignation) rattrape cette validation si le run de l'ouverture a été annulé. Seuls les tickets de la communauté attendent l'étiquette. Pour **proposer** un ticket sans le valider (idée, retour de test, ticket ouvert par un outil ou un agent avec le compte d'un mainteneur), poser l'étiquette **`à décider`** à l'ouverture : il reste « à valider », sans branche, jusqu'à ce qu'un mainteneur pose `validé` (`à décider` est alors retirée). Pour une validation toujours séparée : entrée `auto-validate: never` du workflow `tickets.yml`. Le type de la branche vient de l'étiquette `type: …` du ticket (`feat` par défaut), son nom du titre (minuscules, sans accents).

## Sur le poste

```bash
repowarden ticket 12                          # se place sur la branche du ticket #12
repowarden ticket nouveau "Ajoute le panier"   # crée un ticket (à valider)
repowarden ticket                             # ticket de la branche courante
```

- `repowarden ticket <n>` **prend le ticket** (assigné à soi) et se place sur sa branche ; la crée et la lie au ticket (`gh issue develop`) si elle n'existe pas encore.
- `repowarden ticket nouveau --type <type>` : type parmi `feat`, `fix`, `docs`, `refactor`, `chore` (les étiquettes `type: …`) : si le suivi est géré par repowarden, un autre est refusé, avant toute création.
- **Tickets assignés → branches locales** : `repowarden tickets sync` crée la branche locale de chaque ticket qui t'est assigné, sans changer ta branche courante. Un ticket réassigné à quelqu'un d'autre est signalé, sa branche locale conservée. Jamais pour un ticket livré (`préprod`, `done`) ou en relecture dont la branche a disparu (PR mergée). Réglage `ticketSync = manual | auto | off` : par défaut `manual`, un `git pull` ou un clonage ne touche à rien ; avec `git config repowarden.ticketSync auto`, la synchronisation se fait aussi à chaque `git pull` ou changement de branche (au plus toutes les 15 min, seulement avec `gh` connecté), jamais au clonage.
- **Branche sans ticket** : `repowarden` prévient (à l'arrivée sur la branche et dans `git cc`), **sans jamais bloquer** : tout le monde ne travaille pas avec des tickets. Si le projet fait gérer ses tickets par repowarden, il **propose d'en créer un** (`git cc` le crée et le cite sur un « oui ») ; sinon, il indique comment ne plus le voir : `git config repowarden.skip tickets`.
- `git cc` cite `Ticket : #12` sur une branche `feat/12-…`.

## Les règles

- **Merge automatique vers `develop`** : une PR de travail **prête** (sortie du brouillon), dont le ticket est validé, se merge **seule en squash** dès que ses vérifications sont vertes. Repassée en brouillon, le merge automatique est retiré. Il demande la [GitHub App](industrialisation.md#github-app-des-workflows) : avec le jeton des Actions, le merge ne déclencherait aucun workflow. La livraison `develop` → `main` n'est **jamais** mergée automatiquement : elle attend toujours l'approbation humaine. Réglage `autoMergeWork = false` (`.repowarden.conf`) pour garder des merges manuels.
- **Pas de PR sans ticket** : une PR cite son ticket dans sa description (`Ticket : #12`), ou sa branche le porte (`feat/12-panier`). Sinon, le ticket est **créé automatiquement** à partir de la PR, relié à sa description, et « à valider ».
- **Contrôles de la vérification `ticket`** (pour tout contributeur, agent ou personne) : la PR ne cite **qu'un seul ticket** ; sa branche porte le **numéro du ticket** (`type/12-sujet`) ; le ticket porte une **« Conception retenue »** écrite par un mainteneur avant le code (entrée `require-design` du workflow) ; aucun commit ne cite un autre ticket.
- **Pas de merge sans ticket validé** : la vérification `ticket` de la PR échoue tant que son ticket n'a pas l'étiquette `validé`. Elle passe dès que l'étiquette est posée, sans rien relancer. Le job `tickets` reste vert pendant l'attente : un job rouge signale une vraie panne.
- **Un ticket, une branche, et le ticket s'en souvient** : la branche créée par le ticket lui est liée (panneau *Development*). GitHub ne sait lier une branche qu'à sa création, et une branche liée supprimée y perd son nom : le bot **inscrit donc le nom de la branche sur le ticket** (commentaire « Branche du ticket »), à sa création comme au premier push d'une branche `type/12-…` faite à la main. Une seconde branche pour le même ticket est inscrite et signalée. Une branche faite au nom du ticket **avant sa validation** n'est jamais recréée : GitHub ne lie pas une branche existante (*Development* reste vide), le bot (à la validation) ou `repowarden ticket N` inscrit donc son lien sur le ticket.
- **`main` et `develop` ne sont jamais rouges** : GitHub accroche les vérifications d'une PR au commit de sa branche source. Une PR ne part de `develop` que pour livrer (`develop` → `main`), et de `main` que pour un retour utile (`main` → `develop`). Toute autre PR qui en part est sans objet : la CI la signale sans échouer, et elle est fermée avec la marche à suivre (pour mettre une branche de travail à jour : `git merge origin/develop` sur cette branche).
- Les bots de dépendances, les PR de release et les livraisons `develop` → `main` n'ont pas besoin de ticket.
- La PR en brouillon est ouverte par le jeton des Actions, qui ne déclenche pas d'autre workflow : la CI tourne au push suivant, ou au passage « Ready for review » (`ready_for_review` dans les déclencheurs de la CI, comme dans le modèle de projet).

!!! note "Pourquoi `Ticket : #12` et pas `Closes #12`"
    `Closes #12` ferme le ticket dès le merge dans la branche par défaut, c'est-à-dire `develop` : il serait « done » avant d'être en production. Ici, c'est la release sur `main` qui le ferme.

## Mise en place

```bash
repowarden tickets init          # étiquettes, modèle, workflow, tickets et branches existants
git add .github && git cc       # puis PR
repowarden proteger --checks "repowarden,ticket"   # vérification « ticket » exigée
```

Sur un dépôt qui a déjà des tickets, `tickets init` les reprend (relançable, rien n'est fait deux fois) :

- tickets ouverts **sans statut** : ceux qui portent `validé` ou ont été ouverts par un mainteneur passent en **backlog**, les autres **à valider** (`--sans-validation-auto` : tous à valider) ;
- **branches des PR** ouvertes et mergées : inscrites sur les tickets qu'elles citent, pour savoir quel ticket a géré quelle branche, même supprimée ;
- aucune branche créée en masse : elle naît quand le ticket est pris (`repowarden ticket N`).

Dans `.github/workflows/release.yml`, les tickets passent en préprod à chaque préversion et en done à chaque release, ou à une livraison sur `main` sans nouvelle version (job écrit par `repowarden bots` avec le suivi des tickets, avec l'App si elle est configurée ; à ajouter à la main dans un `release.yml` existant) :

```yaml
  tickets:
    needs: release
    if: needs.release.outputs.release_created == 'true' || needs.release.outputs.prerelease_created == 'true' || needs.release.outputs.delivered_without_version != ''
    uses: simdevWarden/repowarden/.github/workflows/tickets.yml@v4
    permissions: { contents: write, issues: write, pull-requests: write, statuses: write }
    with:
      tag: ${{ needs.release.outputs.tag_name || needs.release.outputs.prerelease_tag }}
      delivered-sha: ${{ needs.release.outputs.delivered_without_version }}
```

Un `tickets.yml` existant n'est jamais écrasé : pour la branche créée à la validation et la PR en brouillon, y ajouter les événements `pull_request_review`, `issues` (`assigned`, `closed`), `push`, et la permission `contents: write` (voir le modèle écrit par `repowarden tickets init`).

Aucune clé ni jeton : tout passe par le jeton des Actions. Le workflow utilise `pull_request_target` sans jamais récupérer le code de la PR : les PR venant de forks sont traitées en sécurité.

Livraison ouverte par le workflow de release (`release-auto`) : avec `delivery-workflow: true`, une PR `develop` → `main` ouverte à la main est fermée, avec la marche à suivre ; elle n'aurait jamais d'approbation de déploiement. Défaut `false` : une livraison par PR manuelle reste possible.

## Tableau

Les statuts sont des étiquettes : un [GitHub Project](https://docs.github.com/fr/issues/planning-and-tracking-with-projects) en vue tableau, groupé par étiquette (ou avec une colonne filtrée par statut), donne le tableau backlog → done. Il se règle une fois, dans l'interface de GitHub ; le workflow n'y touche pas (les Projects d'un compte personnel ne sont pas accessibles au jeton des Actions).
