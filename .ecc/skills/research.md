<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — skills/search-first/SKILL.md.
     See .ecc/UPSTREAM.md. -->

# Research

Establish facts before building on them. Guessing is cheaper now and far more
expensive at review time.

## When to load

- You are about to assert a version, API shape, flag, or behaviour.
- A dependency, upstream project, or external service is involved.
- The task says "pick the best approach" or "does X exist already?".
- Something contradicts what you expected.

## Channel order (cheapest and most authoritative first)

1. **This repository** — `git ls-files`, `rg`, `git log`, `ARENA_CAPABILITIES.md`.
   Most "unknowns" are already answered in-repo.
2. **GitHub, via `gh api`** — primary upstream files at a pinned ref. This is
   how `.ecc/UPSTREAM.md` provenance is produced. Egress allows `github.com`
   and `api.github.com`.
3. **Package registries** — `npm view <pkg> version license`,
   `pip index versions <pkg>`. Egress allows `registry.npmjs.org` and
   `pypi.org`.
4. **Web search / page fetch** — for anything the first three cannot answer.

## Steps

1. **Preflight.** Confirm the channel actually works before relying on it. If a
   channel is blocked or unauthenticated, say so and report reduced coverage —
   never imply you searched a source you could not reach.
2. **Pin the source.** Record version, tag, or commit SHA. "Latest" is not a
   citation; `v2.2.0` / `5eddf1a3` is.
3. **Prefer primary over secondary.** Upstream source file over blog post;
   release notes over changelog summaries; the registry over a mirror.
4. **Separate fact from inference.** Label each finding as
   `[VERIFIED <command>]` or `[INFERRED]`.
5. **Decide: adopt / extend / build.** Adopt a maintained solution when it
   fits; wrap it when it nearly fits; build only when nothing does — and record
   the reasoning either way.
6. **Write it down.** Findings that matter go into `docs/MEMORY.md`; durable
   choices become ADRs (`decisions.md`).

## Arena specifics

- Egress allowlist: `github.com`, `api.github.com`, `registry.npmjs.org`,
  `pypi.org`, `files.pythonhosted.org`. Anything else — including most vendor
  docs sites and browser CDNs — fails at the TLS handshake. Report it as
  unreachable rather than retrying.
- `gh` is authenticated as a bot with repo read/write; `gh api` is the fastest
  path to upstream truth.
- Web search results are secondary evidence: verify anything load-bearing
  against a primary source when reachable.

## Done when

Every load-bearing claim in the plan has a source you can name, and the claims
you could not verify are marked unverified.
