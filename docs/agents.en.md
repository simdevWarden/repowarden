# AI agents

An AI agent (Claude Code, opencode…) can change a protected branch, work without a ticket or bypass the hooks. Git hooks stop it only at commit time and CI only at the PR: the work done until then is lost. The **guard** stops it **before each action**, with the repowarden command to run instead.

```bash
repowarden agents init        # Claude Code and opencode, in the repository (to commit)
git add .claude/settings.json .opencode/plugins/repowarden-garde.js
```

## What is refused

Only in a repowarden repository (`.repowarden.conf`, a `repowarden.*` setting or active repowarden hooks); anywhere else, everything is allowed. Same settings as the hooks.

| Agent action | Refused when | Instead |
|---|---|---|
| Change a file | detached HEAD; protected branch (`protectedBranches`, `integrationBranch`); if the repository tracks its [tickets](tickets.md): branch that is not a ticket's branch (`type/<n>-topic`). Never for a file ignored by git and not tracked (`git check-ignore`): it is never versioned | `repowarden ticket <n>` (without ticket tracking: `git switch -c <type>/<topic>`) |
| Create a branch (`git checkout -b`, `git switch -c`, `git branch <name>`, `git worktree add -b`) | the repository tracks its tickets | `repowarden ticket <n>`: branches come from tickets |
| `git commit` | always, except `--amend --no-edit` | `repowarden cc -m "…" --refs "Ticket : #<n>"` (or `git cc`) |
| `repowarden cc`, `git cc` | protected branch: the commit would be refused there, and without a terminal `cc` does not create a branch for the agent | `git switch -c <type>/<topic>` (changes follow); if the repository tracks its tickets: `repowarden ticket <n>` |
| any commit (`git commit --amend --no-edit` included) | repowarden hooks inactive in the repository (no `core.hooksPath` to the repowarden hooks): messages, secrets and formatting would not be checked | `repowarden install` (or `--global`) |
| `--no-verify` (and `git commit -n`) | always | run it again without, fix what the hooks report |
| `git add .`, `-A`, `--all` | always | `git add <files>` |
| forced `git push`: `--force`, `-f` (`-uf`…), `--force-with-lease[=…]`, `--force-if-includes`, `+branch` refspec | always: it rewrites the history already pushed | fix it with a new commit (`repowarden cc …`), then `git push` without forcing |
| `gh issue create` | always | `repowarden ticket nouveau "<title>"` |
| `gh issue comment`, `gh issue edit` | always | `repowarden ticket comment <n> "…"`, `repowarden ticket label <n> <label>` |
| `gh pr create` | always: the draft PR is opened by the bot on the first push | `git push -u origin HEAD` |
| `gh run rerun` | always | `repowarden run rerun <id>` |
| `gh pr ready`, `gh pr merge`, `gh pr review --approve`, writing `gh api …/pending_deployments` | always, even with a ticket: the maintainer's decision | say the PR is ready, the maintainer decides |
| any other `gh` command (refused by default): writing `gh api` (`-X` other than `GET`, `-f`/`-F`/`--input` without `-X GET`, `graphql` mutation), `gh repo edit`, `gh issue close`, `gh pr comment`, `gh pr review` without `--approve`, `gh release create`, `gh label create`, `gh gist`, unknown subcommand… | without a `REPOWARDEN_TICKET=<n>` prefix of an **open and validated** ticket (read with `gh issue view <n>`, in the current repository or the `-R` one); unreadable ticket: refused (a write without proof of a ticket) | create the ticket (`repowarden ticket nouveau`), get it validated, then `REPOWARDEN_TICKET=<n> gh …` |

Only known `gh` reads are allowed without a ticket: `view`, `list`, `status`, `checks`, `diff`, `watch`, `gh search`, `gh browse`, read-only `gh api`, `gh auth status`, help (`--help`), plus `gh pr edit` (PR description). **Anything that is not a read is refused without a ticket**, forgotten or future subcommands included. Every change, GitHub settings included, starts from a ticket created beforehand.

Help and preview (`--help`, `-h`, `--dry-run` of `repowarden cc`, `git cc`, `git commit`) are always allowed: nothing is committed. Each command of a shell line is checked (`&&`, `;`, `|`…), in the right repository (`cd`, `git -C`). A refusal applies to **the whole line**: none of it runs, not even the other commands (`git add a.txt && git commit …` adds nothing), and the message says so. A refusal gives the reason and the command:

