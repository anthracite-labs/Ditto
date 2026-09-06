<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — rules/common/code-review.md,
     commands/review-pr.md. See .ecc/UPSTREAM.md. -->

# Code Review

Review the diff, not your memory of writing it. Run this before every commit
and on every PR diff.

## Steps

1. **Get the real diff.** `git diff main...HEAD` for a branch, `git diff`
   for uncommitted work. Read every changed file — including the ones you
   "know" are fine.
2. **Security pass first.** If any trigger in `.ecc/rules/security.md` is
   present, load `security-review.md` before continuing.
3. **Correctness pass.** Does the code do what the issue asks? Are edge cases,
   empty inputs, error paths, and boundaries handled?
4. **Quality pass.** Use the checklist below.
5. **Test pass.** Do tests exist for the new behaviour, and were they seen
   failing before passing? Is coverage meaningful rather than incidental?
6. **Verify.** `bash scripts/verify.sh` — record the actual output.
7. **Grade and report.** Findings get a severity and an action.

## Checklist

- [ ] Readable, well-named; intent obvious without comments explaining syntax.
- [ ] Functions focused (< ~50 lines); nesting ≤ 4 levels; early returns.
- [ ] Files cohesive; anything over ~800 lines has a stated reason.
- [ ] Errors handled explicitly — nothing swallowed, nothing silently defaulted.
- [ ] No hardcoded secrets, tokens, or credential-shaped strings.
- [ ] No leftover debug output, commented-out code, or scratch files.
- [ ] No unrelated changes riding along in this diff.
- [ ] No new dependency without a research note and a pinned version.
- [ ] Shell: quoted expansions, `set -euo pipefail` where appropriate, no
      `cd` without a guard, no unbounded globs on untrusted input.
- [ ] Tests added for new behaviour; failure modes covered.

## Severity ladder

| Level | Meaning | Action |
| :-- | :-- | :-- |
| CRITICAL | Security exposure, data loss, or broken correctness | **BLOCK** — fix before commit |
| HIGH | Real bug or significant quality problem | Fix before merge |
| MEDIUM | Maintainability concern; unexplained oversized file | Fix when practical, else record |
| LOW | Style or preference | Optional |

**Approval rule:** CRITICAL blocks. HIGH should be fixed before merge. If you
deliberately defer anything, name it in the PR body.

## Confidence rule

Report findings you would defend at ≥ 80% confidence. Speculation is labelled
speculation. Padding a review with low-confidence noise teaches reviewers to
ignore the real findings.

## Arena note

There are no parallel reviewer subagents here. Reviews are **sequential role
modes** (`.ecc/roles/`): adopt the persona, apply its rubric, then return to
implementation. The genuinely independent review is ChatGPT's pass over the
GitHub diff — do not merge your own work.

## Done when

Every CRITICAL and HIGH finding is resolved or explicitly deferred with a
reason, and the verification output is recorded.
