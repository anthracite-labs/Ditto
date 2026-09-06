# Architecture

**Scope: the engineering system.** There is no application architecture yet,
because there is no application (see [PRODUCT.md](PRODUCT.md)).

## The system that exists

```text
                    ┌─────────────────────────────┐
                    │  ChatGPT (independent layer)│
                    │  planning input, PR review  │
                    └──────────────┬──────────────┘
                                   │ reviews the real diff
                                   ▼
┌──────────────────────────────────────────────────────────────────┐
│  GitHub  (durable source of truth)                               │
│  issues · branches · PRs · Actions · main (protection pending)   │
└───────────────────────────────┬──────────────────────────────────┘
                                │ clone / push / gh api
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│  Arena Agent Mode sandbox (ephemeral)                            │
│  reads .ecc/BOOTSTRAP.md → loads 1–2 skills → plans → implements │
│  → reviews → runs scripts/verify.sh → commits → opens PR         │
└───────────────────────────────┬──────────────────────────────────┘
                                │ only committed files survive
                                ▼
                    ┌─────────────────────────────┐
                    │  .ecc/  (repository-owned)  │
                    │  rules · skills · roles ·   │
                    │  VERSION · UPSTREAM.md      │
                    └─────────────────────────────┘
```

## Component responsibilities

| Component | Responsibility | Deliberately does not |
| :-- | :-- | :-- |
| `.ecc/BOOTSTRAP.md` | Small, complete session protocol | Duplicate rules; load every workflow |
| `.ecc/rules/` | Standing, always-in-force rules | Describe task procedure (that is skills) |
| `.ecc/skills/` | On-demand task workflows, routed by `INDEX.md` | Auto-load; run without being read |
| `.ecc/roles/` | Sequential review personas for one agent | Pretend to be parallel subagents |
| `.ecc/VERSION`, `.ecc/UPSTREAM.md` | Upstream provenance and licence record | Vendor upstream code |
| `docs/MEMORY.md` | Durable cross-session memory | Replace ADRs or PR descriptions |
| `docs/decisions/` | Durable trade-off records | Track task state |
| `scripts/verify.sh` | Deterministic quality gate | Test application behaviour (none exists) |
| `scripts/bootstrap.sh` | Session briefing from repository state | Mutate anything |
| `scripts/sync-ecc.sh` | Upstream inspection and diff preparation | Overwrite local adaptations |
| `.github/workflows/verify.yml` | Independent execution of the gate | Trust an agent's self-report |

## Design principles

1. **Small startup context.** Bootstrap plus the always-read set is a few
   pages. Everything else is loaded only when the task needs it.
2. **Everything durable is in Git.** The sandbox dies between sessions;
   uncommitted knowledge does not exist.
3. **Verification is a program, not a promise.** A committed script with a
   non-zero exit path, re-run by CI, is the only accepted evidence of quality.
4. **Adapt, do not import.** Upstream ECC is enormous (68 agents, 286 skills,
   94 commands). This adapter carries 10 workflows, 4 rules, 3 personas.
5. **No product assumptions.** Nothing here chooses a stack; the guard is
   enforced by `scripts/verify.sh`.

## Constraints from the execution environment

Verified in [../ARENA_CAPABILITIES.md](../ARENA_CAPABILITIES.md) on
2026-09-06:

- No auto-loading of `AGENTS.md`; instructions must be read explicitly.
- No harness hooks, slash commands, plugins, or subagents.
- Egress allowlist: `github.com`, `api.github.com`, `registry.npmjs.org`,
  `pypi.org`, `files.pythonhosted.org`.
- No browser binaries and no Playwright download path, so no browser E2E.
- No inter-session filesystem persistence; Git is the only memory.

## Related

- [decisions/](decisions/README.md) — decision record index
- [SECURITY.md](SECURITY.md) — repository security policy
- [../.ecc/UPSTREAM.md](../.ecc/UPSTREAM.md) — ECC provenance and omissions
