# ADR-0002: `scripts/verify.sh` + GitHub Actions as the sole quality gate

**Date:** 2026-09-06
**Status:** accepted
**Deciders:** Ditto maintainers (issue #2); implemented by Arena Agent Mode

## Context

An AI agent reporting its own quality is not a control: the same context that
produced the code judges it, and an unrun test is easily described as passed.
Arena offers no harness hooks (`PreToolUse`, `PostToolUse`, `SessionStart`), so
there is no native place to intercept a commit. Local Git hooks do work in the
sandbox, but `.git/hooks/` is not committed, so a fresh clone — which is what
every new session gets — has none. At the foundation stage there is also no
application code to test; the engineering system itself is the software.

## Decision

Make one committed, deterministic script — `scripts/verify.sh`, exiting
non-zero on failure — the authoritative gate, and have
`.github/workflows/verify.yml` run that same script on every push and pull
request so verification is witnessed independently of any agent session.

## Alternatives considered

### Alternative: `.git/hooks/pre-commit` as the primary gate

- **Pros:** Fires automatically; zero agent cooperation required.
- **Cons:** Hooks are not tracked by Git, so they vanish on a fresh clone.
- **Why not:** Every Arena session starts from a fresh clone. A control that
  only exists in the sandbox where it was installed is not a control. It may
  still be installed as a convenience, but never as the mechanism.

### Alternative: Harness lifecycle hooks

- **Pros:** The ECC-native design; enforced at tool-call boundaries.
- **Cons:** Arena exposes no such events.
- **Why not:** Verified unavailable in `ARENA_CAPABILITIES.md`.

### Alternative: Agent self-attestation in the PR body

- **Pros:** Zero infrastructure.
- **Cons:** Unfalsifiable, and the exact failure mode this repo must avoid.
- **Why not:** A claim is not evidence. CI output is.

### Alternative: A conventional test suite (Jest/Pytest) over the adapter

- **Pros:** Familiar tooling and reporting.
- **Cons:** Would require adding a runtime dependency and a stack decision to
  test Markdown structure and shell scripts.
- **Why not:** `bash -n`, shellcheck, existence checks, and regex scans cover
  the real assertions with no dependencies. A suite can be added when
  application code exists.

## Consequences

### Positive

- One command, locally and in CI, with a real exit code.
- Checks are reviewable diffs; weakening one is visible in the PR.
- No runtime dependencies beyond bash, coreutils, git, and optionally jq /
  shellcheck / node.

### Negative

- Shell is a blunt instrument for parsing Markdown; the link and index checks
  are regex-based and can miss exotic syntax.
- Checks must be extended by hand as the repository grows.
- A skipped optional check (offline AgentShield, missing shellcheck) reduces
  local assurance, which is why CI runs the stricter configuration.

### Follow-ups

- Add a shell test harness for `scripts/*.sh` beyond syntax and lint.
- Decide whether the AgentShield check should be required in CI or stay
  advisory.
