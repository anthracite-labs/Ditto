<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — rules/common/testing.md and
     skills/tdd-workflow/SKILL.md. See .ecc/UPSTREAM.md. -->

# Testing Rules

## When test-first applies

**Test first (RED → GREEN → IMPROVE):** new functions, scripts, parsers, CLI
behaviour, data transformations, API logic, bug fixes (write the test that
reproduces the bug before fixing it).

**Not test-first:** documentation, repository scaffolding, CI metadata,
engineering-system Markdown. Those are covered by `scripts/verify.sh`, which is
itself the deterministic test for this repository. Do not invent application
tests before an application exists.

## The cycle

1. **RED** — write the smallest test that expresses the required behaviour.
   Run it. It must fail, and it must fail for the expected reason. Record the
   failing output.
2. **GREEN** — write the minimal implementation. Run the test. Record the
   passing output.
3. **IMPROVE** — refactor with tests green. Re-run.
4. **Evidence** — keep the mapping *requirement → test → RED output → GREEN
   output*. It goes in the PR body.

A test you did not run is not evidence. Never report a pass you did not
observe.

## Standards

- **Coverage target: 80%** once a test suite exists (unit + integration).
- **AAA structure** — Arrange, Act, Assert, visibly separated.
- **Descriptive names** — `returns empty list when no records match`, not
  `test1`.
- **Isolation** — no test depends on another test's side effects; no network
  unless the test is explicitly an integration test.
- **Fix the code, not the assertion**, unless the test is provably wrong — then
  say so and explain why in the commit.

## Arena constraints

- Headless browser E2E is unavailable: the Playwright browser CDN is outside
  the egress allowlist. Use unit tests, DOM-level tests (`jsdom` /
  `happy-dom`), HTTP tests against a locally bound server, and the Arena live
  preview for human inspection.
- Local runners work: Node's built-in test runner, Vitest, Jest, Pytest.
- Long-running watchers must be started with the process tools, not `bash`.

## This repository's tests

At the foundation stage the engineering system *is* the software, so its test
suite is `scripts/verify.sh` executed by `.github/workflows/verify.yml`. Any
new script or workflow contract added to the adapter gets a matching check in
`verify.sh` — that is the test-first rule applied to this repo.
