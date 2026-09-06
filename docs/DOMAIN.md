# Domain

**Status: intentionally undefined.**

No domain model, ubiquitous language, entities, or business rules exist yet,
because no product has been defined (see [PRODUCT.md](PRODUCT.md)).

This file exists so that the gap is explicit. It will hold the domain
vocabulary — entities, invariants, state transitions, and the meanings the
team agrees on — once a product definition exists.

## Terms that do have meaning today (engineering, not product)

| Term | Meaning here |
| :-- | :-- |
| **Adapter** | `.ecc/` — the ECC-on-Arena adaptation. Not native ECC. |
| **Skill / workflow** | An on-demand Markdown procedure under `.ecc/skills/`. |
| **Rule** | A standing, always-in-force constraint under `.ecc/rules/`. |
| **Role** | A sequential review persona under `.ecc/roles/` (not a subagent). |
| **Gate** | `scripts/verify.sh` — deterministic, non-zero on failure. |
| **Project memory** | `docs/MEMORY.md` — append-only, Git-tracked. |
| **ADR** | A record under `docs/decisions/` for a durable trade-off. |

## Related

- [PRODUCT.md](PRODUCT.md) — product definition (undefined)
- [ARCHITECTURE.md](ARCHITECTURE.md) — the engineering system
- [decisions/](decisions/README.md) — decision record index
