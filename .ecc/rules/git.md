<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — rules/common/git-workflow.md.
     See .ecc/UPSTREAM.md. -->

# Git Rules

## Branching

- Work only on the Arena session branch (`arena/*`). Never push to `main`.
- One issue → one branch → one pull request.
- No force-push on shared branches; no history rewriting after review starts.

## Commit messages

Conventional commits:

```
<type>: <short imperative summary>

<optional body: what changed and why, plus verification evidence>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`,
`build`.

Body rules:

- Explain *why*, not just *what* — the diff already shows what.
- Record verification actually performed (`verify.sh` result, commands run).
- Reference the issue (`Refs #N`) when the commit is not the closing one.

## Before committing

1. `bash scripts/verify.sh` → exit 0.
2. `git status` and `git diff --stat` — nothing unintended, no scratch files.
3. No secrets, no build output, no generated artifacts that belong outside Git.
4. Commit message follows the format above.

## Pull requests

1. Review the whole branch, not just the last commit:
   `git diff main...HEAD`.
2. Fill `.github/PULL_REQUEST_TEMPLATE.md` completely: what changed, what was
   verified, what was not, known limitations.
3. Reference the issue with `Closes #N` (or `Refs #N` when partial).
4. Include CI status; if CI has not run or failed, say so in the body.
5. Leave the PR **open**. ChatGPT performs the independent review of the real
   GitHub diff. Arena does not merge its own work.
6. Address review feedback with new commits, so the reviewer sees the delta.

## Enforcement

`.git/hooks/` is explicitly **not** the enforcement mechanism: hooks are not
committed, so a fresh clone has none. The authoritative gate is
`scripts/verify.sh` run by the agent and independently by
`.github/workflows/verify.yml`.
