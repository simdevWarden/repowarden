---
name: repowarden
description: Repowarden skill for AI agents. Triggers on ticket, commit, branch, push, PR, CI, gh, forbidden action or guard refusal.
---
<!-- repowarden:skill installed by repowarden agents init; remove this line to customize it -->

# Repowarden

## Goal
Follow the repowarden workflow in the repo: no change without a ticket, written design, `repowarden cc`, draft PR opened by the bot, release by the maintainer.

## Workflow
1. **Ticket before any change** (including GitHub settings). Without a ticket, stop and ask for one: an agent only creates a ticket (`repowarden ticket nouveau "<title>"`) when asked to, and never validates one.
2. **Design**: write a "Conception retenue" on the ticket (what, files touched, out of scope). Any change of plan must be noted on the ticket before or when it happens.
3. **Take the ticket**: `repowarden ticket <n>`. Branch `type/<n>-sujet` is created from `develop`.
4. **Sandbox tests**: use `./.essai/` for disposable repos without a remote. Delete them at the end.
5. **Code and commit**: `git add <files>` (never `git add .`, `-A` or `--all`). Commit via `repowarden cc -m "<description only>" --type <type> --scope <scope> --body "<why>" --refs "Ticket : #<n>"` (French messages, header ≤ 72 chars, no signature/agent). No `--no-verify`.
6. **Push**: `git push -u origin HEAD` without force. The bot opens a draft PR to `develop` with `Ticket : #<n>` (never `Closes #<n>`).
7. **PR**: the maintainer marks it ready and releases; the agent follows `repowarden pr checks <n>` and reports when everything is green. An agent does not merge, does not mark a PR ready, does not close tickets. Only `develop` enters `main`, via the release PR.

## Useful commands
- `repowarden ticket <n>` / `repowarden ticket comment <n> "<text>"`
- `repowarden cc --dry-run -m "<description>" --type <type> --scope <scope> --body "<why>" --refs "Ticket : #<n>"`
- `repowarden pr checks <n>`, `repowarden run rerun <id|--failed|--workflow>`
- `REPOWARDEN_TICKET=<n> gh …`: GitHub write outside the workflow, tied to ticket <n>
- `opencode run --auto "<instruction>" < /dev/null`: non-interactive opencode (without `--auto` every permission is denied, without `< /dev/null` it waits silently)

## Guard
It refuses in particular:
- direct or forced push to `main`/`develop`;
- `git commit` outside `repowarden cc`;
- modifying a file on a protected branch or outside a ticket branch;
- `gh` write outside the workflow without a ticket;
- validating a ticket or changing its status.

If `repowarden garde` refuses an action: read the message, run exactly the command indicated, never bypass (`--no-verify`, `--admin`, exception). A quoted string containing a forbidden command must go in a file. If the refusal seems impossible given the ticket design, stop and explain on the ticket instead of guessing.

## Rules
- French commit messages, no signature or co-author from an agent.
- Bash 3.2 compatible if touching shell scripts.
- A bug becomes a ticket; if linked to an open ticket, note it as "Ajout" there.
