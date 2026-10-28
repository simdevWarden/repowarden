# Agents IA

Un agent IA (Claude Code, opencode…) peut modifier une branche protégée, travailler sans ticket ou contourner les hooks. Les hooks git ne l'arrêtent qu'au commit et la CI qu'à la PR : le travail fait d'ici là est perdu. Le **garde-fou** l'arrête **avant chaque action**, avec la commande repowarden à lancer à la place.

```bash
repowarden agents init        # Claude Code et opencode, dans le dépôt (à versionner)
git add .claude/settings.json .opencode/plugins/repowarden-garde.js .opencode/plugins/repowarden-garde-v2.js
```

## Ce qui est refusé

Seulement dans un dépôt repowarden (`.repowarden.conf`, réglage `repowarden.*` ou hooks repowarden actifs) ; ailleurs, tout est permis. Mêmes réglages que les hooks.

| Action de l'agent | Refusée quand | À la place |
|---|---|---|
| Modifier un fichier | HEAD détaché ; branche protégée (`protectedBranches`, `integrationBranch`) ; si le dépôt suit ses [tickets](tickets.md) : branche qui n'est pas celle d'un ticket (`type/<n>-sujet`). Jamais pour un fichier ignoré par git et non suivi (`git check-ignore`) : il n'est jamais versionné | `repowarden ticket <n>` (sans suivi des tickets : `git switch -c <type>/<sujet>`) |
| Créer une branche (`git checkout -b`, `git switch -c`, `git branch <nom>`, `git worktree add -b`) | le dépôt suit ses tickets | `repowarden ticket <n>` : la branche naît du ticket |
| `git commit` | toujours, sauf `--amend --no-edit` | `repowarden cc -m "…" --refs "Ticket : #<n>"` (ou `git cc`) |
| `repowarden cc`, `git cc` | branche protégée : le commit y serait refusé, et sans terminal `cc` ne crée pas de branche à la place de l'agent | `git switch -c <type>/<sujet>` (les modifications suivent) ; si le dépôt suit ses tickets : `repowarden ticket <n>` |
| tout commit (`git commit --amend --no-edit` compris) | hooks repowarden inactifs dans le dépôt (aucun `core.hooksPath` vers les hooks repowarden) : messages, secrets et formatage ne seraient pas vérifiés | `repowarden install` (ou `--global`) |
| `--no-verify` (et `git commit -n`) | toujours | relancer sans, corriger ce que les hooks signalent |
| `git add .`, `-A`, `--all` | toujours | `git add <fichiers>` |
| `git push` forcé : `--force`, `-f` (`-uf`…), `--force-with-lease[=…]`, `--force-if-includes`, refspec `+branche` | toujours : il réécrit l'historique déjà poussé | corriger par un nouveau commit (`repowarden cc …`), puis `git push` sans forcer |
| `gh issue create` | toujours | `repowarden ticket nouveau "<titre>"` |
| `gh issue comment`, `gh issue edit` | toujours | `repowarden ticket comment <n> "…"`, `repowarden ticket label <n> <label>` |
| `gh pr create` | toujours : la PR brouillon est ouverte par le bot au premier push | `git push -u origin HEAD` |
| `gh run rerun` | toujours | `repowarden run rerun <id>` |
| `gh pr ready`, `gh pr merge`, `gh pr review --approve`, `gh api …/pending_deployments` en écriture | toujours, même avec un ticket : décision du mainteneur | annoncer la PR prête, le mainteneur décide |
| `repowarden ticket label <n> validé` (et `--remove`), toute étiquette de statut (`statut: …`) | toujours, même avec `REPOWARDEN_TICKET=<n>` : valider un ticket est une décision du mainteneur | demander au mainteneur de valider le ticket, puis `repowarden ticket <n>` ; les autres étiquettes (`type: fix`…) restent permises |
| toute autre commande `gh` (refus par défaut) : `gh api` en écriture (`-X` autre que `GET`, `-f`/`-F`/`--input` sans `-X GET`, mutation `graphql`), `gh repo edit`, `gh issue close`, `gh pr comment`, `gh pr review` sans `--approve`, `gh release create`, `gh label create`, `gh gist`, sous-commande inconnue… | sans préfixe `REPOWARDEN_TICKET=<n>` d'un ticket **ouvert et validé** (lu par `gh issue view <n>`, dans le dépôt courant ou celui de `-R`) ; ticket illisible : refusé (écriture sans preuve de ticket) | créer le ticket (`repowarden ticket nouveau`), le faire valider, puis `REPOWARDEN_TICKET=<n> gh …` |

