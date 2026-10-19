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
| `--no-verify` (et `git commit -n`) | toujours | relancer sans, corriger ce que les hooks signalent |
| `git add .`, `-A`, `--all` | toujours | `git add <fichiers>` |

Chaque commande d'une ligne shell est vérifiée (`&&`, `;`, `|`…), dans le bon dépôt (`cd`, `git -C`). Un refus donne la raison et la commande :

```text
✖ repowarden : modification refusée : « main » est une branche protégée.
  → Travailler sur la branche d'un ticket : repowarden ticket <n>
```

## Outils pris en charge

| Outil | Branchement | Projet (`--projet`, défaut) | Utilisateur (`--global`) |
|---|---|---|---|
| [Claude Code](https://code.claude.com/docs/en/hooks) | hook `PreToolUse` (outils `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Bash`) : `repowarden garde --format claude` | `.claude/settings.json` | `~/.claude/settings.json` |
| [opencode](https://opencode.ai/docs/plugins/) | plugin, crochet `tool.execute.before` (outils `edit`, `write`, `apply_patch`, `bash`) | `.opencode/plugins/repowarden-garde.js` | `~/.config/opencode/plugins/repowarden-garde.js` |

`repowarden agents init --claude` ou `--opencode` pour un seul outil. Relançable : un `settings.json` existant est complété (rien si le hook y est déjà), un plugin modifié est gardé tel quel et signalé. Rien n'est jamais écrasé.

## Vérificateur : `repowarden garde`

Un seul vérificateur pour tous les outils : il lit l'action sur l'entrée standard (JSON) et répond par son code de sortie.

| Code | Sens | Effet |
|---|---|---|
| 0 | permis | l'action s'exécute |
| 2 | refusé | Claude Code bloque l'appel et transmet le message à l'agent ; le plugin opencode lève une erreur avec ce message |
| autre | garde-fou en panne (jq absent, JSON illisible) | rien n'est bloqué : un avertissement seulement |

Formats : `--format claude` (`tool_name`, `tool_input`, `cwd` : entrée du hook `PreToolUse`), `--format opencode` (défaut : `tool`, `args`, `cwd`).

## Limites

- **Filet, pas mur** : les hooks git et la vérification `ticket` en CI restent la protection. Une modification faite par le shell (`sed -i`, redirection `>`, script) n'est pas vue avant le commit, où les hooks la vérifient.
- **Lecture d'une ligne shell** : découpage simple (sans interpréter les guillemets ni les sous-shells) ; une commande cachée dans `bash -c "…"` ou une variable n'est pas vue.
- **Prérequis** : `repowarden` dans le `PATH` (`npm install -g repowarden`) et [jq](https://jqlang.org). Sinon, rien n'est bloqué (le garde-fou ne bloque jamais un agent par une panne).
- **opencode** : l'API des plugins évolue ; le garde-fou utilise le crochet documenté `tool.execute.before`. La nouvelle API `{ id, setup }` (paquet `@opencode-ai/plugin`, v2) n'expose pas encore les outils.
- **Autres outils** (Cursor, Gemini CLI…) : pas encore pris en charge ; seuls les hooks et la CI s'appliquent.
