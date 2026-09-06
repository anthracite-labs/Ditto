<!-- Adapted from ECC v2.2.0 (affaan-m/ECC, MIT) — skills/verification-loop/SKILL.md.
     See .ecc/UPSTREAM.md. -->

# Verification

The gate between "I think it works" and "it works". Verification is
`scripts/verify.sh` — deterministic, committed, and enforced independently by
GitHub Actions.

## When to load

Before every commit. Before opening a PR. After refactors. Whenever you are
about to write the word "done".

## Run it

```bash
bash scripts/verify.sh
```

Useful variants:

```bash
bash scripts/verify.sh --list                  # enumerate checks
bash scripts/verify.sh --only=secrets          # run one check
bash scripts/verify.sh --skip-agentshield      # offline / no registry access
VERIFY_AGENTSHIELD=require bash scripts/verify.sh   # fail if scanner cannot run
```

Exit code 0 means no selected check failed; a SKIP is still a SKIP, not proof of
coverage. Non-zero means the change is not ready — read the failures, fix them,
re-run.

## What the gate covers

| Check | Asserts |
| :-- | :-- |
| `foundation` | required adapter, docs, config, CI, and script files exist |
| `foundation_version` | one valid foundation SemVer, separate from the ECC record |
| `links` | every relative Markdown link in repository `.md` files resolves |
| `shell_syntax` | every `*.sh` passes `bash -n` |
| `shell_lint` | shell scripts pass shellcheck at style severity (skipped if absent) |
| `executable` | required scripts are executable on disk, and mode 100755 once tracked |
| `provenance` | exact reviewed ECC/scanner pins, full MIT notice, Ditto identity and App-Factory source record; no missing/duplicate required keys |
| `attribution` | adapted rules/skills/roles carry an ECC attribution header |
| `skill_index` | index rows and workflow files match in both directions |
| `bootstrap` | bootstrap's always-read and referenced files exist; every workflow is routed |
| `ci_wiring` | actual gate/self-test execution, exact required job names, unfiltered triggers, pinned actions, safe checkout and read-only permissions (Python/PyYAML required) |
| `secrets` | no credential-shaped value anywhere in the repository files; findings are reported as `path:line [category]` with the value redacted |
| `env_files` | no `.env*` at any depth (regular `.env.example` only; still secret-scanned) |
| `lifecycle` | complete, unique, valid project config and a real accepted ADR before enabling a stack |
| `no_app_stack` | independently validates all lifecycle state; rejects known stack artifacts until a valid transition (then SKIP) |
| `ruleset` | portable structural branch policy, exact two contexts, no bypass or instance IDs |
| `agentshield` | static AgentShield scan; `SKIP` (not PASS) when it scanned 0 files |
| `workflows_yaml` | workflow files parse as YAML (skipped without a YAML parser) |

Checks walk the **working tree**, not the git index, so uncommitted work is
verified too. The only index-aware check is `executable`, which cannot demand a
mode from a file that has not been added yet.

## Prove the gate can fail

A green gate means nothing unless the gate is capable of going red. Run the
committed negative tests:

```bash
bash scripts/selftest.sh
```

It injects faults into a **throwaway copy** of the repository (never the real
tree) and asserts a non-zero exit for each one — including that an injected
credential fails the gate *without* its value appearing in the output, and that
credentials are still caught on lines containing words like `example` or
`todo`. Cases assert the intended named failure and exit 1, not arbitrary runner
errors. Lifecycle/metadata/CI/ruleset faults, safe init behavior and deterministic
scanner reports are tested too, with positive controls. Run it after changing
`scripts/verify.sh`. Use both ShellCheck 0.9.x and 0.11.x when practical.

## Report format

Report verification the way it actually came back:

```
VERIFICATION
============
command:  bash scripts/verify.sh
result:   <PASS/FAIL — actual passed, failed and skipped counts>
executed: <name the function/path the run actually reached>
notes:    <anything skipped, and why>
```

## Rules

- A clean exit code with wrong output is not a pass. Read the output.
- A skipped check is reported as skipped — never folded into "passed".
- Never weaken a check to make it green. If a check is genuinely wrong, fix
  the check in the same commit and explain why.
- Never substitute a hand-written stand-in for the project's own runner: a
  script that re-implements the changed logic verifies the stand-in, not the
  change.
- CI is the independent witness. Local PASS plus CI PASS is the standard for
  "done".

## Done when

`scripts/verify.sh` exits 0 in this session, the same run is green in GitHub
Actions, and any skip is stated plainly in the PR body.
