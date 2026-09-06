<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) —
     skills/architecture-decision-records/SKILL.md (Nygard ADR format).
     See .ecc/UPSTREAM.md. -->

# Decisions (ADR)

Decisions that are not written down get re-litigated, or worse, silently
reversed. An ADR costs five minutes and saves a future session from undoing
your reasoning.

## When to load

- A real trade-off was chosen over at least one viable alternative.
- A constraint was accepted ("we cannot do E2E in Arena, so…").
- Someone will plausibly ask "why did we do X instead of Y?".
- A foundation-level choice was made: tooling, layout, verification strategy,
  upstream pinning.

Do not write an ADR for reversible trivia, naming, or anything with no
rejected alternative.

## Steps

1. Find the next number: `ls docs/decisions/`.
2. Copy `docs/decisions/0000-template.md` to
   `docs/decisions/NNNN-<kebab-title>.md`.
3. Fill every section — including the alternatives you rejected and *why*.
4. Add the ADR to the index table in `docs/decisions/README.md`.
5. Link it from the PR body and from `docs/MEMORY.md`.
6. Never edit an accepted ADR to change the decision. Supersede it: new ADR,
   status `superseded by ADR-NNNN` on the old one.

## Format

```markdown
# ADR-NNNN: <Decision title>

**Date:** YYYY-MM-DD
**Status:** proposed | accepted | superseded by ADR-NNNN
**Deciders:** <who/what decided>

## Context
<The situation, constraints, and forces. 2-5 sentences.>

## Decision
<The change, stated plainly. 1-3 sentences.>

## Alternatives considered
### Alternative: <name>
- **Pros:** …
- **Cons:** …
- **Why not:** <the specific reason>

## Consequences
### Positive
- …
### Negative
- …
### Follow-ups
- …
```

## Quality bar

- **Context is factual.** Cite the evidence: a command output, a verified
  capability, an upstream ref — not an impression.
- **Alternatives are real.** An ADR with one strawman alternative records a
  preference, not a decision.
- **Consequences include the costs.** If an ADR has no downsides, it was not a
  trade-off.
- **Status is honest.** `proposed` until it is actually in force.

## Done when

The ADR exists, is indexed, is linked from the PR, and a future reader can
reconstruct *why* without asking anyone.
