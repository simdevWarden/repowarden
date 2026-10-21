# Security policy

## Supported versions

| Version | Supported |
|---|---|
| Latest major version (`v1`) | ✅ security fixes |
| Previous major versions | ❌ |

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private reporting:
*Security* tab → *Report a vulnerability*.

Include: affected version, reproduction scenario, estimated impact.

Target response times: acknowledgement within 3 business days, fix or action plan within 30 days.

## Verifying a release

Each release contains a source archive signed with [Sigstore](https://www.sigstore.dev) by the release workflow (no private key to manage):

```bash
TAG=v1.1.0
gh release download "$TAG" --repo simdevWarden/repowarden -p "repowarden-$TAG*"
cosign verify-blob "repowarden-$TAG.tar.gz" \
  --bundle "repowarden-$TAG.tar.gz.sigstore.json" \
  --certificate-identity-regexp '^https://github.com/simdevWarden/repowarden/\.github/workflows/release\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Each release also contains an **[SLSA](https://slsa.dev) level 3 provenance attestation** (`repowarden-vX.Y.Z.intoto.jsonl`): it attests that the archive was built by this repository's release workflow, from the tag's commit.

```bash
slsa-verifier verify-artifact "repowarden-$TAG.tar.gz" \
  --provenance-path "repowarden-$TAG.intoto.jsonl" \
  --source-uri github.com/simdevWarden/repowarden --source-branch main
```

(`--source-branch main`: releases are built by the workflow triggered on `main`, which then creates the tag.)

## What repowarden does for security

- Secret detection (gitleaks) in the hooks and in CI; gitleaks installed in CI at a **pinned version with a verified SHA-256 checksum**.
- GitHub Actions pinned by SHA, CI Python tools pinned by hash (`--require-hashes`), updated by Dependabot (pip lock files regenerated with the command from their header by the `verrous-pip` workflow, which needs the **Dependabot** secret `REPOWARDEN_APP_KEY`); workflows have no permissions by default.
- CodeQL analysis of the workflows, OpenSSF Scorecard assessment.
- No secrets used by the workflows other than `GITHUB_TOKEN` (read-only by default) and the optional release token.
- The hooks only run tools installed on the developer machine or declared by the project; nothing is downloaded at commit time.
