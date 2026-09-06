# Security Policy

This repository contains no application, no user data, and no deployed
service. Its real attack surface is **an AI agent that reads and executes
repository content**, plus the CI that runs on every pull request. This policy
covers exactly that.

## Threat model

| Asset | Threat | Control |
| :-- | :-- | :-- |
| Agent behaviour | Prompt injection via issue bodies, fetched pages, or plan files | Instruction files treat external content as data; `.ecc/rules/security.md` requires reporting, never obeying |
| Credentials | Token committed to Git, or leaked into logs/PR bodies | `scripts/verify.sh` secrets check (CI-enforced); no real credential is ever needed locally |
| Supply chain | Malicious or typosquatted dependency; floating CI action tag | Pinned versions; allowlisted registries; `contents: read` CI permissions |
| CI runner | Workflow that executes untrusted input, or needs excess scope | Minimal permissions; no secrets required by the verify workflow |
| Engineering system | A weakened check that silently passes | Checks fail closed; weakening a gate requires justification in review |

## Rules that are enforced automatically

`scripts/verify.sh` (run locally and by `.github/workflows/verify.yml`):

- no credential-shaped value in any tracked file;
- no secret-looking `.env*` file committed;
- ECC provenance present, so adapted material stays attributable;
- the CI workflow is wired to the gate and cannot be silently decoupled;
- the AgentShield static scan runs clean when the registry is reachable.

### Known weakness in the automated secrets sweep

`check_secrets` skips a matching line when that line also contains a common
placeholder word (`example`, `sample`, `dummy`, `fake`, `redacted`,
`placeholder`, `none`, `undefined`, `todo`, `n/a`, `xxx`, `your-`, `<`, `>`).
A genuine credential committed on a line that happens to contain one of those
words would be missed. The sweep is a floor, not a guarantee: it exists to
catch the common accident, and human review remains the control for the rest.
Narrowing this allowlist is a Stage 1 item.

Nothing in `scripts/` executes repository content. Verification parses
(`bash -n`), lints statically (shellcheck), parses YAML with `safe_load`, and
runs the pinned scanner in static mode. `curl` is used only against
`api.github.com`. No script uses `sudo`.

## Rules that are enforced by review

- No secret in a commit, PR body, issue comment, or log line.
- Least privilege in CI: `contents: read` unless a job proves it needs more.
- Dependencies pinned, from `registry.npmjs.org` or `pypi.org` only.
- Any change to `.ecc/**` or `AGENTS.md` is reviewed as executable code,
  because an agent will act on it.
- Mandatory security review triggers are listed in
  `.ecc/rules/security.md`; the procedure is `.ecc/skills/security-review.md`.

## Scanner

AgentShield (`ecc-agentshield@1.4.0`, MIT,
[`affaan-m/agentshield`](https://github.com/affaan-m/agentshield)) is executed
from npm in **static mode only**:

```bash
npx -y ecc-agentshield@1.4.0 scan --format json
```

The deep modes (`--injection`, `--sandbox`, `--taint`, `--deep`) actively
execute or probe configuration and are never run automatically. If the
scanner cannot be reached, the check is reported as skipped — never as passed.

## Reporting a security problem

Open a private security report through GitHub's private vulnerability
reporting on this repository, or contact the maintainers directly. Do not open
a public issue for an unpatched exposure.

If a credential is ever committed, treat it as burned: **rotate it first**,
then remove it. Deleting a line does not remove it from history.
