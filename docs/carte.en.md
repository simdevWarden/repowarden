# Project map

An AI agent (or a person) taking over a project explores it file by file to understand "what does what and why": costly in context. repowarden already asks, right above each new function, for one or two lines saying what it does and why ([hooks](hooks.md)). The **map** gathers these "whys" into an index, with no LLM and no network.

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
      "fonctions": [{ "ligne": 3, "nom": "main", "pourquoi": "Point d'entrée : lit les options" }]
    }
  },
  "version": 1
}
```

- **One detection only**: the one of the "functions without a comment" check, not a second parser.
- **First batch: shell** (`.sh`, `.bash`, or a script with a `sh`/`bash` shebang); other languages will follow, one family at a time.
- **Deterministic**: sorted keys, no date nor absolute path; two runs on the same repository give the same file.
- **Never versioned**: the `.repowarden/carte/` folder holds a `.gitignore` (`*`) that ignores the folder itself; nothing to add to the project's `.gitignore`.
- Requires `jq`.
