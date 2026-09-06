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

### Properties of the automated secrets sweep

Two properties are load-bearing and both are covered by committed negative
tests in `scripts/selftest.sh`:

1. **The detector cannot leak what it finds.** A finding is reported as
   `path:line [category]` only. Matched material never reaches stdout or
   stderr, so an accidentally committed credential is not echoed into CI logs
   by the check meant to catch it. Test: `secrets/redaction` asserts the gate
   fails *and* that the injected value is absent from combined output.
2. **There is no whole-line bypass.** No rule skips a line because it contains
   a word such as `example`, `todo`, or `sample`. Exemptions are
   value-specific and structural only: a value made of one repeated
   alphanumeric character (`xxxxxxxx…`), or an angle-bracket placeholder
   (`<your-token-here>`). Tests: `secrets/bypass-*` assert real-looking
   credentials are still caught on lines containing those words.

Dotenv files are enforced rather than merely documented: `check_env_files`
fails if any `.env` or `.env.*` exists in the tree, because `.gitignore` cannot
stop `git add -f`. `.env.example` is the only permitted template.

These checks are a floor, not a guarantee — a credential in an unrecognised
shape will pass. Human review remains the control for the rest.

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
execute or probe configuration and are never run automatically.

**AgentShield is advisory in this repository, not a security gate.** It targets
Claude Code configuration surfaces (`.claude/`, hooks, MCP config), and this
Arena adapter has none, so it scans zero files. `scripts/verify.sh` therefore
reports it as `SKIP` rather than `PASS` whenever `filesScanned == 0` — a scan
that examined nothing proves nothing, and reporting it as a pass would
advertise coverage that does not exist. The credential controls that actually
apply here are `check_secrets` and `check_env_files`, described above.

## Reporting a security problem

Open a private security report through GitHub's private vulnerability
reporting on this repository, or contact the maintainers directly. Do not open
a public issue for an unpatched exposure.

If a credential is ever committed, treat it as burned: **rotate it first**,
then remove it. Deleting a line does not remove it from history.
