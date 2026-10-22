# Politique de sécurité

## Versions supportées

| Version | Supportée |
|---|---|
| Dernière version majeure (`v1`) | ✅ correctifs de sécurité |
| Versions majeures précédentes | ❌ |

## Signaler une vulnérabilité

**Ne pas ouvrir d'issue publique.** Utiliser le signalement privé de GitHub :
onglet *Security* → *Report a vulnerability*.

Inclure : version concernée, scénario de reproduction, impact estimé.

Délais visés : accusé de réception sous 3 jours ouvrés, correctif ou plan d'action sous 30 jours.

## Vérifier une release

Chaque release contient une archive source signée avec [Sigstore](https://www.sigstore.dev) par le workflow de release (sans clé privée à gérer) :

```bash
TAG=v1.1.0
gh release download "$TAG" --repo simdevWarden/repowarden -p "repowarden-$TAG*"
cosign verify-blob "repowarden-$TAG.tar.gz" \
  --bundle "repowarden-$TAG.tar.gz.sigstore.json" \
  --certificate-identity-regexp '^https://github.com/simdevWarden/repowarden/\.github/workflows/release\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Chaque release contient aussi une **preuve de provenance [SLSA](https://slsa.dev) niveau 3** (`repowarden-vX.Y.Z.intoto.jsonl`) : elle atteste que l'archive a été construite par le workflow de release de ce dépôt, depuis le commit du tag.

```bash
slsa-verifier verify-artifact "repowarden-$TAG.tar.gz" \
  --provenance-path "repowarden-$TAG.intoto.jsonl" \
  --source-uri github.com/simdevWarden/repowarden --source-branch main
```

(`--source-branch main` : les releases sont construites par le workflow lancé sur `main`, qui crée ensuite le tag.)

## Ce que repowarden fait pour la sécurité

- Détection de secrets (gitleaks) dans les hooks et en CI ; gitleaks installé en CI à **version figée avec somme SHA-256 vérifiée**.
- Actions GitHub figées par SHA, outils Python de la CI figés par empreinte (`--require-hashes`), mis à jour par Dependabot (verrous pip régénérés avec la commande de leur en-tête par le workflow `verrous-pip`, qui demande le secret **Dependabot** `REPOWARDEN_APP_KEY`) ; workflows sans droits par défaut.
- Analyse CodeQL des workflows, évaluation OpenSSF Scorecard.
- Aucun secret utilisé par les workflows hors `GITHUB_TOKEN` (lecture seule par défaut) et le jeton optionnel de release.
- Les hooks n'exécutent que les outils installés sur le poste ou déclarés par le projet ; aucun téléchargement au moment du commit.