Seules les lectures `gh` connues sont permises sans ticket : `view`, `list`, `status`, `checks`, `diff`, `watch`, `gh search`, `gh browse`, `gh api` en lecture, `gh auth status`, l'aide (`--help`), ainsi que `gh pr edit` (description de la PR). **Tout ce qui n'est pas une lecture est refusé sans ticket**, une sous-commande oubliée ou future comprise. Tout changement, réglage GitHub compris, part d'un ticket créé avant.

L'aide et l'aperçu (`--help`, `-h`, `--dry-run` de `repowarden cc`, `git cc`, `git commit`) sont toujours permis : rien n'est commité. Chaque commande d'une ligne shell est vérifiée (`&&`, `;`, `|`…), dans le bon dépôt (`cd`, `git -C`). Un refus vaut pour **toute la ligne** : rien n'en est lancé, pas même les autres commandes (`git add a.txt && git commit …` n'ajoute rien), et le message le dit. Un refus donne la raison et la commande :

```text
✖ repowarden : modification refusée : « main » est une branche protégée.
  → Travailler sur la branche d'un ticket : repowarden ticket <n>
```

## Outils pris en charge

| Outil | Branchement | Projet (`--projet`, défaut) | Utilisateur (`--global`) |
|---|---|---|---|
| [Claude Code](https://code.claude.com/docs/en/hooks) | hook `PreToolUse` (outils `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Bash`) : `repowarden garde --format claude` | `.claude/settings.json` | `$CLAUDE_CONFIG_DIR/settings.json` ([défini](https://code.claude.com/docs/en/settings)), sinon `~/.claude/settings.json` |
| [opencode](https://opencode.ai/docs/plugins/) 1.x | plugin, crochet `tool.execute.before` (outils `edit`, `write`, `apply_patch`, `bash`) | `.opencode/plugins/repowarden-garde.js` | `$OPENCODE_CONFIG_DIR/plugins/` ([défini](https://opencode.ai/docs/config/)), sinon `${XDG_CONFIG_HOME:-~/.config}/opencode/plugins/` |
| opencode 2.x (`@opencode/cli`) | plugin `{ id, setup }`, crochet `ctx.tool.hook("execute.before")` (outils `edit`, `write`, `shell`) | `.opencode/plugins/repowarden-garde-v2.js` | même dossier |

Deux fichiers, un par version d'opencode : opencode 1.x prend un module qui a un export par défaut `{ id, setup }` pour un plugin 2.x et n'appelle plus son export 1.x. Chaque version charge les deux ; celui de l'autre version ne fait rien. Essayé avec opencode 1.18.34, 1.19.4 et 2.1.4.

`repowarden agents init --claude` ou `--opencode` pour un seul outil. Relançable : un `settings.json` existant est complété (rien si le hook y est déjà), un plugin modifié est gardé tel quel et signalé. **Le garde-fou suit les mises à jour de repowarden** : un plugin posé par repowarden (première ligne `// Garde-fou repowarden pour opencode…`, l'ancien plugin autonome compris) ou un hook `repowarden garde…` d'une autre forme que l'actuelle est remplacé par le modèle, les autres hooks restant intacts (« garde-fou mis à jour »). Un fichier personnel (sans cet en-tête) n'est jamais écrasé. `repowarden statut` signale un garde-fou périmé, du dépôt ou de l'utilisateur, avec `repowarden agents init` (`--global` pour l'utilisateur) ; `repowarden install` met à jour, sans question, le garde-fou de l'utilisateur déjà branché. Hooks repowarden inactifs (dépôt, ou `--global` sans `repowarden install --global`) : signalé, avec la commande, puisque le garde-fou refusera alors les commits. `repowarden statut` et `repowarden install` signalent un agent présent (`claude` ou `opencode` dans le `PATH`, ou leur dossier de configuration) sans garde-fou branché, ni dans le dépôt ni pour l'utilisateur, avec `repowarden agents init` ; `install` le propose dans un terminal.

### Retirer le garde-fou

```bash
repowarden agents retirer             # dépôt ; --global : configuration de l'utilisateur
```

Mêmes options qu'`init` (`--claude`, `--opencode`, `--projet`, `--global`). Seul ce qu'`init` a écrit part : dans `settings.json`, les commandes `repowarden garde` (les autres hooks et réglages restent ; le fichier est supprimé s'il ne contient plus rien) ; chaque plugin opencode s'il est identique à son modèle (modifié, il est gardé et signalé). Relancé, rien à retirer, sans erreur.

## Vérificateur : `repowarden garde`

Un seul vérificateur pour tous les outils : il lit l'action sur l'entrée standard (JSON) et répond par son code de sortie.

| Code | Sens | Effet |
|---|---|---|
| 0 | permis | l'action s'exécute |
| 2 | refusé | Claude Code bloque l'appel et transmet le message à l'agent ; le plugin opencode lève une erreur avec ce message |
| autre | garde-fou en panne (jq absent, JSON illisible) | rien n'est bloqué : un avertissement seulement |

Formats : `--format claude` (`tool_name`, `tool_input`, `cwd` : entrée du hook `PreToolUse`), `--format opencode` (défaut : `tool`, `args`, `cwd`).

## Consignes de code

Toute nouvelle fonction a, juste au-dessus, une à deux lignes qui disent ce qu'elle fait et **pourquoi**, sans paraphraser le code : des fonctionnalités documentées dans le code, sans gros blocs de commentaires. À reprendre dans les consignes du projet (`AGENTS.md`, `CLAUDE.md`…) ; le pre-commit et la CI signalent les oublis ([fonctions sans commentaire](hooks.md#fonctions-sans-commentaire)).

## Carte du projet

**Avant de modifier un fichier X : `repowarden carte X`.** L'agent lit l'extrait utile au lieu d'explorer le dépôt : les fonctions de X et leur pourquoi, les tests qui le couvrent (à écrire d'abord, puis à relancer, avec la commande), les tickets qui l'ont modifié et leur conception ([carte du projet](carte.md)). `repowarden carte <fonction>` et `repowarden carte '#<n>'` aussi. À reprendre dans les consignes du projet (`AGENTS.md`, `CLAUDE.md`…). Un refus de modification du garde-fou le rappelle :

```text
✖ repowarden : modification refusée : « main » est une branche protégée.
  → Travailler sur la branche d'un ticket : repowarden ticket <n>
  → Avant de modifier bin/garde, une fois sur la bonne branche : repowarden carte bin/garde (fonctions, tests, tickets)
```

## Limites

- **Filet, pas mur** : les hooks git et la vérification `ticket` en CI restent la protection. Une modification faite par le shell (`sed -i`, redirection `>`, script) n'est pas vue avant le commit, où les hooks la vérifient.
- **Écritures GitHub** : seules celles de `gh` sont vues, et seulement depuis un dépôt repowarden : `gh -R …` lancé hors d'un tel dépôt n'est pas vu ; l'interface web et `curl` vers l'API non plus.
- **Lecture d'une ligne shell** : découpage simple (sans interpréter les guillemets ni les sous-shells) ; une commande cachée dans `bash -c "…"` ou une variable n'est pas vue.
- **Prérequis** : `repowarden` dans le `PATH` (`npm install -g repowarden`) et [jq](https://jqlang.org). Sinon, rien n'est bloqué (le garde-fou ne bloque jamais un agent par une panne).
- **opencode** : l'API des plugins évolue. En 1.x, le crochet documenté `tool.execute.before` ; en 2.x, `ctx.tool.hook("execute.before")`, établi par essai (pas encore documenté). Un plugin repowarden posé avant le plugin 2.x est signalé périmé par `repowarden statut` et complété par `repowarden agents init`.
- **Autres outils** (Cursor, Gemini CLI…) : pas encore pris en charge ; seuls les hooks et la CI s'appliquent.
