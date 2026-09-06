# Ditto

**Ditto is a product name only.** No product definition, framework, database,
or UI has been chosen yet — deliberately. This repository currently contains
the engineering system that will govern how Ditto gets built.

## What is here

An **ECC-on-Arena adapter**: a curated, repository-owned set of engineering
rules, on-demand workflows, and review personas adapted from
[Everything Claude Code (ECC)](https://github.com/affaan-m/ECC) v2.2.0 (MIT)
so that Arena Agent Mode can work with ECC discipline despite having no plugin
runtime, slash commands, lifecycle hooks, or subagents.

Operating model:

| Layer | Role |
| :-- | :-- |
| **ECC (repository-owned)** | Engineering discipline: rules, workflows, personas |
| **Arena Agent Mode** | The developer: reads the repo, writes code, runs commands |
| **GitHub** | Durable source of truth: issues, commits, PRs, CI |
| **ChatGPT** | Independent planning and PR review over the real diff |

This is an **adaptation, not native ECC** and not a claim of plugin
compatibility. See [`.ecc/UPSTREAM.md`](.ecc/UPSTREAM.md) for provenance,
licence obligations, what was deliberately omitted, and the update policy.

## Foundation and lifecycle

Ditto's engineering foundation is aligned with **App-Factory v0.1.0**, pinned to
`ffe4382677c5237d2c86066c96742cf96a5f10fe`. This is a foundation sync, **not an ECC
upgrade**: ECC remains `2.2.0` / `v2.2.0` /
`5eddf1a3ffd311423be2d4ba7d26f7209c91b033`.

[`config/project.env`](config/project.env) records **discovery**,
`ALLOW_APP_STACK=0`, and an empty stack ADR. No product or architecture selection
is implied. Ditto keeps its own history, product/domain/roadmap content, memory,
existing ADRs and Arena capability audit. See
[the foundation guide](docs/FOUNDATION.md) for the source record, accepted-stack
transition contract, tooling and live-governance limitations.

## Start a session

Arena does not auto-load repository instructions, so begin with:

> Read `.ecc/BOOTSTRAP.md`, initialize the Ditto engineering protocol, inspect
> project memory and the skill index, then work GitHub Issue #X. Load only
> skills relevant to that issue.

From the shell, `bash scripts/bootstrap.sh` prints the same briefing:
foundation/lifecycle state, provenance, must-read files, the workflow index,
and both verification commands.

## Verify

```bash
bash scripts/verify.sh
```

The gate is deterministic and exits non-zero on failure. It checks that the
foundation files exist, that Markdown links resolve, that shell scripts parse
(and pass shellcheck when available), that required scripts are executable,
that ECC provenance and the committed upstream MIT notice are intact, that no
credential-shaped value or dotenv file is committed, and that the skill index
and bootstrap references resolve. It also validates foundation provenance,
complete lifecycle state, accepted application-stack metadata, portable ruleset
structure and actual CI wiring. Python 3 and PyYAML are required for structural
CI checks; [tooling guidance](docs/FOUNDATION.md#verification-and-tooling) explains
local setup and CI's dependencies. Findings are reported as `path:line
[category]` with matched material redacted, so the detector cannot leak a
credential into CI logs.

```bash
bash scripts/selftest.sh
```

A green gate means nothing unless it can go red, so the negative tests are
committed too: they inject faults into a throwaway copy of the repository and
assert the intended named failure and exit status for each one. Positive cases
also prove that valid transitions and safe identity-only initialization work.
GitHub Actions runs both scripts on every main push and pull request, so
verification does not depend on any one agent's honesty.

## Repository map

```text
AGENTS.md                     entry point for coding agents
FOUNDATION_VERSION            reusable foundation release, separate from ECC
config/project.env            Ditto identity and committed lifecycle state
config/main-ruleset.json       portable desired policy, not live admin state
.ecc/BOOTSTRAP.md             session protocol — read first
.ecc/rules/                   standing rules: engineering, testing, security, git
.ecc/skills/INDEX.md          workflow router (load 1–2 per task)
.ecc/skills/*.md              planning, research, tdd, debugging, code-review,
                              spec-review, security-review, verification,
                              project-memory, decisions
.ecc/roles/*.md               architect, security-reviewer, spec-reviewer
.ecc/VERSION                  adapter + upstream provenance (machine-readable)
.ecc/UPSTREAM.md              provenance, licence, curation policy, sync policy
docs/FOUNDATION.md            source sync, lifecycle and governance guide
docs/PRODUCT.md               product placeholder — intentionally undefined
docs/ARCHITECTURE.md          current architecture (engineering system only)
docs/DOMAIN.md                domain vocabulary placeholder
docs/ROADMAP.md               roadmap placeholder
docs/SECURITY.md              security policy for this repository
docs/MEMORY.md                append-only project memory
docs/decisions/               architecture decision records
docs/codemaps/                code maps (empty until application code exists)
scripts/verify.sh             authoritative verification gate
scripts/bootstrap.sh          session briefing
scripts/init-project.sh       safe identity-only helper (normally a no-op)
scripts/selftest.sh            positive/negative guard and safety regressions
scripts/sync-ecc.sh           upstream ECC inspection (never overwrites .ecc/)
.github/workflows/verify.yml  independent CI verification
```

## Ground rules

- No application stack, product requirement, database, auth scheme, hosting
  choice, or UI without an approved issue and an ADR.
- `scripts/verify.sh` must pass before commit; `.git/hooks/` is not used for
  enforcement.
- Work happens only on the Arena session branch. **Never push directly to main
  or merge your own PR.** Leave it open for independent ChatGPT review.
- The live **Main** ruleset was verified active during this sync, requiring
  exactly **Foundation gate** and **Independent checks**, PRs, resolved review
  threads and strict status checks. The portable payload preserves that intent;
  this PR does not change live settings. Zero mandatory human approvals and
  reported bypass capability still require the explicit no-self-merge/review
  discipline and an administrator audit; see `docs/FOUNDATION.md`. Historical
  "protection pending" observations in the roadmap/memory are retained.

## Licence

Ditto's own content is © its authors. Adapted ECC material is © 2026 Affaan
Mustafa, MIT licensed; attribution is carried per file and recorded in
[`.ecc/UPSTREAM.md`](.ecc/UPSTREAM.md). AgentShield
(`ecc-agentshield`, MIT) is executed from npm and never vendored here.
