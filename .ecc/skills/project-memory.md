<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — skills/unified-memory/SKILL.md,
     commands/update-codemaps.md. See .ecc/UPSTREAM.md. -->

# Project Memory

The Arena sandbox is destroyed between sessions. Anything worth knowing must be
committed, or it never happened.

## When to load

At the end of every working session — always. Also mid-session after a
surprise, a failed approach, or a hard-won environment fact.

## Where memory lives

| File | Purpose | Cadence |
| :-- | :-- | :-- |
| `docs/MEMORY.md` | Append-only session ledger: what was done, verified, learned | Every session |
| `docs/decisions/` | ADRs for durable trade-offs (`.ecc/skills/decisions.md`) | When a real decision is made |
| `docs/ARCHITECTURE.md` | Current structure and boundaries | When structure changes |
| `docs/codemaps/` | Token-lean maps of code areas | When application code exists |
| `ARENA_CAPABILITIES.md` | Verified environment facts | When a capability changes |

## Steps

1. **Append a session entry** to `docs/MEMORY.md` using the template below.
   Append — never rewrite history; corrections are new entries.
2. **Record facts, not feelings.** "Playwright CDN is outside the egress
   allowlist" is useful. "Networking was tricky" is not.
3. **Record failed approaches.** The next session's cheapest saving is not
   repeating your dead end. One line each, with the reason it failed.
4. **Record verification, not intent.** The command run and the value it
   returned — not "tests should pass".
5. **Promote durable decisions** into an ADR. Memory is a ledger; ADRs are the
   reasoning that outlives it.
6. **Update structure docs** if the repository shape changed.
7. **Commit it with the work.** Memory pushed in a separate commit that never
   happens is memory lost.

## Entry template

```markdown
## YYYY-MM-DD — <short title> (issue #N, branch <name>, PR #M)

**Done:**       <what changed, in one or two lines>
**Verified:**   <command> → <actual result>
**Learned:**    <durable facts about the repo, tooling, or environment>
**Dead ends:**  <approaches tried and why they failed>
**Next:**       <the obvious next step, and any open question>
```

## Rules

- Keep entries short. A ledger nobody reads is worse than none.
- No secrets, tokens, or customer data in memory files.
- Never state a capability as verified unless it was observed in a session;
  mark inferences `[INFERRED]`.
- Do not duplicate the PR description. Memory records what a future session
  needs; the PR records what a reviewer needs.

## Done when

`docs/MEMORY.md` carries today's entry, committed and pushed on the session
branch, and any durable decision has an ADR.
