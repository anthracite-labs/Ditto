# Codemaps

Token-lean maps of how code areas fit together — entry points, call flow, data
flow, and dependencies — written for an agent that has to orient quickly
without reading everything.

**Currently empty, deliberately.** There is no application code to map
(see [../PRODUCT.md](../PRODUCT.md)). The only structure that exists is the
engineering system, which is already documented in
[../ARCHITECTURE.md](../ARCHITECTURE.md) and the repository map in
[../../README.md](../../README.md).

## When to add a codemap

Once application code exists, add one per significant area, on feature
completion or when a reviewer asks "how does this part work?".

| Suggested file | Contents |
| :-- | :-- |
| `architecture.md` | System diagram, service boundaries, data flow |
| `<area>.md` | Entry points, call flow, key types, failure modes |
| `dependencies.md` | External services, registries, integration points |

## Format rules

- Optimised for AI context consumption: short lines, tables, arrows. No prose
  essays.
- Cite real paths. A codemap with invented paths is worse than none, because
  it is trusted.
- State the commit or date it describes; stale maps must be labelled stale.
- Keep each under ~150 lines. Split rather than grow.
