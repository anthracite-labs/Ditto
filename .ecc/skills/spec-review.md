<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — commands/review-pr.md and
     skills/santa-method/SKILL.md (dual independent review, reframed as
     sequential passes: Arena has no parallel subagents). See .ecc/UPSTREAM.md. -->

# Specification Review

Code review asks *"is this code good?"*. Spec review asks *"is this the code
that was asked for?"*. They fail independently, so they are run separately.

## When to load

- The change implements a GitHub issue with acceptance criteria.
- A written spec, ADR, or contract exists.
- The PR is about to be opened.
- A reviewer says the work "looks fine but isn't what I asked for".

## Steps

1. **Fetch the spec fresh.** `gh issue view N` — do not review against your
   recollection of it. Requirements drift during implementation, and memory
   drifts faster.
2. **Extract every requirement**, including the ones buried in prose, and the
   explicit non-goals.
3. **Build the conformance table.** One row per requirement:

   ```
   | Requirement (verbatim) | Where implemented | Evidence | Verdict |
   |------------------------|-------------------|----------|---------|
   | <quote from the issue> | <file:line / command> | <command output> | MET / PARTIAL / NOT MET / N/A |
   ```

   Every verdict needs evidence — a path, a command, an output value. "Done"
   is not evidence.
4. **Check the non-goals.** Confirm nothing forbidden was introduced: no
   product decisions, no stack choices, no scope expansion.
5. **Check the deltas the spec never mentioned** — new files, new scripts, new
   CI jobs. Each needs a justification line.
6. **Report gaps honestly.** A PARTIAL row with a stated reason is fine. A
   silent omission is the failure mode this skill exists to catch.

## Verdict rules

- **PASS** — every requirement MET or explicitly N/A with a reason.
- **CONDITIONAL** — at least one PARTIAL, each with a named follow-up.
- **FAIL** — any requirement NOT MET without an agreed deferral.

## Arena note

The independent second pass is ChatGPT's review of the real GitHub diff. This
skill prepares for it: the conformance table goes in the PR body so the
reviewer can check each row instead of re-deriving it. Do not merge on the
strength of your own spec review.

## Done when

Every requirement in the spec has a row, a verdict, and evidence — and the
non-goals are confirmed untouched.
