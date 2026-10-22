# Agents IA

Un agent IA (Claude Code, opencode…) peut modifier une branche protégée, travailler sans ticket ou contourner les hooks. Les hooks git ne l'arrêtent qu'au commit et la CI qu'à la PR : le travail fait d'ici là est perdu. Le **garde-fou** l'arrête **avant chaque action**, avec la commande repowarden à lancer à la place.

```bash
repowarden agents init        # Claude Code et opencode, dans le dépôt (à versionner)
git add .claude/settings.json .opencode/plugins/repowarden-garde.js
```

## Ce qui est refusé

Seulement dans un dépôt repowarden (`.repowarden.conf`, réglage `repowarden.*` ou hooks repowarden actifs) ; ailleurs, tout est permis. Mêmes réglages que les hooks.

| Action de l'agent | Refusée quand | À la place |
|---|---|---|
| Modifier un fichier | HEAD détaché ; branche protégée (`protectedBranches`, `integrationBranch`) ; si le dépôt suit ses [tickets](tickets.md) : branche qui n'est pas celle d'un ticket (`type/<n>-sujet`) | `repowarden ticket <n>` (sans suivi des tickets : `git switch -c <type>/<sujet>`) |
| Créer une branche (`git checkout -b`, `git switch -c`, `git branch <nom>`, `git worktree add -b`) | le dépôt suit ses tickets | `repowarden ticket <n>` : la branche naît du ticket |
| `git commit` | toujours, sauf `--amend --no-edit` | `repowarden cc -m "…" --refs "Ticket : #<n>"` (ou `git cc`) |
| `repowarden cc`, `git cc` | branche protégée : le commit y serait refusé, et sans terminal `cc` ne crée pas de branche à la place de l'agent | `git switch -c <type>/<sujet>` (les modifications suivent) ; si le dépôt suit ses tickets : `repowarden ticket <n>` |
| tout commit (`git commit --amend --no-edit` compris) | hooks repowarden inactifs dans le dépôt (aucun `core.hooksPath` vers les hooks repowarden) : messages, secrets et formatage ne seraient pas vérifiés | `repowarden install` (ou `--global`) |
| `--no-verify` (et `git commit -n`) | toujours | relancer sans, corriger ce que les hooks signalent |
| `git add .`, `-A`, `--all` | toujours | `git add <fichiers>` |
| `git push` forcé : `--force`, `-f` (`-uf`…), `--force-with-lease[=…]`, `--force-if-includes`, refspec `+branche` | toujours : il réécrit l'historique déjà poussé | corriger par un nouveau commit (`repowarden cc …`), puis `git push` sans forcer |

L'aide et l'aperçu (`--help`, `-h`, `--dry-run` de `repowarden cc`, `git cc`, `git commit`) sont toujours permis : rien n'est commité. Chaque commande d'une ligne shell est vérifiée (`&&`, `;`, `|`…), dans le bon dépôt (`cd`, `git -C`). Un refus vaut pour **toute la ligne** : rien n'en est lancé, pas même les autres commandes (`git add a.txt && git commit …` n'ajoute rien), et le message le dit. Un refus donne la raison et la commande :

```text
✖ repowarden : modification refusée : « main » est une branche protégée.
  → Travailler sur la branche d'un ticket : repowarden ticket <n>
```

## Outils pris en charge

| Outil | Branchement | Projet (`--projet`, défaut) | Utilisateur (`--global`) |
|---|---|---|---|
| [Claude Code](https://code.claude.com/docs/en/hooks) | hook `PreToolUse` (outils `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Bash`) : `repowarden garde --format claude` | `.claude/settings.json` | `$CLAUDE_CONFIG_DIR/settings.json` ([défini](https://code.claude.com/docs/en/settings)), sinon `~/.claude/settings.json` |
| [opencode](https://opencode.ai/docs/plugins/) | plugin, crochet `tool.execute.before` (outils `edit`, `write`, `apply_patch`, `bash`) | `.opencode/plugins/repowarden-garde.js` | `$OPENCODE_CONFIG_DIR/plugins/` ([défini](https://opencode.ai/docs/config/)), sinon `${XDG_CONFIG_HOME:-~/.config}/opencode/plugins/` |

`repowarden agents init --claude` ou `--opencode` pour un seul outil. Relançable : un `settings.json` existant est complété (rien si le hook y est déjà), un plugin modifié est gardé tel quel et signalé. Rien n'est jamais écrasé. Hooks repowarden inactifs (dépôt, ou `--global` sans `repowarden install --global`) : signalé, avec la commande, puisque le garde-fou refusera alors les commits.

### Retirer le garde-fou

```bash
repowarden agents retirer             # dépôt ; --global : configuration de l'utilisateur
```

Mêmes options qu'`init` (`--claude`, `--opencode`, `--projet`, `--global`). Seul ce qu'`init` a écrit part : dans `settings.json`, les commandes `repowarden garde` (les autres hooks et réglages restent ; le fichier est supprimé s'il ne contient plus rien) ; le plugin opencode s'il est identique au modèle (modifié, il est gardé et signalé). Relancé, rien à retirer, sans erreur.

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

## Limites

- **Filet, pas mur** : les hooks git et la vérification `ticket` en CI restent la protection. Une modification faite par le shell (`sed -i`, redirection `>`, script) n'est pas vue avant le commit, où les hooks la vérifient.
- **Lecture d'une ligne shell** : découpage simple (sans interpréter les guillemets ni les sous-shells) ; une commande cachée dans `bash -c "…"` ou une variable n'est pas vue.
- **Prérequis** : `repowarden` dans le `PATH` (`npm install -g repowarden`) et [jq](https://jqlang.org). Sinon, rien n'est bloqué (le garde-fou ne bloque jamais un agent par une panne).
- **opencode** : l'API des plugins évolue ; le garde-fou utilise le crochet documenté `tool.execute.before`. La nouvelle API `{ id, setup }` (paquet `@opencode-ai/plugin`, v2) n'expose pas encore les outils.
- **Autres outils** (Cursor, Gemini CLI…) : pas encore pris en charge ; seuls les hooks et la CI s'appliquent.
