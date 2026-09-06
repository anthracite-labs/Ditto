<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) —
     skills/agent-introspection-debugging/SKILL.md. See .ecc/UPSTREAM.md. -->

# Debugging

Use this when you have failed twice. The third blind retry is the most expensive
thing you can do: it burns context, erases the evidence, and usually reproduces
the same failure.

## When to load

- The same failure has appeared twice.
- You are looping on the same tool or command with no new information.
- The environment does not match your assumptions (paths, versions, ports,
  branch, permissions).
- A check passes locally and fails in CI, or vice versa.
- Output is subtly wrong rather than loudly broken.

## The four-phase loop

### Phase 1 — Capture (before touching anything)

Record precisely:

```markdown
## Failure capture
Goal:                  <what you were trying to achieve>
Command:               <exact command>
Exit code / output:    <verbatim, trimmed to the relevant lines>
Last known good step:  <what still works>
Assumptions in play:   <cwd, branch, versions, env, files expected to exist>
Pattern:               <how many times, does it vary?>
```

Do not clean up, revert, or "just try" anything yet — the state you are about to
destroy is the evidence.

### Phase 2 — Diagnose

- Form **one** falsifiable hypothesis. Write it as: *"If X, then running Y will
  show Z."*
- Check the cheapest discriminator first: `pwd`, `git status`, `--version`,
  `ls`, a single-line reproduction.
- Bisect deliberately: `git bisect` for regressions, comment-out halves for
  logic, minimal input for parsers.
- Distinguish the four usual causes: wrong assumption, wrong environment,
  wrong code, wrong test.

### Phase 3 — Contain and fix

- Make the **smallest** change that the hypothesis supports.
- Keep it reversible; do not bundle an unrelated cleanup into a bug fix.
- Re-run the original failing command. Same input, same command, new result.
- Add or update the test that now covers this failure
  (`.ecc/skills/tdd.md`), so it cannot return silently.

### Phase 4 — Report

State: the symptom, the root cause, the fix, the command that proves it, and
what you still do not know. If the root cause is unknown but the symptom is
contained, say exactly that — a contained workaround presented as a diagnosis
is a lie with a longer fuse.

## Anti-patterns

- Retrying the same command hoping for a different result.
- Widening scope: "while I'm here" changes inside a bug fix.
- Deleting or skipping the failing check to get green.
- Fixing the test instead of the code without evidence the test was wrong.
- Guessing at a version or flag instead of asking the tool.

## Done when

The original failing command now succeeds, the reason is explained, and a test
or check exists that would catch the same failure again.
