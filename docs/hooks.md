# Hooks et règles

## Les hooks

| Hook | Rôle |
|---|---|
| `post-checkout` | Avertit dès qu'on arrive sur une branche mal nommée (non bloquant) |
| `pre-commit` | Refuse les branches mal nommées, bloque les commits directs sur les branches protégées (`main`/`master` par défaut), détecte les secrets, formate **uniquement le contenu stagé** (le travail non stagé est préservé) |
| `prepare-commit-msg` | Préfixe le message d'après la branche : sur `feat/bean`, `git commit -m "ajoute X"` → `feat(bean): ajoute X` |
| `commit-msg` | Impose [Conventional Commits](https://www.conventionalcommits.org), 72 caractères maximum |
| `pre-push` | Refuse les branches mal nommées et le push direct sur les branches protégées (`protectedBranches`, création initiale permise) ; **lint** (shellcheck pour les scripts shell, actionlint pour les workflows GitHub) puis build et tests **du commit poussé**, seulement pour les projets touchés (succès : une ligne de résumé par projet ; échec : sortie complète) |
| `post-merge` | Après un `git pull` : supprime les branches locales mergées (classique ou squash) dont la branche distante a été supprimée ; jamais une branche contenant du travail non intégré |

Contournement ponctuel : `git commit --no-verify`, `git push --no-verify` — la [CI](ci.md) refait les vérifications.

## Secrets au pre-commit

Avec [gitleaks](https://github.com/gitleaks/gitleaks) installé, le contenu stagé est analysé avant chaque commit. Un secret trouvé refuse le commit et dit **où** il est, **sans jamais afficher sa valeur** :

```text
✖ Secret détecté : commit refusé.
  config/app.ini:3 (github-pat)

Que faire :
  1. Retirer la valeur du fichier (variable d'environnement, fichier ignoré), puis recommencer le commit.
  2. Fichier qui ne doit jamais être versionné : l'ajouter à .gitignore, puis git rm --cached <fichier>.
  3. Clé qui a pu fuir ailleurs (déjà poussée, partagée) : la révoquer chez son fournisseur.
  Faux positif : ajouter son empreinte à .gitleaksignore :
    config/app.ini:github-pat:3
```

gitleaks en panne (configuration invalide, version incompatible) refuse aussi le commit, avec son message d'erreur : la détection n'a pas été faite, ce n'est jamais présenté comme une fuite. Sans gitleaks, la détection est ignorée avec la commande d'installation ; la vérification `secrets` de la [CI](ci.md) la refait. Désactiver pour un dépôt : `git config repowarden.skip secrets`.

## Lint au pre-push

Le hook `pre-push` lance des linters sur les fichiers modifiés **avant** les tests :

| Linter | Fichiers ciblés | Outil requis |
|---|---|---|
| **shellcheck** | `*.sh`, `*.bash` et scripts sans extension avec shebang (`#!/bin/sh`, `#!/bin/bash`, `#!/usr/bin/env bash`…) | `shellcheck` |
| **actionlint** | `.github/workflows/*.yml`, `.github/workflows/*.yaml` | `actionlint` |

### Sévérité shellcheck

Réglage `repowarden.lintSeverity` (dans `.repowarden.conf` ou `git config`) :

| Valeur | Comportement | Checks activés |
|---|---|---|
| `error` | Bloque seulement sur les erreurs | Obligatoires niveau error |
| `warning` (défaut) | Bloque sur erreurs + avertissements | Obligatoires error + warning |
| `style` | Bloque aussi sur les remarques de style | Tous + optionnels (`-o all`) |
| `info` | Bloque sur tout | Tous + optionnels (`-o all`) |

### Désactiver le lint

- `repowarden.skip lint` (git config ou `.repowarden.conf`) : désactive complètement le lint au push.
- Mode strict CI (`REPOWARDEN_WARN_FILE` défini) : outil manquant = échec.

### Installation des outils

Si un linter est absent, un message d'avertissement indique la commande d'installation selon l'OS :
- macOS : `brew install shellcheck` / `brew install actionlint`
- Linux : `apt-get install shellcheck` / `go install github.com/rhysd/actionlint/cmd/actionlint@latest`
- Windows : `choco install shellcheck` / `scoop install actionlint`

## Messages de commit

Format `<type>(<scope>): <description>` ; `!` après le type pour un changement majeur (`feat!: …`).

| Type | Usage | Release |
|---|---|---|
| `feat` | nouvelle fonctionnalité | version mineure (1.**4**.0) |
| `fix` | correction de bug | correctif (1.4.**1**) |
| `perf` | performance | correctif |
| `docs` | documentation | correctif |
| `style`, `refactor`, `test`, `build`, `ci`, `chore`, `revert` | formatage, restructuration, tests, build, CI, maintenance, annulation | aucune à eux seuls |

**Agents IA** : les signatures d'agent (`Co-Authored-By: Claude …`, « 🤖 Generated with … ») sont **retirées** du message, et un commit dont l'auteur ou le committer est un agent (`noreply@anthropic.com`, Copilot, Cursor, Devin) est **refusé** : l'historique porte l'identité d'une personne. Les bots d'automatisation (`github-actions`, App repowarden, Dependabot) ne sont pas concernés. Pour autoriser les agents : `git config repowarden.allowAgentSignatures true` (ou dans `.repowarden.conf`). Pour arrêter un agent **avant** qu'il ne modifie une branche protégée ou ne contourne les hooks : [garde-fou des agents](agents.md) (`repowarden agents init`).

Un `!` (`feat!: …`) ou un pied de page `BREAKING CHANGE:` donne une **version majeure**. Voir [releases automatiques](industrialisation.md#2-versions-et-releases-automatiques).

## Assistant de commit : `git cc`

Pour écrire un message conforme sans retenir le format, `git cc` guide pas à pas (alias installé par `install.sh`), dans la langue choisie à l'installation :

```text
$ git cc
◆ repowarden · commit conventionnel
Entrée = valeur proposée entre [crochets] · Ctrl+C pour abandonner

◇ 1/5  Type de changement
   1  ✨  feat      nouvelle fonctionnalité
   2  🐛  fix       correction de bug
   …
Numéro ou nom [feat] :                          ← proposé d'après la branche feat/panier

◇ 2/5  Scope (optionnel)
Scope (« - » pour aucun) [panier] :

◇ 3/5  Changement incompatible ?
Incompatible ? [o/N] :

◇ 4/5  Description
  À l'impératif, sans majuscule initiale ni point final ; 58 caractères au plus.
feat(panier): ajoute le panier

◇ 5/5  Détails (optionnels)
> Le client garde ses articles entre deux visites.
>
Références (ex. Closes #12 ; Entrée pour aucune) : Closes #12

┌─ Message ───────────────────────────────────────────────
│ feat(panier): ajoute le panier
│
│ Le client garde ses articles entre deux visites.
│
│ Closes #12
└─────────────────────────────────────────────────────────
Commiter ? [O/n] :
```

| Étape | Obligatoire | Aide |
|---|---|---|
| Type | oui | menu (numéro ou nom), proposé d'après la branche ; rien n'est proposé sur une branche hors convention (`wip/…`) : le type doit être choisi |
| Scope | non | proposé d'après la branche ; un scope invalide est corrigé et proposé (« doc test » → `doc-test`) |
| Changement incompatible | non | ajoute `!` et le pied `BREAKING CHANGE: …`, décrit aussitôt (10 caractères au moins) ; question sautée au premier commit du dépôt |
| Description | oui | longueur de l'en-tête contrôlée (72 caractères) ; point final retiré |
| Corps | non | plusieurs lignes : le pourquoi ; une ligne vide (ou seulement `;`, `.`) termine |
| Références | non | exemple adapté à la plateforme : `Closes #12`, `!34` (GitLab), `PROJ-42` (Bitbucket) |

**Sur une branche protégée** (`main`…), le commit serait refusé : l'assistant le dit dès l'étape 2 et propose une branche `<type>/<scope>` (Entrée pour la créer, tes modifications suivent ; « n » pour abandonner). Une réponse incomplète est complétée (`feat` → `feat/<scope>`), un nom approximatif corrigé (`Mon Essai` → `feat/mon-essai`).

**Saisie robuste** : flèches et effacement dans un terminal, touches parasites ignorées ; une réponse oui/non invalide est redemandée ; Ctrl+D abandonne. Si un hook refuse le commit, le message est conservé (`git commit -F .git/repowarden-message` après correction).

Les options de `git commit` sont transmises (`git cc --no-verify`…) ; `git cc --dry-run` affiche le message sans commiter. Réponses fournies par un script (une par ligne sur l'entrée standard) : `git cc --strict`, pour qu'une réponse refusée arrête tout au lieu de lire la ligne suivante comme une nouvelle réponse. Sans `install.sh` : `git config --global alias.cc '!bash /chemin/vers/repowarden/bin/commit'`.

**Sans question** (scripts, agents, CI) : les réponses passent en options, avec les mêmes contrôles, et toute valeur refusée arrête tout sans rien commiter. Le type et le scope omis sont déduits de la branche, comme avec Entrée ; sur une branche protégée, aucune branche n'est créée.

```bash
git cc -m "ajoute le panier"                                  # sur feat/panier → feat(panier): ajoute le panier
git cc --type fix --scope - -m "corrige le total" \
       --body "Le total ignorait la remise." --refs "Closes #12"
git cc --type feat --breaking "le total est en centimes" -m "change l'API du panier"
```

| Option | Rôle |
|---|---|
| `-m`, `--message` | description (obligatoire sans question) |
| `--type` | type (nom ou numéro du menu) |
| `--scope` | scope ; `-` pour aucun |
| `--breaking` | changement incompatible : `!` et pied `BREAKING CHANGE: <texte>` |
| `--body` | corps (plusieurs lignes possibles) |
| `--refs` | références (`Closes #12`) |

Les autres options sont transmises à `git commit` ; `--` termine les options de l'assistant.

## Nommage des branches

Format `<type>/<sujet>` (sujet en `a-z0-9._-`, `/` pour sous-découper) : `feat/inscription`, `fix/user/login`, `hotfix/timeout-db`.

- Averti à la création, refusé au commit et au push, avec la commande de renommage à copier.
- Exceptions par défaut : `main`, `master`, `develop`, `release/*` et les branches des bots (`release-please--*`, `dependabot/*`, `renovate/*`) ; réglage `allowedBranches`.
- Le type devient le préfixe du commit, le sujet son scope (omis au-delà de 20 caractères).
- Alias : `feature/` → `feat`, `bugfix/` et `hotfix/` → `fix`.
- Un message déjà conforme n'est jamais modifié ; merge, squash et amend sont ignorés.

!!! tip "Git n'a pas de hook à la création de branche"
    Le nom est donc vérifié au premier commit et au push. Pour l'imposer côté serveur, voir les [règles serveur](ci.md#regles-cote-serveur).
