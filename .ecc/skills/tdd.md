<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — skills/tdd-workflow/SKILL.md.
     See .ecc/UPSTREAM.md. -->

# Test-Driven Development

Tests are written before the code they constrain. The point is not ritual — it
is that a test which never failed proves nothing.

## When to load

- New executable behaviour: functions, scripts, parsers, CLI flags, logic.
- A bug fix: the reproduction test comes before the patch.
- A refactor: characterisation tests first, so behaviour is pinned.

Not for docs, scaffolding, or CI metadata — see `.ecc/rules/testing.md`.

## Step 0 — Detect the runner first

Do not assume `npm test`. Resolve the real command once, then reuse it
everywhere:

- Node: `package.json` `scripts.test`; or the built-in runner
  (`node --test`); or Vitest/Jest when configured.
- Python: `pytest` inside a venv (the system interpreter is PEP 668 managed).
- Shell: `bash -n <script>` for syntax, plus a real invocation of the changed
  code path.

Record the command in the plan. `<test>` below means that command.

## The cycle

1. **RED.** Write the smallest failing test for one behaviour. Run `<test>`.
   Capture the failure output. Confirm it fails *for the expected reason* — an
   import error or typo is not a RED.
2. **GREEN.** Write the minimum code that passes. Run `<test>`. Capture the
   passing output. Do not add speculative features here.
3. **IMPROVE.** Refactor with tests green. Re-run `<test>` after each
   meaningful refactor.
4. **Repeat** per behaviour, one test at a time. Small steps keep failures
   attributable.
5. **Evidence.** Maintain the mapping:

   ```
   requirement → test name → RED output → GREEN output
   ```

   This mapping is what goes in the PR body. It is the difference between
   "I tested it" and a reviewer being able to check.

## Rules

- Never edit an assertion to make a suite pass unless the test is provably
  wrong — and then say why in the commit.
- Never report a test result you did not observe in this session.
- Coverage target is 80% once a suite exists; edge cases and error paths count
  as required, not optional.
- Tests must be isolated and deterministic: no ordering dependence, no network
  unless the test is explicitly an integration test, no wall-clock flakiness.
- If a test needs a live server, start it with the process tools bound to
  `0.0.0.0`, then stop it.

## Done when

Every acceptance criterion maps to at least one test, each test was seen failing
before it was seen passing, and the full suite passes with its real output
recorded.
