# Tickets

Every change starts from a **ticket** (GitHub issue): **the branch derives from the ticket**, and each step of the ticket's life moves the branch and the PR forward, from idea to production, without manual tracking.

## A ticket's lifecycle

| Status (label) | When | Automatic effect |
|---|---|---|
| `statut: à valider` | ticket created (by hand, or `repowarden ticket nouveau`) | — |
| `statut: backlog` | a maintainer adds the **`validé`** label, or opens the ticket themselves (validated straight away) | ticket ready to be taken; comment with the command to take it |
| `statut: en cours` | someone assigns themselves the ticket (or `repowarden ticket N`), or pushes a first commit to its branch | on assignment: **branch `<type>/<n>-<title>` created** from `develop` and **linked to the ticket** (*Development* panel), so a ticket validated for later has no branch going stale; on the first push: **draft PR** opened to `develop`, titled with the **header of the branch's first commit**, trailing `(#n)` removed (it becomes the squash commit; if it is not conventional: the ticket title, scope from its prefix, acronyms kept, no word cut), with a **description taken from the ticket** (acceptance criteria as checkboxes, maintainer comments titled "Ajout" or "Constat lié", summary of the "Conception retenue": what changes and out of scope, commit list, `Ticket : #n`), assigned; **refreshed on every push** while it is a draft, a hand-written `## Réalisé` section being kept as is |
| `statut: en relecture` | PR "Ready for review" | CI runs; a "Request changes" review moves the ticket back to in progress |
| `statut: préprod` | PR merged into `develop` | branch deleted; comment on each pre-release `vX.Y.Z-next.N` |
| `statut: done` | release on `main`, or delivery without a new version (no `fix` nor `feat`) | ticket **closed**, with the version (or "without a new version" and the delivered commit) |

A **delivered** ticket (`préprod`, `done`) never goes back: a PR event handled late (PR edited after its merge), a branch that reappears or a reassignment does not bring it back to in progress or in review; the tracking reports it with a notice.

Ticket closed as **abandoned** (*not planned*): its PR is closed and its branch deleted.

**Finished** ticket (moved to `done` at release, or closed by hand) whose branch still exists, because the work went through another branch: the branch is deleted if it has no commit missing from `develop` and no open PR comes from it. Otherwise it is kept and the ticket says so: nothing is ever lost.

