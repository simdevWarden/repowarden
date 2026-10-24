# Carte du projet

Un agent IA (ou une personne) qui reprend un projet l'explore fichier par fichier pour comprendre « quoi fait quoi et pourquoi » : coûteux en contexte. repowarden demande déjà, au-dessus de chaque nouvelle fonction, une à deux lignes qui disent ce qu'elle fait et pourquoi ([hooks](hooks.md)). La **carte** rassemble ces « pourquoi » en un index, sans LLM ni réseau.

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
      "fonctions": [{ "ligne": 3, "nom": "main", "pourquoi": "Point d'entrée : lit les options" }]
    }
  },
  "version": 1
}
```

- **Une seule détection** : celle du contrôle « fonctions sans commentaire », pas un second analyseur.
- **Premier lot : shell** (`.sh`, `.bash`, ou script à shebang `sh`/`bash`) ; les autres langages viendront, une famille à la fois.
- **Déterministe** : clés triées, ni date ni chemin absolu ; deux lancements sur le même dépôt donnent le même fichier.
- **Jamais versionnée** : le dossier `.repowarden/carte/` contient un `.gitignore` (`*`) qui l'ignore lui-même ; rien à ajouter au `.gitignore` du projet.
- Demande `jq`.
