<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — rules/common/development-workflow.md,
     rules/common/code-review.md, rules/common/patterns.md. See .ecc/UPSTREAM.md. -->

# Engineering Rules

Always in force. These are the standing rules; workflows in `.ecc/skills/`
describe *how* to apply them.

## The loop

```
Research → Plan → Implement (test-first where applicable) → Review → Verify → Commit → PR → independent review
```

No stage may be skipped silently. If a stage genuinely does not apply, say why
in one line — in the plan, the commit body, or the PR description.

## Non-negotiables

1. **Plan before code.** Multi-file changes get a written plan first
   (`.ecc/skills/planning.md`).
2. **Research before inventing.** Check the repo, then primary upstream
   sources, then the wider web (`.ecc/skills/research.md`).
3. **Test first for executable behaviour.** RED before GREEN
   (`.ecc/rules/testing.md`).
4. **Review before commit.** Every diff gets a code review pass; security
   triggers get a security pass (`.ecc/rules/security.md`).
5. **Verify before claiming done.** `bash scripts/verify.sh` must exit 0.
6. **Record what mattered.** `docs/MEMORY.md` plus ADRs for real decisions.
7. **One PR per issue.** The PR body states what was verified and what was not.

## Honesty rules

These exist because an agent's most damaging failure is confident fiction.

- State results you obtained in *this* session, with the command and the value
  that came back. Name the function or path the check actually executed.
- A clean exit code is not a pass if the output is wrong. Read the output.
- A skipped check is reported as skipped, never as passed.
- "I could not run this here, because X" is an acceptable outcome. An
  unverified claim presented as done is not.

## Code shape

Applies as soon as application code exists; harmless before that.

- Functions stay focused (< ~50 lines); prefer early returns over nesting
  deeper than 4 levels.
- Files stay cohesive; treat ~800 lines as a soft ceiling that needs a reason.
- Handle errors explicitly. No silent catches, no swallowed failures.
- No debug output left behind (`console.log`, `print`, stray `set -x`).
- Prefer immutable updates and pure functions over in-place mutation.
- Prefer an existing, maintained dependency over hand-rolled code — but only
  after research, and record the choice.

## Scope discipline

- Implement what the issue asks. Nothing adjacent, nothing speculative.
- No new framework, database, auth scheme, hosting target, or UI without an
  approved issue and an ADR in `docs/decisions/`.
- If the smallest correct change is larger than the issue implies, stop and
  say so rather than quietly expanding scope.

## Arena-specific rules

Derived from `ARENA_CAPABILITIES.md` (verified 2026-09-06):

- Nothing persists between sessions except what is committed and pushed.
- Shell state (variables, `cd`, env) does not survive between tool calls;
  long-lived processes need the process tools, and servers bind `0.0.0.0`.
- Egress is allowlisted: `github.com`, `api.github.com`, `registry.npmjs.org`,
  `pypi.org`, `files.pythonhosted.org`. Assume anything else is blocked and
  say so instead of retrying.
- No browser binaries and no Playwright download path — E2E is out of scope;
  substitute unit/DOM tests plus the live preview.
- There are no harness hooks, slash commands, or subagents. Enforcement is
  `scripts/verify.sh` plus GitHub Actions, never `.git/hooks/`.
