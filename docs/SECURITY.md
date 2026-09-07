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
| Engineering system | A weakened check that silently passes | Named negative tests plus positive controls; weakening a gate requires justification in review |
| Lifecycle | Untracked overrides or an unrelated/proposed ADR enabling a stack | Complete committed config validation and accepted, explicit stack metadata, even in standalone checks |
| Governance | Portable JSON mistaken for applied GitHub settings; optional or decoy CI jobs | Structural ruleset/CI contracts; human audit of live rules and bypass access in `docs/FOUNDATION.md` |

## Rules that are enforced automatically

`scripts/verify.sh` (run locally and by `.github/workflows/verify.yml`):

- no credential-shaped value in the working-tree files, including untracked work;
- no secret-looking `.env*` file committed;
- the reviewed ECC pin, full MIT notice, Ditto adapter identity and foundation
  source provenance remain intact;
- actual CI gate/self-test invocations and exact required job names are validated,
  with no skip/failure-suppression, shell-environment or checkout-ref overrides;
- lifecycle keys are complete and unambiguous; metadata in comments, fences or
  prose and unconfined ADR paths cannot authorize a stack;
- the ruleset has the intended policy structure and exactly two required CI
  contexts, with no bypass actors or repository-specific identifiers;
- the pinned AgentShield static invocation is checked when reachable, with
  zero-file results reported as SKIP/advisory, not PASS.

### Properties of the automated secrets sweep

Two properties are load-bearing and both are covered by committed negative
tests in `scripts/selftest.sh`:

1. **The detector cannot leak what it finds.** A finding is reported as
   `path:line [category]` only. Matched material never reaches stdout or
   stderr, so an accidentally committed credential is not echoed into CI logs
   by the check meant to catch it. Test: `secrets/redaction` asserts the gate
   fails *and* that the injected value is absent from combined output. Colons
   and newlines in filenames cannot break redaction; credential-shaped filenames
   are redacted too. The gate banner does not echo unvalidated version/config
   values, and AgentShield reports only normalized counters, never finding text.
2. **There are no exemptions at all.** No rule skips a line because it contains
   a word such as `example`, `todo`, or `sample`, and no rule skips a value
   because it "looks like a placeholder". Every match is a finding.

   A repeated-character value is caught, because a structurally simple value
   can be a real password — an all-x or all-zero assignment is a plausible
   credential, not evidence of a documentation example. Tests:
   `secrets/repeated-char-password`, `secrets/repeated-char-token`.

   Documentation should therefore avoid credential-shaped examples entirely.
   An empty value or an angle-bracket placeholder does not match the patterns,
   so it needs no exemption; tests `secrets/angle-bracket-not-credential-shaped`
   and `secrets/empty-value-not-credential-shaped` pin that behaviour.

   Tests `secrets/bypass-*` additionally assert that real-looking credentials
   are still caught on lines containing `example`, `todo`, `sample`,
   `placeholder`, and `n/a`.

Dotenv files are enforced rather than merely documented: `check_env_files`
fails if any `.env*` path exists at any depth, because `.gitignore` cannot
stop `git add -f`. A regular `.env.example` file is the only permitted template;
a symlink is not an example, and example contents still receive the secrets scan.
`config/project.env` is committed lifecycle data, not a dotenv file: it is never
sourced and must not contain credentials.

These checks are a floor, not a guarantee — a credential in an unrecognised
shape will pass. Human review remains the control for the rest.

The committed gate and test harness are executable repository code and require
review. Config and ADR inputs are parsed as data, never sourced or evaluated.
Verification uses `bash -n`, static ShellCheck, safe YAML/JSON loaders and the
pinned scanner in static mode. The self-test harness executes only its explicit
fixture mutations and the real gate in disposable copies. `curl` in the ECC
inspection helper is used only against `api.github.com`; no repository script
uses `sudo` or applies GitHub administrative settings.

## Rules that are enforced by review

- No secret in a commit, PR body, issue comment, or log line.
- Least privilege in CI: `contents: read` unless a job proves it needs more.
- Dependencies pinned, from `registry.npmjs.org` or `pypi.org` only.
- Any change to `.ecc/**`, `AGENTS.md`, `config/**`, `scripts/**` or CI is
  reviewed as executable policy, because an agent or runner will act on it.
- No direct pushes to main and no self-merge. Independent ChatGPT review is
  required before an authorized maintainer merges agent-authored work.
- No GitHub administrative settings are changed by a repository script. Live
  rules and bypass access are separate from committed portable policy; the
  zero-human-approval workflow does not platform-enforce ChatGPT review.
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

Malformed or incomplete scanner summaries are rejected rather than defaulted to
zero. The package/version pin is revalidated before execution even when the
AgentShield check runs alone. None of this makes a zero-file scan meaningful.

## Reporting a security problem

Open a private security report through GitHub's private vulnerability
reporting on this repository, or contact the maintainers directly. Do not open
a public issue for an unpatched exposure.

If a credential is ever committed, treat it as burned: **rotate it first**,
then remove it. Deleting a line does not remove it from history.
