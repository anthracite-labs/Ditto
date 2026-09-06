# Skill Index — load only what the task needs

Router for the Ditto ECC-on-Arena adapter. Read this table, then open **1–2**
workflow files. Do not read them all; do not read upstream ECC.

Every path below is checked for existence by `scripts/verify.sh`
(`skill_index`), in both directions: an index row with a missing file fails, and
a workflow file missing from this index fails.

| Workflow | Path | Load when | Skip when |
| :-- | :-- | :-- | :-- |
| Planning | `.ecc/skills/planning.md` | Any multi-file change, any issue without an obvious one-step fix, ambiguous requirements | Trivial single-line typo fixes |
| Research | `.ecc/skills/research.md` | Facts are uncertain, a dependency or upstream API is involved, "which approach?" questions | The answer is already in the repo |
| TDD | `.ecc/skills/tdd.md` | New executable behaviour: functions, scripts, parsers, logic | Docs-only or metadata-only changes |
| Debugging | `.ecc/skills/debugging.md` | Any failure reproduced twice, flaky checks, environment mismatch | First-try errors with an obvious cause |
| Code review | `.ecc/skills/code-review.md` | Before every commit and on every PR diff | Never skip |
| Spec review | `.ecc/skills/spec-review.md` | The change implements a written spec or a GitHub issue with acceptance criteria | Purely exploratory work |
| Security review | `.ecc/skills/security-review.md` | Mandatory triggers in `.ecc/rules/security.md`; any CI/workflow change; before release | Diff touches no trigger surface |
| Verification | `.ecc/skills/verification.md` | Before commit, before PR, after refactors, when claiming "done" | Never skip |
| Project memory | `.ecc/skills/project-memory.md` | End of every working session, after a surprise, after a failed approach | Never skip |
| Decisions (ADR) | `.ecc/skills/decisions.md` | A trade-off was chosen over a real alternative; a constraint was accepted | No decision was actually made |

## Persona modes (sequential, one agent)

| Role | Path | Use for |
| :-- | :-- | :-- |
| Architect | `.ecc/roles/architect.md` | Structure, boundaries, "does this belong here?" |
| Security reviewer | `.ecc/roles/security-reviewer.md` | Adversarial read of the diff |
| Spec reviewer | `.ecc/roles/spec-reviewer.md` | Acceptance-criteria conformance |

## Standing rules (always apply, loaded once at bootstrap)

`.ecc/rules/engineering.md` · `.ecc/rules/testing.md` · `.ecc/rules/security.md` · `.ecc/rules/git.md`
