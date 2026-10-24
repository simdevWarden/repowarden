# Project map

An AI agent (or a person) taking over a project explores it file by file to understand "what does what and why": costly in context. repowarden already asks, right above each new function, for one or two lines saying what it does and why ([hooks](hooks.md)). The **map** gathers these "whys" into an index, with no LLM; only the tickets' design goes through `gh`, optionally.

```bash
repowarden carte        # (re)generates .repowarden/carte/carte.json
```

```text
✔ Map: 80 file(s), 395 function(s), 154 without a comment → .repowarden/carte/carte.json
```

## Contents

For each file of the repository (tracked, or new and not ignored, outside `repowarden.exclude`): its functions, their line and their **why**, the text of the comment lines right above the declaration (tool directives such as `# shellcheck disable=…` skipped). A function without a comment is listed with an empty why.

```json
{
  "fichiers": {
    "bin/outil": {
      "fonctions": [{ "ligne": 3, "nom": "main", "pourquoi": "Point d'entrée : lit les options" }],
      "tests": ["test/outil.bats"],
      "tickets": [12]
    }
  },
  "tickets": { "12": { "fichiers": ["bin/outil"] } },
  "version": 1
}
```

- **One detection only**: the one of the "functions without a comment" check, not a second parser.
- **First batch: shell** (`.sh`, `.bash`, or a script with a `sh`/`bash` shebang); other languages will follow, one family at a time.
- **Deterministic**: sorted keys, no date nor absolute path; two runs on the same repository give the same file.
- **Never versioned**: the `.repowarden/carte/` folder holds a `.gitignore` (`*`) that ignores the folder itself; nothing to add to the project's `.gitignore`.
- Requires `jq`.

## Querying

Read only the useful excerpt, without loading the whole JSON:

```bash
repowarden carte bin/garde          # the file's functions and their why
repowarden carte verifier_gh        # file, line, why of the function
repowarden carte bin/garde --json   # same excerpt, for tools (also: repowarden carte --json)
```

```text
verifier_gh  bin/garde:262
  Commande gh (mots $@, sans « gh ») lancée depuis $dir, …
```

A path is read from the current folder (`repowarden carte outil.sh` in `lib/`); a name that is neither a file nor a function of the map: message and exit code 1. **Missing or stale map** (a repository file or the git index newer than it): regenerated before answering.

## Linked tests

Before changing a file, know which tests cover it, to write them first then run them again. `repowarden carte <file>` gives them after its functions, with the command:

```text
Tests: test/garde.bats
  → bats test/garde.bats
```

A test (`*.bats`, first batch) is linked to a mapped file by:

- **naming**: same name without extension (`bin/garde` ↔ `test/garde.bats`);
- **cited path** in the test (`$BATS_TEST_DIRNAME/../ci/check.sh` cites `ci/check.sh`), with no other name character attached;
- **command** `repowarden <subcommand>` cited in the test → `bin/<subcommand>`.

A file without a test is reported ("No test found"); in the JSON, `"tests": []`. Tests are read even when they are in `repowarden.exclude`.

## Tickets

A file's why is also in its history: the tickets that changed it. The map reads them from **git only** (offline, never `gh`): `Ticket : #<n>` commit footers (squash headers included) and, for a merge, the merged `type/<n>-topic` branch (`Merge branch 'fix/40-x'`, `Merge pull request #5 from o/feat/12-x`). The `(#471)` number of a squash header is the PR's: it is not read.

```bash
repowarden carte '#12'          # files changed by ticket 12 (--json: {"ticket", "fichiers"})
repowarden carte bin/garde      # … then "Tickets: #317 #407 …"
```

Any file still present (outside `repowarden.exclude`) touched by a ticket enters the map, even without functions (doc, workflow); the root `tickets` key gives each ticket's files.

## Tickets' design

The decision behind a change is written in the "Conception retenue" comment of its ticket. The map attaches it to the files, so that an agent does not have to look for it:

```bash
repowarden carte '#12'          # files, then "Design:" and its summary
repowarden carte lib/a.sh       # … "#12 — <first line of the design>" per ticket
```

- **Same summary as the draft PR**: "Ce qui change" and "Hors périmètre" of the last "Conception retenue", then the "Ajout" / "Constat lié" comments; only maintainers' comments count.
- **Read with `gh`, cached** in `.repowarden/carte/conception/<n>.md` (empty for a ticket without design): a single call (`gh issue list --state all`, read-only), and only when tickets are missing from the cache; then no call at all. To refresh: delete that folder.
- **`gh` missing or not logged in**: warning, map without design, exit code 0.
- JSON: `"tickets": {"12": {"fichiers": [...], "conception": "…"}}`.