```text
✖ repowarden : change refused: "main" is a protected branch.
  → Work on a ticket's branch: repowarden ticket <n>
```

## Supported tools

| Tool | Wiring | Project (`--projet`, default) | User (`--global`) |
|---|---|---|---|
| [Claude Code](https://code.claude.com/docs/en/hooks) | `PreToolUse` hook (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Bash` tools): `repowarden garde --format claude` | `.claude/settings.json` | `$CLAUDE_CONFIG_DIR/settings.json` ([if set](https://code.claude.com/docs/en/settings)), else `~/.claude/settings.json` |
| [opencode](https://opencode.ai/docs/plugins/) | plugin, `tool.execute.before` hook (`edit`, `write`, `apply_patch`, `bash` tools) | `.opencode/plugins/repowarden-garde.js` | `$OPENCODE_CONFIG_DIR/plugins/` ([if set](https://opencode.ai/docs/config/)), else `${XDG_CONFIG_HOME:-~/.config}/opencode/plugins/` |

`repowarden agents init --claude` or `--opencode` for a single tool. Re-runnable: an existing `settings.json` is completed (nothing if the hook is already there), a modified plugin is kept as is and reported. **The guard follows repowarden updates**: a plugin written by repowarden (first line `// Garde-fou repowarden pour opencode…`, the former standalone plugin included) or a `repowarden garde…` hook in a form other than the current one is replaced by the template, other hooks staying intact ("guard updated"). A personal file (without that header) is never overwritten. `repowarden statut` reports an outdated guard, in the repository or for the user, with `repowarden agents init` (`--global` for the user); `repowarden install` updates, without asking, the user guard already wired. repowarden hooks inactive (repository, or `--global` without `repowarden install --global`): reported, with the command, since the guard will then refuse commits. `repowarden statut` and `repowarden install` report an agent present (`claude` or `opencode` in the `PATH`, or their configuration folder) with the guard wired neither in the repository nor for the user, with `repowarden agents init`; `install` offers it in a terminal.

### Removing the guard

```bash
repowarden agents retirer             # repository; --global: user configuration (alias: remove)
```

Same options as `init` (`--claude`, `--opencode`, `--projet`, `--global`). Only what `init` wrote goes: in `settings.json`, the `repowarden garde` commands (other hooks and settings stay; the file is deleted if nothing is left); the opencode plugin if identical to the template (modified, it is kept and reported). Run again, nothing to remove, no error.

## Checker: `repowarden garde`

One checker for all tools: it reads the action on standard input (JSON) and answers with its exit code.

| Code | Meaning | Effect |
|---|---|---|
| 0 | allowed | the action runs |
| 2 | refused | Claude Code blocks the call and passes the message to the agent; the opencode plugin throws an error with this message |
| other | guard out of order (jq missing, unreadable JSON) | nothing is blocked: a warning only |

Formats: `--format claude` (`tool_name`, `tool_input`, `cwd`: the `PreToolUse` hook input), `--format opencode` (default: `tool`, `args`, `cwd`).

## Code instructions

Every new function has, right above it, one or two lines saying what it does and **why**, without paraphrasing the code: features documented in the code, without big comment blocks. Copy it into the project instructions (`AGENTS.md`, `CLAUDE.md`…); the pre-commit hook and the CI report omissions ([functions without a comment](hooks.md#functions-without-a-comment)).

## Limitations

- **Safety net, not a wall**: git hooks and the `ticket` check in CI remain the protection. A change made through the shell (`sed -i`, `>` redirection, script) is not seen before the commit, where the hooks check it.
- **GitHub writes**: only `gh` ones are seen, and only from a repowarden repository: `gh -R …` run outside such a repository is not seen; neither are the web interface and `curl` to the API.
- **Reading a shell line**: simple splitting (quotes and subshells are not interpreted); a command hidden in `bash -c "…"` or in a variable is not seen.
- **Requirements**: `repowarden` on the `PATH` (`npm install -g repowarden`) and [jq](https://jqlang.org). Otherwise nothing is blocked (the guard never blocks an agent because of a failure).
- **opencode**: the plugin API is evolving; the guard uses the documented `tool.execute.before` hook. The new `{ id, setup }` API (`@opencode-ai/plugin` package, v2) does not expose tools yet.
- **Other tools** (Cursor, Gemini CLI…): not supported yet; only hooks and CI apply.
