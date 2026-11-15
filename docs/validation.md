# Validation humaine

repowarden automatise ce qui est **mécanique et vérifiable** :
- formater ;
- vérifier un message, un nom de branche ou une cible de PR ;
- calculer une version, écrire un changelog, poser un tag ;
- construire et signer un paquet.

Ces actions donnent toujours le même résultat pour la même entrée, et chacune est tracée (logs de CI, attestations de provenance).

Ce qui demande du **jugement** reste humain :
- ce code fait-il ce qu'on veut ?
- est-ce le moment de livrer ?
- peut-on publier ?

Le risque n'est pas la machine. C'est une validation humaine trop légère. Cette page décrit comment la rendre obligatoire.

## Les points de décision

| Décision | Mécanisme GitHub | repowarden |
|---|---|---|
| Relire le code avant qu'il n'entre | approbations obligatoires ; approbation annulée par un nouveau commit ; le dernier à pousser ne peut pas approuver son propre push (sauf dépôt solo : une seule personne avec l'écriture, aucune règle n'exige une autre personne) | `repowarden proteger --relecteurs N` |
| Faire relire les zones sensibles par leurs responsables | fichier `CODEOWNERS` + revue du propriétaire obligatoire | `repowarden proteger --codeowners` |
| Décider de publier | environnement de déploiement : le job attend l'approbation d'une personne désignée | `repowarden proteger --environnement production` |
| Décider de livrer (flux `develop`) | un clic **« Approve and deploy »** sur l'environnement `production` (notification, application mobile, page du run) ; la GitHub App merge alors la PR de livraison `develop` → `main`. `main` exige ce déploiement réussi : rien n'y entre sans cette approbation. **Ou, au choix du projet, livraison automatique** : la validation humaine est le merge de chaque ticket ; la GitHub App merge la livraison dès que les vérifications exigées sur `main` sont vertes ([comparaison des deux modes](releases.md#livraison-approuvee-ou-automatique)) | mode `tag`, `deliveryApproval = deployment` (défaut ; `review` : revue de PR à la place ; `auto` : livraison automatique, entrée `delivery-auto: true`) |
| Garder la main sur la PR de release (mode `pr`) | merge humain | `release-auto` avec `merge-auto: false` |

Avec une relecture exigée, la PR de release n'est jamais mergée par le bot. Il la prépare et la fait valider par la CI, puis elle attend une approbation humaine. Son merge publie la release.

## Mise en place

Réglages versionnés dans `.repowarden.conf`, appliqués par `repowarden proteger` (relançable) :

```ini
[repowarden]
    requiredReviews = 1              # approbations par PR
    codeOwnerReview = true           # revue des CODEOWNERS sur leurs fichiers
    unattributedApproval = false     # approbation en plus pour les changements non attribués (défaut false)
    deliveryApproval = deployment    # livraison validée par « Approve and deploy » (review : revue de PR ; auto : automatique)
    environment = production         # déploiements soumis à approbation
    environmentReviewers = alice @acme/release  # comptes ou équipes ; défaut : l'utilisateur gh courant
```

`unattributedApproval` vaut `false` par défaut et `proteger` le pose toujours explicitement. Sans cela, GitHub l'active d'office : une PR ouverte par une application (PR de livraison, PR brouillon d'un ticket, ouvertes par le jeton des Actions) attendrait alors une approbation humaine, même sans approbation exigée. La validation humaine d'une livraison passe déjà par `requiredReviews` sur `main`.

```text title=".github/CODEOWNERS"
# Un motif par ligne ; la dernière règle qui correspond l'emporte
*                  @equipe-dev
# Workflows et protection
/.github/          @equipe-plateforme
# Build et dépendances
/pom.xml           @equipe-plateforme
/package.json      @equipe-plateforme
/src/**/security/  @equipe-securite
```

Puis, dans les workflows, chaque job de publication déclare l'environnement :

```yaml
  publier:
    needs: release
    if: needs.release.outputs.release_created == 'true'
    environment: production   # attend l'approbation avant de s'exécuter
```

L'environnement n'accepte de déploiement que depuis les branches protégées et les tags `v*` : une branche de travail ne peut pas publier.

## Où cliquer

Tout le reste est automatique. Voici chaque geste humain du cycle, avec le bouton GitHub et la commande équivalente.

| Geste | Quand | Où | Commande |
|---|---|---|---|
| Valider un ticket | ticket ouvert par quelqu'un d'autre qu'un mainteneur | ticket → *Labels* → `validé` (posé d'office si un mainteneur ouvre le ticket) | `gh issue edit N --add-label validé` |
| Écrire la conception | avant le code | commentaire d'un mainteneur sur le ticket contenant « Conception retenue » | `gh issue comment N --body-file conception.md` |
| Sortir la PR du brouillon | travail terminé | bas de la PR → **Ready for review** ; elle se merge seule (squash) quand la CI est verte | `gh pr ready N` |
| Approuver une relecture | si `requiredReviews ≥ 1` | PR → *Files changed* → **Review changes** → *Approve* → **Submit review** | `gh pr review N --approve` |
| Livrer en production | flux `develop`, chaque livraison | **Approve and deploy**, voir ci-dessous | voir ci-dessous |
| Livrer un correctif urgent | sans attendre la fenêtre | étiquette `urgent` (à créer si absente) sur la PR `fix/…` avant son merge | `gh pr edit N --add-label urgent` |
| Merger la PR de release | mode `pr` avec `merge-auto: false` | PR « release x.y.z » → **Merge pull request** | `gh pr merge N --merge` |

### Approve and deploy, pas à pas

1. **La demande existe-t-elle ?** Elle est créée par le workflow `release` : chaque vendredi à 7 h (`delivery-schedule`), au merge d'une PR `urgent`, ou à la main :
   *Actions → release → **Run workflow** → branche `develop`*, ou `gh workflow run release.yml --ref develop`.
2. **Trouver le bouton** (environ une minute après, quand le job `release / livraison` est *Waiting*) :
   - page du run (*Actions* → run **release** le plus récent) : bandeau jaune « *production needs approval* » → **Review deployments** → cocher `production` → **Approve and deploy** ;
   - ou la notification GitHub (cloche, mail « Deployment review requested », application mobile).
3. La GitHub App merge alors la PR de livraison dès que les vérifications sont vertes ; tag et release suivent.

### Pièges

- **PR de livraison ouverte à la main** (`develop` → `main`) : elle reste bloquée sur « *Missing successful active production deployment* », car aucune demande d'approbation n'est créée pour elle. Lancer le workflow `release` (étape 1) : il ouvre sa propre PR, figée sur `livraison/vX.Y.Z`, et ferme l'autre.
- **« Approve » sur la PR de livraison** (*Review changes*) : c'est une relecture de code, elle ne débloque rien. Seul **Approve and deploy**, sur la page du run, crée le déploiement exigé.
- **Une approbation vaut pour un commit** : un merge dans `develop` après l'approbation part à la livraison suivante, avec sa propre approbation.
- **« Awaiting requested review »** sur une PR de livraison : simple demande de relecture, elle ne bloque pas le merge si aucune approbation n'est exigée.
- **Demande en attente oubliée** : une nouvelle demande (manuelle ou planifiée) la remplace ; inutile de l'approuver, elle porte un état périmé.

## Projet solo

GitHub interdit d'approuver sa propre PR, et `repowarden proteger` n'accorde **aucune exception**, pas même à l'administrateur : avec `requiredReviews = 1` et un seul développeur, aucun merge ne serait possible. Pour un projet solo, le réglage conseillé :
- `requiredReviews = 0` : la CI fait foi sur la forme ;
- `environment = production` avec soi-même comme approbateur : chaque publication demande un clic délibéré ;
- pas de `.github/CODEOWNERS` à une seule personne : sans `codeOwnerReview`, il ne fait que demander sa relecture sur chaque PR, sans rien exiger.

## Qui est prévenu

Les destinataires se désignent par **compte ou équipe GitHub**, jamais par adresse mail : un dépôt public exposerait les adresses, et l'historique Git les garderait pour toujours. GitHub prévient ensuite chacun selon ses préférences (mail, mobile, web).

| Qui | Où | Exemple |
|---|---|---|
| Relecteurs, par zone du code | `.github/CODEOWNERS` | `/.github/  @acme/plateforme` |
| Approbateurs des publications | `environmentReviewers` | `alice @acme/release` |
| Canal de l'équipe (optionnel) | secret `REPOWARDEN_WEBHOOK` | Slack, Teams, Discord, Mattermost… |

Une équipe (`@organisation/equipe`) se gère dans GitHub : arrivées et départs ne touchent aucun fichier.

### Canal de l'équipe

Le workflow de release peut écrire dans un canal : release publiée, PR de release en attente d'approbation, échec. L'adresse du webhook entrant est un **secret**, jamais dans le dépôt :

```bash
gh secret set REPOWARDEN_WEBHOOK      # adresse collée en saisie masquée
```

```yaml
jobs:
  release:
    uses: simdevWarden/repowarden/.github/workflows/release-auto.yml@v4
    secrets:
      webhook: ${{ secrets.REPOWARDEN_WEBHOOK }}
    with:
      notify: release attente echec   # défaut : les trois
```

Le format suit la plateforme reconnue d'après l'adresse (Slack, Discord, Microsoft Teams ; sinon `{"text"}` pour Mattermost, Rocket.Chat…) et le message la langue du projet. Un envoi impossible est signalé sans jamais interrompre une release.

## Traçabilité et arrêt d'urgence

- Chaque merge, approbation, déploiement et contournement est enregistré (historique des PR, onglet *Environments*, journal d'audit).
- Les tags `v*` ne peuvent être posés ou supprimés que par les workflows (ruleset « repowarden (tags) »), et les tags de version `vX.Y.Z` jamais déplacés (ruleset « repowarden (tags de version) ») ; seul le tag majeur (`v4`) reste mobile, déplacé à chaque release (voir [Versions et releases](releases.md)) ; chaque paquet publié porte une attestation de provenance vérifiable.
- Suspendre les releases automatiques : *Actions → release → Disable workflow*.
