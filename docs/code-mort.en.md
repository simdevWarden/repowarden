# Dead code

Code is **dead** when it can be **proven** to have no effect on the program's behaviour. repowarden distinguishes three cases, which are not proven the same way:

| Category | Definition | Examples | Proof | repowarden |
|---|---|---|---|---|
| **Unreachable** | statements no execution path can reach | code after a `return`, `if (false)` | control-flow analysis | **proven**: blocking |
| **Unused in its scope** | declaration never referenced where it is visible | import, local variable, **private** parameter or member never read | file reference analysis | **proven**: blocking |
| **Unreferenced in the project** | externally visible element that nothing in the project uses | public method, export, file, dependency | call graph from the entry points | **candidate**: warning |

The first two cases are certain: the tool guesses nothing. The third one is not always, because code can be called **without a visible reference**:

- reflection and injection (Spring beans, `Class.forName`, `getattr`);
- calls from outside: a library's public API, HTTP routes, scheduled jobs;
- serialization (Jackson, JPA), templates, configuration, another language.

That is why a **candidate** never blocks by default: a human confirms.

## Only new dead code

repowarden only reports dead code **introduced** by the PR (lines added or changed since the base). An existing project is not flooded with its history: the debt stops growing, and you reduce it at your own pace.

## Tools, by language

| Language | Proven | Candidates |
|---|---|---|
| Java (Maven, Gradle) | PMD: unused imports, private fields, methods and variables | — (Spring and reflection make the analysis too uncertain) |
| TypeScript / JavaScript | `tsc`: unused variables, parameters, imports, unreachable code | [knip](https://knip.dev) if installed in the project: files, exports, dependencies |
| Python | ruff (F401, F811, F841), vulture at 100% confidence | vulture below 100% (the percentage is shown) |
| Go | staticcheck (U1000: unused unexported identifiers) | — |

In CI, the action installs PMD for a Java project (pinned version and checksum). Other tools are the project's own. A missing tool is reported without failing, even in strict mode: detection remains an aid.

## Partial analysis

When a language has several tools (Python: ruff and vulture; JavaScript: `tsc` and knip) and only one is installed, the analysis is **partial**: repowarden says so, with the missing installation ("Python: vulture not installed, partial dead code analysis (pip install vulture)"). And above all, with no finding in what was analysed, the closing message is no longer the green light "No new dead code", but "No new dead code in what was analysed: partial analysis, see above". No tool of the language at all: the "dead code not analysed" message remains, and also counts as a partial analysis.

## Usage

- **CI**: the `deadcode` check, included by default in the action (`checks:`).
- **Developer machine**: `repowarden code-mort [base]` analyses your branch like the CI: commits, pending changes and new files. Default base: `origin/main`; on a branch with no changes, nothing is analysed.

## Settings

```ini
[repowarden]
    deadcode = block               # default: proven blocks, candidates warn
    # deadcode = warn              # nothing blocks
    # deadcode = strict            # candidates block too
    deadcodeIgnore = src/generated/* legacy/*   # ignored paths
    # skip = deadcode              # disable the check
```

A one-off false positive can also be declared with the tool's annotation (`@SuppressWarnings("PMD.UnusedPrivateMethod")`, `# noqa: F401`, `// @ts-expect-error`…), visible in review.
