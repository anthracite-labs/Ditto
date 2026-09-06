# Product

**Status: intentionally undefined.**

Ditto is a product name only. No product definition exists yet, and this file
deliberately contains no requirements, personas, features, pricing, or
positioning.

## Why this file exists

So that the absence of a product definition is explicit rather than ambiguous.
An agent that finds this file knows that inventing product requirements would
be a violation, not a contribution.

## What must happen before this file gains content

1. A product owner writes the definition — problem, users, scope, non-goals.
2. The definition lands in a reviewed PR against this file.
3. Any technical consequence (framework, database, hosting, auth) is recorded
   as an ADR in [decisions/](decisions/README.md), not implied by code.

## Guardrails in force until then

- No application source code, framework, database, auth scheme, hosting
  target, or UI may be introduced (`scripts/verify.sh`, check `no_app_stack`).
- Engineering work proceeds on the adapter itself: rules, workflows,
  verification, memory, and decisions.

## Related

- [ARCHITECTURE.md](ARCHITECTURE.md) — what actually exists today
- [DOMAIN.md](DOMAIN.md) — domain vocabulary (also undefined)
- [ROADMAP.md](ROADMAP.md) — sequencing
- [decisions/](decisions/README.md) — decision record index
