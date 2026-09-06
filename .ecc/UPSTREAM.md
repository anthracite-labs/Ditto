# ECC Upstream Provenance

This directory is **not** ECC. It is a curated **ECC-on-Arena adapter**: a small
set of engineering rules, on-demand workflows, and review personas adapted from
the public [Everything Claude Code (ECC)](https://github.com/affaan-m/ECC)
project so that Arena Agent Mode can follow ECC engineering discipline without
any native ECC runtime.

Machine-readable provenance lives in [VERSION](VERSION). This file is the
human-readable record and the licence obligation.

## What was used

| Field | Value |
| :-- | :-- |
| Upstream project | Everything Claude Code (ECC), `affaan-m/ECC` |
| Upstream licence | MIT — `Copyright (c) 2026 Affaan Mustafa` |
| Pinned upstream version | `2.2.0` (release tag `v2.2.0`) |
| Pinned upstream commit | `5eddf1a3ffd311423be2d4ba7d26f7209c91b033` |
| npm distribution | `ecc-universal@2.2.0` |
| Upstream `main` at review time | `e04ea0b9cc8248686edf5ac751cadff550e162b8` (`VERSION` = `2.2.1`, unreleased) |
| Reviewed on | 2026-09-06, via GitHub API against primary upstream files |
| Security scanner | `ecc-agentshield@1.4.0` (MIT, `affaan-m/agentshield`) |

Upstream scale at review time: 68 agents, 286 `SKILL.md` files, 94 command
shims, 22 rule families. This adapter ships **10 workflows, 4 rule files and 3
personas** — roughly 1% of the upstream library. That ratio is deliberate; see
"Curation policy" below.

## What each local file is adapted from

| Local file | Primary upstream source | Adaptation |
| :-- | :-- | :-- |
| `.ecc/rules/engineering.md` | `rules/common/development-workflow.md`, `rules/common/code-review.md`, `rules/common/patterns.md`, `rules/common/coding-style.md` | Research-first and plan-first steps kept; agent delegation replaced with role modes and on-demand Markdown loading. |
| `.ecc/rules/testing.md` | `rules/common/testing.md`, `skills/tdd-workflow/SKILL.md` | RED/GREEN/IMPROVE cycle and 80% target kept; Playwright E2E marked unavailable in Arena. |
| `.ecc/rules/security.md` | `rules/common/security.md`, `skills/security-review/SKILL.md`, `the-security-guide.md` | Mandatory pre-commit checklist kept; enforcement moved to `scripts/verify.sh` + CI. |
| `.ecc/rules/git.md` | `rules/common/git-workflow.md` | Conventional commits kept; PR steps extended with ChatGPT review and CI status. |
| `.ecc/skills/planning.md` | `commands/plan.md`, `skills/plan-canvas/SKILL.md` | Plan-before-code gate kept; "wait for user CONFIRM" reframed as plan-then-proceed with an explicit plan record. |
| `.ecc/skills/research.md` | `skills/search-first/SKILL.md` | Tool-availability preflight kept, narrowed to Arena's egress allowlist. |
| `.ecc/skills/tdd.md` | `skills/tdd-workflow/SKILL.md` | RED/GREEN/IMPROVE, runner detection, evidence mapping kept; package-manager matrix trimmed. |
| `.ecc/skills/debugging.md` | `skills/agent-introspection-debugging/SKILL.md` | Four-phase capture → diagnose → contain → report loop kept. |
| `.ecc/skills/code-review.md` | `rules/common/code-review.md`, `commands/review-pr.md` | Severity ladder (CRITICAL/HIGH/MEDIUM/LOW) and confidence rule kept. |
| `.ecc/skills/spec-review.md` | `commands/review-pr.md`, `skills/santa-method/SKILL.md` | Dual independent review reframed as sequential ChatGPT + Arena passes (no parallel subagents in Arena). |
| `.ecc/skills/security-review.md` | `skills/security-review/SKILL.md`, `rules/common/security.md` | Trigger list and severity gate kept; scanner step pinned to AgentShield. |
| `.ecc/skills/verification.md` | `skills/verification-loop/SKILL.md` | Six-phase loop kept and bound to `scripts/verify.sh` instead of ad-hoc commands. |
| `.ecc/skills/project-memory.md` | `skills/unified-memory/SKILL.md`, `commands/update-codemaps.md` | Durable-memory intent kept; the ECC Memory Vault runtime is replaced by Git-tracked Markdown. |
| `.ecc/skills/decisions.md` | `skills/architecture-decision-records/SKILL.md` | Nygard ADR format kept verbatim in shape; stored under `docs/decisions/`. |
| `.ecc/roles/*.md` | `agents/planner`, `agents/architect`, `agents/security-reviewer`, `rules/common/agents.md` | Personas converted to single-agent role modes. |
| `scripts/verify.sh` | `skills/verification-loop/SKILL.md` | Phase list implemented as a deterministic, exit-code-bearing shell gate. |

## Licence obligation

Upstream ECC is MIT licensed. MIT requires the copyright notice **and** the
permission notice to be included in copies or substantial portions of the
software, so the full upstream notice is committed in this repository at
[`.ecc/LICENSE-ECC`](LICENSE-ECC) rather than left behind an external link.
That file is a byte-exact copy of upstream `LICENSE` at tag `v2.2.0`
(sha256 `326146379f01bb137c0a5d3c54770c1aa31076705c8b88a7f6b26a460f6221b2`),
and `scripts/verify.sh` (check `provenance`) fails if it is missing, altered,
or missing any of the copyright, permission, or warranty text.

The obligation is further satisfied by:

1. this file recording upstream copyright and licence;
2. per-file `Adapted from ECC v2.2.0` attribution headers on every adapted
   workflow, rule, and persona (enforced by the `attribution` check).

AgentShield is a separate MIT project (`affaan-m/agentshield`); it is executed
as a version-pinned `npx` invocation and never vendored into this repository,
so no copy of its licence text is distributed here.

## Curation policy

Deliberately **not** ported, with reasons:

| Upstream capability | Status here | Why |
| :-- | :-- | :-- |
| Claude Code plugin manifest (`ecc@ecc`) | Omitted | Arena has no plugin marketplace or harness installer. |
| `hooks/hooks.json` lifecycle hooks | Omitted | Arena exposes no `PreToolUse`/`PostToolUse`/`SessionStart` events. |
| 94 slash commands | Omitted | No slash-command dispatcher in Arena; workflows are read as files. |
| Real subagents / parallel `Task` delegation | Omitted | No native subagent API; replaced by sequential role modes. |
| MCP server defaults | Omitted | Arena's egress allowlist covers GitHub/npm/PyPI only. |
| Language rule families (22) | Omitted | No implementation language chosen yet; adding them would be a stack decision. |
| Browser E2E (`e2e-testing`, `browser-qa`) | Omitted | Playwright browser CDN is blocked by the Arena egress firewall. |
| Memory Vault CLI / MCP (`ecc memory`) | Omitted | Requires the `ecc-universal` runtime on `PATH`; Git-tracked Markdown is the durable layer here. |
| Codex/Cursor/Gemini/Kiro harness adapters | Omitted | Out of scope; Ditto targets Arena. |

## Update / sync strategy

`scripts/sync-ecc.sh` is **inspection-only by default**: it reports the pinned
version, the current upstream release, and the upstream files behind each local
adaptation. It never writes to `.ecc/`.

To adopt an upstream change:

1. `bash scripts/sync-ecc.sh` — see whether upstream moved.
2. `bash scripts/sync-ecc.sh --fetch` — download upstream sources to a temp dir
   (outside the repo) and diff them against the local adaptations.
3. Edit the affected `.ecc/` files by hand, keeping the Arena-specific parts.
4. Update `UPSTREAM_VERSION`, `UPSTREAM_TAG`, `UPSTREAM_COMMIT` and
   `UPSTREAM_REVIEWED_AT` in [VERSION](VERSION).
5. Record the upgrade as an ADR in `docs/decisions/`.
6. `bash scripts/verify.sh` must pass before the change is committed.

Local Arena adaptations always win over upstream text on conflict: where
upstream assumes hooks, subagents, or a browser, this adapter must keep the
Arena-safe behaviour.

## 2026-09-06 — App-Factory foundation sync (not an ECC upgrade)

Ditto retains the reviewed ECC provenance above, including its original adapter
identity, release pin, upstream-main observation and MIT notice. The reusable
engineering hardening is synchronized separately from
[anthracite-labs/App-Factory](https://github.com/anthracite-labs/App-Factory)
at source commit `ffe4382677c5237d2c86066c96742cf96a5f10fe`, foundation
version `0.1.0`. This does not change the ECC or AgentShield pins.

`FOUNDATION_SOURCE_REPO`, `FOUNDATION_SOURCE_COMMIT` and `FOUNDATION_SYNCED_AT`
are appended to [VERSION](VERSION); the foundation version lives in the separate
root `FOUNDATION_VERSION` file. App-Factory was itself derived from Ditto at
`5d9cc349d264f73e8da913da9d2cea664522237d`. This sync brings reusable hardening
back into the independent Ditto repository; it does not replace Ditto history
with the master template or copy the template's derivation fields as our identity.

Ported material includes lifecycle/ADR validation, initialization safety,
foundation/provenance checks, CI/ruleset contracts and negative tests. Ditto's
application-repository adaptations and additional regression hardening are
recorded in [docs/FOUNDATION.md](../docs/FOUNDATION.md) and
[ADR-0004](../docs/decisions/0004-foundation-lifecycle-sync.md). No upstream ECC
skills were added, removed or upgraded as part of this foundation sync.
