# Human approval

repowarden automates what is **mechanical and verifiable**:
- formatting;
- checking a message, a branch name or a PR target;
- computing a version, writing a changelog, creating a tag;
- building and signing a package.

These actions always produce the same result for the same input, and each one is traceable (CI logs, provenance attestations).

What requires **judgment** stays human:
- does this code do what we want?
- is this the right time to deliver?
- can we publish?

The risk is not the machine. It is human approval that is too light. This page describes how to make it mandatory.

## Decision points

| Decision | GitHub mechanism | repowarden |
|---|---|---|
| Review code before it gets in | required approvals; approval dismissed by a new commit; the last pusher cannot approve their own push (except in a solo repository: a single person with write access, no rule requires another person) | `repowarden proteger --relecteurs N` |
| Have sensitive areas reviewed by their owners | `CODEOWNERS` file + required code owner review | `repowarden proteger --codeowners` |
| Decide to publish | deployment environment: the job waits for approval from a designated person | `repowarden proteger --environnement production` |
| Decide to deliver (`develop` flow) | one **"Approve and deploy"** click on the `production` environment (notification, mobile app, run page); the GitHub App then merges the `develop` → `main` delivery PR. `main` requires this successful deployment: nothing enters it without this approval. **Or, if the project chooses so, automatic delivery**: human validation is merging each ticket; the GitHub App merges the delivery as soon as the checks required on `main` are green ([comparison of both modes](releases.md#approved-or-automatic-delivery)) | `tag` mode, `deliveryApproval = deployment` (default; `review`: PR review instead; `auto`: automatic delivery, `delivery-auto: true` input) |
| Keep control over the release PR (`pr` mode) | human merge | `release-auto` with `merge-auto: false` |

With a required review, the release PR is never merged by the bot. The bot prepares it and has CI validate it, then it waits for human approval. Merging it publishes the release.

## Setup

Settings versioned in `.repowarden.conf`, applied by `repowarden proteger` (can be re-run):

```ini
[repowarden]
    requiredReviews = 1              # approvals per PR
    codeOwnerReview = true           # CODEOWNERS review on their files
    unattributedApproval = false     # extra approval for unattributed changes (default false)
    deliveryApproval = deployment    # delivery validated by "Approve and deploy" (review: PR review; auto: automatic)
    environment = production         # deployments subject to approval
    environmentReviewers = alice @acme/release  # accounts or teams; default: the current gh user
```

`unattributedApproval` defaults to `false` and `proteger` always sets it explicitly. Otherwise GitHub turns it on: a PR opened by an app (delivery PR, ticket draft PR, opened by the Actions token) would then wait for a human approval, even with no approval required. Human validation of a delivery already goes through `requiredReviews` on `main`.

```text title=".github/CODEOWNERS"
# One pattern per line; the last matching rule wins
*                  @equipe-dev
# Workflows and protection
/.github/          @equipe-plateforme
# Build and dependencies
/pom.xml           @equipe-plateforme
/package.json      @equipe-plateforme
/src/**/security/  @equipe-securite
```

Then, in the workflows, each publishing job declares the environment:

```yaml
  publier:
    needs: release
    if: needs.release.outputs.release_created == 'true'
    environment: production   # waits for approval before running
```

The environment only accepts deployments from protected branches and `v*` tags: a working branch cannot publish.

## Where to click

Everything else is automatic. Here is each human step of the cycle, with the GitHub button and the equivalent command.

| Step | When | Where | Command |
|---|---|---|---|
| Validate a ticket | ticket opened by someone other than a maintainer | ticket → *Labels* → `validé` (set automatically when a maintainer opens the ticket) | `gh issue edit N --add-label validé` |
| Write the design | before the code | maintainer comment on the ticket containing "Conception retenue" | `gh issue comment N --body-file conception.md` |
| Take the PR out of draft | work done | bottom of the PR → **Ready for review**; it merges itself (squash) once CI is green | `gh pr ready N` |
| Approve a review | if `requiredReviews ≥ 1` | PR → *Files changed* → **Review changes** → *Approve* → **Submit review** | `gh pr review N --approve` |
| Deliver to production | `develop` flow, every delivery | **Approve and deploy**, see below | see below |
| Deliver an urgent fix | without waiting for the window | `urgent` label (create it if missing) on the `fix/…` PR before it is merged | `gh pr edit N --add-label urgent` |
| Merge the release PR | `pr` mode with `merge-auto: false` | "release x.y.z" PR → **Merge pull request** | `gh pr merge N --merge` |

### Approve and deploy, step by step

1. **Does the request exist?** It is created by the `release` workflow: every Friday at 7:00 (`delivery-schedule`), when an `urgent` PR is merged, or by hand:
   *Actions → release → **Run workflow** → branch `develop`*, or `gh workflow run release.yml --ref develop`.
2. **Find the button** (about a minute later, when the `release / livraison` job is *Waiting*):
   - run page (*Actions* → latest **release** run): yellow banner "*production needs approval*" → **Review deployments** → tick `production` → **Approve and deploy**;
   - or the GitHub notification (bell, "Deployment review requested" email, mobile app).
3. The GitHub App then merges the delivery PR as soon as checks are green; tag and release follow.

### Pitfalls

- **Delivery PR opened by hand** (`develop` → `main`): it stays blocked on "*Missing successful active production deployment*", because no approval request is created for it. Run the `release` workflow (step 1): it opens its own PR, frozen on `livraison/vX.Y.Z`, and closes the other one.
- **"Approve" on the delivery PR** (*Review changes*): that is a code review, it unblocks nothing. Only **Approve and deploy**, on the run page, creates the required deployment.
- **An approval is for one commit**: anything merged into `develop` after the approval goes out with the next delivery, with its own approval.
- **"Awaiting requested review"** on a delivery PR: only a review request, it does not block the merge when no approval is required.
- **Forgotten pending request**: a new request (manual or scheduled) replaces it; no need to approve it, it carries an outdated state.

## Solo project

GitHub does not allow approving your own PR, and `repowarden proteger` grants **no exception**, not even to the administrator: with `requiredReviews = 1` and a single developer, no merge would be possible. For a solo project, the recommended settings:
- `requiredReviews = 0`: CI is the authority on form;
- `environment = production` with yourself as approver: each publication requires a deliberate click;
- no single-person `.github/CODEOWNERS`: without `codeOwnerReview`, it only requests that person's review on every PR, without requiring anything.

## Who gets notified

Recipients are designated by **GitHub account or team**, never by email address: a public repository would expose the addresses, and Git history would keep them forever. GitHub then notifies each person according to their preferences (email, mobile, web).

| Who | Where | Example |
|---|---|---|
| Reviewers, per code area | `.github/CODEOWNERS` | `/.github/  @acme/platform` |
| Release approvers | `environmentReviewers` | `alice @acme/release` |
| Team channel (optional) | `REPOWARDEN_WEBHOOK` secret | Slack, Teams, Discord, Mattermost… |

A team (`@organisation/team`) is managed in GitHub: people joining or leaving change no file.

### Team channel

The release workflow can post to a channel: release published, release PR waiting for approval, failure. The incoming webhook address is a **secret**, never stored in the repository:

```bash
gh secret set REPOWARDEN_WEBHOOK      # address pasted with masked input
```

```yaml
jobs:
  release:
    uses: simdevWarden/repowarden/.github/workflows/release-auto.yml@v4
    secrets:
      webhook: ${{ secrets.REPOWARDEN_WEBHOOK }}
    with:
      notify: release attente echec   # default: all three
```

The format follows the platform recognised from the address (Slack, Discord, Microsoft Teams; otherwise `{"text"}` for Mattermost, Rocket.Chat…) and the message uses the project's language. A failed delivery is reported but never interrupts a release.

## Traceability and emergency stop

- Every merge, approval, deployment and bypass is recorded (PR history, *Environments* tab, audit log).
- `v*` tags can only be created or deleted by the workflows (ruleset "repowarden (tags)"), and `vX.Y.Z` version tags are never moved (ruleset "repowarden (tags de version)"); only the major tag (`v4`) stays movable, moved on every release (see [Versions and releases](releases.md)); each published package carries a verifiable provenance attestation.
- Suspend automatic releases: *Actions → release → Disable workflow*.
