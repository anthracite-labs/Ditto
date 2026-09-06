# Roadmap

Sequencing only. No product commitments, dates, or feature promises — Ditto has
no product definition yet (see [PRODUCT.md](PRODUCT.md)).

## Stage 0 — Engineering foundation (current)

Goal: a fresh Arena session can bootstrap from the repository alone and work an
issue with real discipline.

- [x] Arena capability audit (`ARENA_CAPABILITIES.md`)
- [x] ECC-on-Arena adapter (`.ecc/`: bootstrap, rules, skills, roles)
- [x] ECC upstream provenance recorded (`.ecc/VERSION`, `.ecc/UPSTREAM.md`)
- [x] Deterministic verification gate (`scripts/verify.sh`)
- [x] Independent CI verification (`.github/workflows/verify.yml`)
- [x] Project memory and ADR skeleton (`docs/`)
- [ ] Independent ChatGPT review of the adapter (this issue's PR)

## Stage 1 — Foundation hardening (next, no product decisions)

Candidates, in rough priority order; each needs its own issue:

- [ ] Exercise the protocol on a real issue and record the friction in
      `docs/MEMORY.md`
- [ ] Add the first language rule family **once** a stack is chosen
- [ ] Add a committed shell test harness for `scripts/*.sh` beyond
      `bash -n` / shellcheck
- [ ] Codify the ChatGPT review loop: expected inputs, expected output shape,
      and how feedback is tracked
- [ ] Upstream ECC sync drill: run `scripts/sync-ecc.sh --fetch`, diff, and
      record findings as an ADR
- [ ] Decide whether AgentShield should gate CI or stay advisory

## Stage 2 — Product definition (blocked)

Cannot start until a product owner defines the problem, users, scope, and
non-goals in [PRODUCT.md](PRODUCT.md). Every technical consequence of that
definition requires its own ADR in [decisions/](decisions/README.md).

## Explicitly not planned

- Any framework, database, auth scheme, hosting target, or UI choice.
- Native ECC plugin compatibility — Arena has no plugin runtime.
- Browser E2E — the browser CDN is outside the Arena egress allowlist.
- `.git/hooks/` enforcement — hooks do not survive a fresh clone.
