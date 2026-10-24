# Carte du projet

Un agent IA (ou une personne) qui reprend un projet l'explore fichier par fichier pour comprendre « quoi fait quoi et pourquoi » : coûteux en contexte. repowarden demande déjà, au-dessus de chaque nouvelle fonction, une à deux lignes qui disent ce qu'elle fait et pourquoi ([hooks](hooks.md)). La **carte** rassemble ces « pourquoi » en un index, sans LLM ; seule la conception des tickets passe par `gh`, en option.

```bash
repowarden carte        # (re)génère .repowarden/carte/carte.json
```

```text
✔ Carte : 80 fichier(s), 395 fonction(s), dont 154 sans commentaire → .repowarden/carte/carte.json
```

## Contenu

Pour chaque fichier du dépôt (suivi, ou nouveau et non ignoré, hors `repowarden.exclude`) : ses fonctions, leur ligne et leur **pourquoi**, le texte des lignes de commentaire juste au-dessus de la déclaration (directives d'outil comme `# shellcheck disable=…` sautées). Une fonction sans commentaire y figure avec un pourquoi vide.

```json
{
  "fichiers": {
    "bin/outil": {
      "fonctions": [{ "ligne": 3, "nom": "main", "pourquoi": "Point d'entrée : lit les options" }],
      "tests": ["test/outil.bats"],
      "tickets": [12]
    }
  },
  "tickets": { "12": { "fichiers": ["bin/outil"] } },
  "version": 1
}
```

- **Une seule détection** : celle du contrôle « fonctions sans commentaire », pas un second analyseur.
- **Premier lot : shell** (`.sh`, `.bash`, ou script à shebang `sh`/`bash`) ; les autres langages viendront, une famille à la fois.
- **Déterministe** : clés triées, ni date ni chemin absolu ; deux lancements sur le même dépôt donnent le même fichier.
- **Jamais versionnée** : le dossier `.repowarden/carte/` contient un `.gitignore` (`*`) qui l'ignore lui-même ; rien à ajouter au `.gitignore` du projet.
- Demande `jq`.

## Interroger

Lire seulement l'extrait utile, sans charger tout le JSON :

```bash
repowarden carte bin/garde          # fonctions du fichier et leur pourquoi
repowarden carte verifier_gh        # fichier, ligne, pourquoi de la fonction
repowarden carte bin/garde --json   # même extrait, pour les outils (aussi : repowarden carte --json)
```

```text
verifier_gh  bin/garde:262
  Commande gh (mots $@, sans « gh ») lancée depuis $dir, …
```

Un chemin est lu depuis le dossier courant (`repowarden carte outil.sh` dans `lib/`) ; un nom qui n'est ni un fichier ni une fonction de la carte : message et code 1. **Carte absente ou périmée** (un fichier du dépôt ou l'index git plus récent qu'elle) : régénérée avant de répondre.

## Tests liés

Avant de modifier un fichier, savoir quels tests le couvrent, pour les écrire d'abord puis les relancer. `repowarden carte <fichier>` les donne après ses fonctions, avec la commande :

```text
Tests : test/garde.bats
  → bats test/garde.bats
```

Un test (`*.bats`, premier lot) est relié à un fichier cartographié par :

- **nommage** : même nom sans extension (`bin/garde` ↔ `test/garde.bats`) ;
- **chemin cité** dans le test (`$BATS_TEST_DIRNAME/../ci/check.sh` cite `ci/check.sh`), sans autre caractère de nom collé ;
- **commande** `repowarden <sous-commande>` citée dans le test → `bin/<sous-commande>`.

Un fichier sans test est signalé (« Aucun test trouvé ») ; dans le JSON, `"tests": []`. Les tests sont lus même s'ils sont dans `repowarden.exclude`.

## Tickets

Le pourquoi d'un fichier est aussi dans son histoire : les tickets qui l'ont modifié. La carte les lit dans **git seulement** (hors ligne, jamais `gh`) : pieds `Ticket : #<n>` des commits (en-tête de squash compris), et, pour une fusion, la branche `type/<n>-sujet` fusionnée (`Merge branch 'fix/40-x'`, `Merge pull request #5 from o/feat/12-x`). Le numéro `(#471)` d'un en-tête de squash est celui de la PR : il n'est pas lu.

```bash
repowarden carte '#12'          # fichiers modifiés par le ticket 12 (--json : {"ticket", "fichiers"})
repowarden carte bin/garde      # … puis « Tickets : #317 #407 … »
```

Tout fichier encore présent (hors `repowarden.exclude`) touché par un ticket entre dans la carte, même sans fonction (doc, workflow) ; la racine `tickets` donne les fichiers de chaque ticket.

## Conception des tickets

La décision derrière un changement est écrite dans le commentaire « Conception retenue » de son ticket. La carte la rattache aux fichiers, pour qu'un agent n'ait pas à la chercher :

```bash
repowarden carte '#12'          # fichiers, puis « Conception : » et son résumé
repowarden carte lib/a.sh       # … « #12 — <première ligne de la conception> » par ticket
```

- **Même résumé que la PR brouillon** : « Ce qui change » et « Hors périmètre » de la dernière « Conception retenue », puis les commentaires « Ajout » / « Constat lié » ; seuls les commentaires de mainteneur comptent.
- **Lu par `gh`, mis en cache** dans `.repowarden/carte/conception/<n>.md` (vide pour un ticket sans conception) : un seul appel (`gh issue list --state all`, lecture), et seulement s'il manque des tickets au cache ; ensuite, plus aucun appel. Pour rafraîchir : supprimer ce dossier.
- **`gh` absent ou non connecté** : avertissement, carte sans conception, code 0.
- JSON : `"tickets": {"12": {"fichiers": [...], "conception": "…"}}`.

## Fraîcheur

- **Après une fusion locale** (hook `post-merge`, `git pull` compris) : une carte déjà générée est recalculée **hors ligne** (sans `gh` ; les conceptions en cache restent), en silence ; sans carte, rien n'est créé. Mesuré sur repowarden (186 fichiers) : environ 0,2 s de plus pour le hook.
- **`repowarden statut`** : carte périmée → avertissement et étape suivante `repowarden carte` ; absente → simple information (la carte est facultative).
- **À la demande** : `repowarden carte` ; une interrogation régénère d'abord une carte périmée.
- **Agents** : `AGENTS.md` et la page [Agents IA](agents.md) disent « avant de modifier X : `repowarden carte X` » ; un refus du garde-fou sur un fichier existant le rappelle.
