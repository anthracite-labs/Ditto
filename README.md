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

## Start a session

Arena does not auto-load repository instructions, so begin with:

> Read `.ecc/BOOTSTRAP.md`, initialize the Ditto engineering protocol, inspect
> project memory and the skill index, then work GitHub Issue #X. Load only
> skills relevant to that issue.

From the shell, `bash scripts/bootstrap.sh` prints the same briefing:
provenance, must-read files, the workflow index, and the verification command.

## Verify

```bash
bash scripts/verify.sh
```

The gate is deterministic and exits non-zero on failure. It checks that the
foundation files exist, that Markdown links resolve, that shell scripts parse
(and pass shellcheck when available), that required scripts are executable,
that ECC provenance is recorded, that no credential-shaped value is committed,
that the skill index and bootstrap references resolve, and that the AgentShield
static scan runs clean. GitHub Actions runs the same script on every push and
pull request, so verification does not depend on any one agent's honesty.

## Repository map

```text
AGENTS.md                     entry point for coding agents
.ecc/BOOTSTRAP.md             session protocol — read first
.ecc/rules/                   standing rules: engineering, testing, security, git
.ecc/skills/INDEX.md          workflow router (load 1–2 per task)
.ecc/skills/*.md              planning, research, tdd, debugging, code-review,
                              spec-review, security-review, verification,
                              project-memory, decisions
.ecc/roles/*.md               architect, security-reviewer, spec-reviewer
.ecc/VERSION                  adapter + upstream provenance (machine-readable)
.ecc/UPSTREAM.md              provenance, licence, curation policy, sync policy
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
scripts/sync-ecc.sh           upstream ECC inspection (never overwrites .ecc/)
.github/workflows/verify.yml  independent CI verification
```

## Ground rules

- No application stack, product requirement, database, auth scheme, hosting
  choice, or UI without an approved issue and an ADR.
- `scripts/verify.sh` must pass before commit; `.git/hooks/` is not used for
  enforcement.
- Work happens on session branches; `main` is protected by review. Arena does
  not merge its own PRs.

## Licence

Ditto's own content is © its authors. Adapted ECC material is © 2026 Affaan
Mustafa, MIT licensed; attribution is carried per file and recorded in
[`.ecc/UPSTREAM.md`](.ecc/UPSTREAM.md). AgentShield
(`ecc-agentshield`, MIT) is executed from npm and never vendored here.
