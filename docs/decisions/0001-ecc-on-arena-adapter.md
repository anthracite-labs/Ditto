# ADR-0001: Adopt an ECC-on-Arena adapter instead of native ECC

**Date:** 2026-09-06
**Status:** accepted
**Deciders:** Ditto maintainers (issue #2); implemented by Arena Agent Mode

## Context

Ditto wants ECC-grade engineering discipline (plan-first, research-first, TDD,
disciplined debugging, review, security review, deterministic verification,
durable memory) while the only executor available is Arena Agent Mode. The
capability audit (`ARENA_CAPABILITIES.md`, verified 2026-09-06) established
that Arena does not auto-load `AGENTS.md`, exposes no plugin marketplace, no
lifecycle hooks, no slash commands, and no subagent API — but does reliably
read and follow repository Markdown, run shell commands, and use `git`/`gh`.
Upstream ECC (`affaan-m/ECC` v2.2.0, MIT) is far larger than one session can
hold: 68 agents, 286 skills, 94 commands, 22 rule families.

## Decision

Ship a small, repository-owned **ECC-on-Arena adapter** under `.ecc/` —
bootstrap protocol, 4 standing rules, 10 on-demand workflows, 3 review
personas — with upstream provenance recorded in `.ecc/VERSION` and
`.ecc/UPSTREAM.md`, and load workflows selectively per task.

## Alternatives considered

### Alternative: Install the native ECC plugin (`ecc@ecc`)

- **Pros:** Full fidelity; upstream updates arrive for free; hooks and commands
  work as designed.
- **Cons:** Requires the Claude Code plugin harness and `~/.claude` state.
- **Why not:** Arena exposes no plugin marketplace and no `~/.claude`
  lifecycle. The install path does not exist in the only executor we have.

### Alternative: Vendor the whole ECC repository into Ditto

- **Pros:** Everything available offline; no upstream drift.
- **Cons:** Enormous context and maintenance burden; most of it is
  inapplicable (browser E2E, MCP defaults, 22 language families).
- **Why not:** Startup context is the scarcest resource in an agent loop. A
  286-skill library that must be navigated costs more than the discipline it
  provides, and wholesale copying obscures provenance rather than preserving it.

### Alternative: Write Ditto's own engineering conventions from scratch

- **Pros:** Perfectly tailored; no licence obligations.
- **Cons:** Reinvents solved problems; loses the battle-tested review ladders,
  TDD evidence rules, and security triggers ECC already encodes.
- **Why not:** Adaptation is cheaper and better-proven, and MIT terms are easy
  to satisfy with attribution.

## Consequences

### Positive

- A fresh Arena session can bootstrap from the repository plus one short
  instruction.
- Discipline is versioned, reviewable, and auditable in Git.
- Provenance and MIT obligations are explicit and machine-checked.
- Upstream changes can be adopted selectively rather than wholesale.

### Negative

- Adapted workflows drift from upstream; keeping them honest requires periodic
  review (`scripts/sync-ecc.sh` plus an ADR per upgrade).
- No automated enforcement of "load the right skill" — routing depends on the
  agent following `.ecc/BOOTSTRAP.md`.
- ECC features that need hooks or subagents are unavailable, and the adapter
  must keep saying so.

### Follow-ups

- Exercise the protocol on a real issue and record friction in
  `docs/MEMORY.md`.
- Decide whether AgentShield gates CI or stays advisory.
- Add a language rule family only once a stack exists.
