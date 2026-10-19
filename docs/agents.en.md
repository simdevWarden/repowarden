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
| Change a file | detached HEAD; protected branch (`protectedBranches`, `integrationBranch`); if the repository tracks its [tickets](tickets.md): branch that is not a ticket's branch (`type/<n>-topic`) | `repowarden ticket <n>` (without ticket tracking: `git switch -c <type>/<topic>`) |
| Create a branch (`git checkout -b`, `git switch -c`, `git branch <name>`, `git worktree add -b`) | the repository tracks its tickets | `repowarden ticket <n>`: branches come from tickets |
| `git commit` | always, except `--amend --no-edit` | `repowarden cc -m "…" --refs "Ticket : #<n>"` (or `git cc`) |
| `--no-verify` (and `git commit -n`) | always | run it again without, fix what the hooks report |
| `git add .`, `-A`, `--all` | always | `git add <files>` |

Each command of a shell line is checked (`&&`, `;`, `|`…), in the right repository (`cd`, `git -C`). A refusal gives the reason and the command:

```text
✖ repowarden : change refused: "main" is a protected branch.
  → Work on a ticket's branch: repowarden ticket <n>
```

## Supported tools

| Tool | Wiring | Project (`--projet`, default) | User (`--global`) |
|---|---|---|---|
| [Claude Code](https://code.claude.com/docs/en/hooks) | `PreToolUse` hook (`Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Bash` tools): `repowarden garde --format claude` | `.claude/settings.json` | `~/.claude/settings.json` |
| [opencode](https://opencode.ai/docs/plugins/) | plugin, `tool.execute.before` hook (`edit`, `write`, `apply_patch`, `bash` tools) | `.opencode/plugins/repowarden-garde.js` | `~/.config/opencode/plugins/repowarden-garde.js` |

`repowarden agents init --claude` or `--opencode` for a single tool. Re-runnable: an existing `settings.json` is completed (nothing if the hook is already there), a modified plugin is kept as is and reported. Nothing is ever overwritten.

## Checker: `repowarden garde`

One checker for all tools: it reads the action on standard input (JSON) and answers with its exit code.

| Code | Meaning | Effect |
|---|---|---|
| 0 | allowed | the action runs |
| 2 | refused | Claude Code blocks the call and passes the message to the agent; the opencode plugin throws an error with this message |
| other | guard out of order (jq missing, unreadable JSON) | nothing is blocked: a warning only |

Formats: `--format claude` (`tool_name`, `tool_input`, `cwd`: the `PreToolUse` hook input), `--format opencode` (default: `tool`, `args`, `cwd`).

## Limitations

- **Safety net, not a wall**: git hooks and the `ticket` check in CI remain the protection. A change made through the shell (`sed -i`, `>` redirection, script) is not seen before the commit, where the hooks check it.
- **Reading a shell line**: simple splitting (quotes and subshells are not interpreted); a command hidden in `bash -c "…"` or in a variable is not seen.
- **Requirements**: `repowarden` on the `PATH` (`npm install -g repowarden`) and [jq](https://jqlang.org). Otherwise nothing is blocked (the guard never blocks an agent because of a failure).
- **opencode**: the plugin API is evolving; the guard uses the documented `tool.execute.before` hook. The new `{ id, setup }` API (`@opencode-ai/plugin` package, v2) does not expose tools yet.
- **Other tools** (Cursor, Gemini CLI…): not supported yet; only hooks and CI apply.