Everything is automatic except validation: it is the only human decision, and GitHub only lets people with rights on the repository add the `validé` label. A ticket **opened by a maintainer** (write access: owner, member, collaborator) is **validated straight away**: opening it is already their decision; every event on the ticket (label, assignment) catches up on this validation if the opening run was cancelled. Only community tickets wait for the label. To **propose** a ticket without validating it (idea, test feedback, ticket opened by a tool or an agent with a maintainer's account), add the **`à décider`** label when opening it: it stays "to validate" (`statut: à valider`), without a branch, until a maintainer adds `validé` (`à décider` is then removed). To always require a separate validation: `auto-validate: never` input of the `tickets.yml` workflow. The branch type comes from the ticket's `type: …` label (`feat` by default), its name from the title (lowercase, no accents).

## On the developer machine

```bash
repowarden ticket 12                          # switch to ticket #12's branch
repowarden ticket nouveau "Add the cart"       # create a ticket (awaiting validation)
repowarden ticket                             # ticket of the current branch
```

- `repowarden ticket <n>` **takes the ticket** (assigned to you) and switches to its branch; creates it and links it to the ticket (`gh issue develop`) if it does not exist yet.
- `repowarden ticket nouveau --type <type>`: one of `feat`, `fix`, `docs`, `refactor`, `chore` (the `type: …` labels): when tracking is managed by repowarden, any other is refused, before anything is created.
- **Assigned tickets → local branches**: `repowarden tickets sync` creates the local branch of each ticket assigned to you, without changing your current branch. A ticket reassigned to someone else is flagged, its local branch kept. Never for a delivered ticket (`préprod`, `done`) or one in review whose branch is gone (PR merged). Setting `ticketSync = manual | auto | off`: `manual` by default, a `git pull` or a clone touches nothing; with `git config repowarden.ticketSync auto`, syncing also happens on every `git pull` or branch switch (at most every 15 min, only with `gh` logged in), never on clone.
- **Branch without a ticket**: `repowarden` warns (when arriving on the branch and in `git cc`), **never blocking**: not everyone works with tickets. If the project's tickets are managed by repowarden, it **offers to create one** (`git cc` creates and references it on "yes"); otherwise it shows how to silence it: `git config repowarden.skip tickets`.
- `git cc` references `Ticket : #12` on a `feat/12-…` branch.

## The rules

- **Automatic merge into `develop`**: a **ready** work PR (out of draft), whose ticket is validated, merges **on its own as a squash** as soon as its checks are green. Back to draft, the automatic merge is removed. It needs the [GitHub App](industrialisation.md#github-app-for-workflows): with the Actions token, the merge would trigger no workflow. The `develop` → `main` delivery is **never** merged automatically: it always waits for the human approval. Setting `autoMergeWork = false` (`.repowarden.conf`) to keep manual merges.
- **No PR without a ticket**: a PR references its ticket in its description (`Ticket : #12`), or its branch carries it (`feat/12-cart`). Otherwise, the ticket is **created automatically** from the PR, linked to its description, and "à valider".
- **Checks of the `ticket` verification** (for any contributor, agent or person): the PR references **only one ticket**; its branch carries the **ticket number** (`type/12-topic`); the ticket carries a **"Conception retenue"** (design) written by a maintainer before the code (`require-design` workflow input); no commit references another ticket.
- **No merge without a validated ticket**: the PR's `ticket` check fails until its ticket has the `validé` label. It passes as soon as the label is added, without re-running anything. The `tickets` job stays green while waiting: a red job means a real failure.
- **One ticket, one branch, and the ticket remembers it**: the branch created by the ticket is linked to it (*Development* panel). GitHub can only link a branch when creating it, and a deleted linked branch loses its name there: the bot therefore **writes the branch name on the ticket** ("Ticket branch" comment), when it is created as well as on the first push of a hand-made `type/12-…` branch. A second branch for the same ticket is registered and flagged.
- **`main` and `develop` are never red**: GitHub attaches a PR's checks to the commit of its source branch. A PR only leaves `develop` to deliver (`develop` → `main`), and `main` for a useful back-merge (`main` → `develop`). Any other PR leaving them is pointless: the CI flags it without failing, and it is closed with the way forward (to update a work branch: `git merge origin/develop` on that branch).
- Dependency bots, release PRs and `develop` → `main` deliveries do not need a ticket.
- The draft PR is opened by the Actions token, which does not trigger other workflows: CI runs on the next push, or when marked "Ready for review" (`ready_for_review` in the CI triggers, as in the project template).

!!! note "Why `Ticket : #12` and not `Closes #12`"
    `Closes #12` closes the ticket as soon as it is merged into the default branch, i.e. `develop`: it would be "done" before reaching production. Here, the release on `main` closes it.

## Setup

```bash
repowarden tickets init          # labels, template, workflow, existing tickets and branches
git add .github && git cc       # then a PR
repowarden proteger --checks "repowarden,ticket"   # "ticket" check required
```

On a repository that already has tickets, `tickets init` takes them over (re-runnable, nothing is done twice):

- open tickets **without a status**: those labelled `validé` or opened by a maintainer go to **backlog**, the others **to validate** (`--sans-validation-auto`: all to validate);
- **branches of open and merged PRs**: registered on the tickets they reference, to know which ticket handled which branch, even deleted;
- no mass branch creation: the branch is born when the ticket is taken (`repowarden ticket N`).

In `.github/workflows/release.yml`, tickets move to pre-production on each pre-release and to done on each release, or on a delivery to `main` without a new version (job written by `repowarden bots` with ticket tracking, with the App when it is set up; add it by hand to an existing `release.yml`):

```yaml
  tickets:
    needs: release
    if: needs.release.outputs.release_created == 'true' || needs.release.outputs.prerelease_created == 'true' || needs.release.outputs.delivered_without_version != ''
    uses: simdevWarden/repowarden/.github/workflows/tickets.yml@v4
    permissions: { contents: write, issues: write, pull-requests: write, statuses: write }
    with:
      tag: ${{ needs.release.outputs.tag_name || needs.release.outputs.prerelease_tag }}
      delivered-sha: ${{ needs.release.outputs.delivered_without_version }}
```

An existing `tickets.yml` is never overwritten: for the branch created on validation and the draft PR, add the `pull_request_review`, `issues` (`assigned`, `closed`) and `push` events to it, and the `contents: write` permission (see the template written by `repowarden tickets init`).

No key or token: everything goes through the Actions token. The workflow uses `pull_request_target` without ever fetching the PR's code: PRs from forks are handled safely.

Delivery opened by the release workflow (`release-auto`): with `delivery-workflow: true`, a `develop` → `main` PR opened by hand is closed, with the steps to follow; it would never get a deployment approval. Default `false`: delivering through a manual PR remains possible.

## Board

Statuses are labels: a [GitHub Project](https://docs.github.com/en/issues/planning-and-tracking-with-projects) in board view, grouped by label (or one column filtered per status), gives the backlog → done board. It is set up once, in GitHub's interface; the workflow does not touch it (personal-account Projects are not accessible to the Actions token).
