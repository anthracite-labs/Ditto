# ADR-0004: Sync the reviewed foundation without re-templating Ditto

**Date:** 2026-09-06
**Status:** accepted
**Deciders:** Ditto maintainers; implementation requested in Arena, independent ChatGPT review completed on 2026-09-07

## Context

Ditto's reviewed engineering foundation at
`5d9cc349d264f73e8da913da9d2cea664522237d` was the source of App-Factory.
App-Factory v0.1.0 subsequently hardened lifecycle configuration, accepted-stack
ADR validation, portable branch policy, initialization and negative tests.
Ditto can adopt that engineering work without becoming the master template or
losing its own product history. Its product remains explicitly undefined.

The [migration plan](../plans/2026-09-06-foundation-v0.1.0-sync.md) was recorded
before implementation. The pinned reusable source is
`anthracite-labs/App-Factory@ffe4382677c5237d2c86066c96742cf96a5f10fe`.

## Decision

Adopt the App-Factory v0.1.0 hardening into Ditto's own foundation. Track the
foundation version separately from the ECC/scanner records, and append the
foundation source provenance without replacing existing ECC provenance. ECC
remains `2.2.0` / `v2.2.0` /
`5eddf1a3ffd311423be2d4ba7d26f7209c91b033`; its MIT notice remains byte-identical.

Move the lifecycle guard's state from an environment-overridable script constant
to committed `config/project.env`. Both the full gate and the standalone stack
check validate the complete config and the same transition requirements. Ditto
starts in **discovery**, with `ALLOW_APP_STACK=0` and an empty `STACK_DECISION_ADR`.
Only an accepted, specifically marked application-stack ADR can later authorize
implementation. Comments, examples, duplicate state and unconfined paths cannot.
This ADR does **not** select an application stack or authorize that transition.

Keep the exact required CI jobs `Foundation gate` and `Independent checks`,
PR-only main changes and independent ChatGPT review/no self-merge. A portable
ruleset describes desired policy; no repository script applies administrative
settings. Keep Ditto's branch-creation protection in addition to the source's
required policy. Explain the live policy and its operational limitations in
[FOUNDATION.md](../FOUNDATION.md).

Keep the existing numbered ADRs, product/domain/architecture/roadmap documents,
Arena capability audit and all historical memory intact. Add current guidance
rather than replacing them with generic factory documents. Initialization is
identity-only and non-destructive; `--force` cannot regress lifecycle state.

## Alternatives considered

### Alternative: Replace Ditto with the current App-Factory template

- **Pros:** Minimal integration work; byte-identical master template.
- **Cons:** Erases Ditto history and context, resets its identity to a generic
  factory, and misrepresents the direction of provenance.
- **Why not:** This is an existing product repository, not a new template instance.

### Alternative: Keep the old environment override and copy only documentation

- **Pros:** Small diff and no new config to validate.
- **Cons:** A local environment can silently stand down the application guard;
  documentation cannot enforce an accepted ADR or consistent lifecycle state.
- **Why not:** It does not deliver the reviewed reusable hardening.

### Alternative: Import all upstream scripts without reviewing edge cases

- **Pros:** Easier future source diffs.
- **Cons:** Carries factory-only assumptions and misses complete standalone
  validation, exact structural CI policy, unusual-filename redaction and deep
  dotenv handling required by Ditto's safety contract.
- **Why not:** Preserve source intent and test coverage, not known bypasses.

## Consequences

### Positive

- Lifecycle progress is an explicit, reviewed config diff, not a gate edit.
- Version/provenance, ruleset and CI changes have machine-checked contracts and
  negative tests; all previous credential protections remain in force.
- Ditto retains its own identity, history and future product authority.

### Negative

- A few application-repository differences must be re-reviewed on each future
  foundation sync; this is not a one-command template replacement.
- Structural policy checks require Python/PyYAML, already provided in CI.
- The single shell gate and negative harness are larger than the usual file-size
  guideline: they intentionally retain the reviewed source's one-command,
  inspectable structure rather than adding an application test framework.
- Neither committed JSON nor zero GitHub human approvals enforce independent
  ChatGPT review. Bypass access and live policy remain administrative concerns.
- Credential scanning is heuristic, and AgentShield provides no coverage when
  it examines zero files. Application-specific tests must be added later.

### Follow-ups

- Independent ChatGPT review [completed successfully on 2026-09-07](https://github.com/anthracite-labs/Ditto/pull/4#pullrequestreview-5127176109).
  This foundation decision is accepted; any merge remains a maintainer action,
  not an Arena self-merge.
- An administrator may compare/audit live rules and bypass access as described
  in `docs/FOUNDATION.md`; the migration itself makes no admin changes.
- A product owner must define Ditto before architecture selection. No product,
  stack, hosting or UI decision is made by this foundation work.
