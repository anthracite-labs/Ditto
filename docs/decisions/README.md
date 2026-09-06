# Architecture Decision Records

Durable trade-offs, recorded so future sessions can reconstruct *why* instead of
re-litigating it. Procedure:
[`.ecc/skills/decisions.md`](../../.ecc/skills/decisions.md).

## Rules

- One decision per file: `NNNN-<kebab-title>.md`, numbered sequentially.
- Accepted ADRs are never edited to change the decision — supersede them with a
  new ADR and mark the old one `superseded by ADR-NNNN`.
- Alternatives must be real, and the "why not" must be specific.
- Consequences must include the costs.

## Index

| ADR | Title | Status | Date |
| :-- | :-- | :-- | :-- |
| [0001](0001-ecc-on-arena-adapter.md) | Adopt an ECC-on-Arena adapter instead of native ECC | accepted | 2026-09-06 |
| [0002](0002-verification-gate.md) | `scripts/verify.sh` + GitHub Actions as the sole quality gate | accepted | 2026-09-06 |
| [0003](0003-flat-skill-files.md) | Flat per-task workflow files instead of upstream `SKILL.md` directories | accepted | 2026-09-06 |

## Template

Copy [`0000-template.md`](0000-template.md) to start a new record.
