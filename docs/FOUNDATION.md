# Ditto engineering foundation

Ditto is an independent product repository, **not a template repository**. Its
product is still undefined. This foundation sync preserves Ditto's project
history, memory, product documents, Arena audit and existing decisions; it does
not initialize a replacement project or import App-Factory's generic history.

## Reviewed source and versions

| Record | Value / meaning |
| :-- | :-- |
| Foundation | [`FOUNDATION_VERSION`](../FOUNDATION_VERSION): `0.1.0` |
| Foundation source | [anthracite-labs/App-Factory](https://github.com/anthracite-labs/App-Factory) at `ffe4382677c5237d2c86066c96742cf96a5f10fe` |
| Ditto before this sync | `5d9cc349d264f73e8da913da9d2cea664522237d` |
| ECC | `2.2.0`, tag `v2.2.0`, commit `5eddf1a3ffd311423be2d4ba7d26f7209c91b033` — unchanged |
| AgentShield | `ecc-agentshield@1.4.0` — unchanged, advisory |

This is an **App-Factory foundation sync, not an ECC upgrade**. The foundation,
ECC adapter and scanner are separate versioned records. Their numbers need not
be different forever; their meanings and provenance must remain distinct.
Machine-readable source fields are appended to [`.ecc/VERSION`](../.ecc/VERSION).
Existing reviewed ECC provenance and the full upstream MIT licence remain intact.

App-Factory itself was derived from Ditto's earlier foundation. Synchronizing its
reusable hardening back does not make Ditto a new instance of the master template.
The [migration plan](plans/2026-09-06-foundation-v0.1.0-sync.md) records the inspected
source and preservation boundaries; [ADR-0004](decisions/0004-foundation-lifecycle-sync.md)
records this foundation decision, **not** an application-stack choice.

## Lifecycle: explicit, committed, fail closed

Read [`config/project.env`](../config/project.env) at session start. Today it is:

```text
PROJECT_NAME=Ditto
PROJECT_SLUG=ditto
PROJECT_PHASE=discovery
ALLOW_APP_STACK=0
STACK_DECISION_ADR=
```

| Phase | Meaning | Stack guard |
| :-- | :-- | :-- |
| `discovery` | Product not defined | Required: `ALLOW_APP_STACK=0` |
| `architecture` | Reviewed product definition exists; architecture selection is underway | Required: `ALLOW_APP_STACK=0` |
| `implementation` | Stack selected and recorded in an ADR | May allow artifacts only with the accepted stack decision |

There is no `factory` phase in Ditto. Do not move to architecture merely because
engineering-system documentation exists. First the product owner defines the
problem, users, scope and non-goals through a reviewed issue/PR, as required by
[PRODUCT.md](PRODUCT.md). Nothing in this migration chooses a framework,
database, authentication provider, hosting platform or UI.

The config is data, never shell code: scripts do not source it. Required keys
must occur exactly once. Missing, duplicate, malformed or contradictory state
fails validation, including a standalone `--only=no_app_stack` invocation. An
`ALLOW_APP_STACK` environment variable is ignored. The guard is not disabled by
editing `scripts/verify.sh`.

### Recording a future stack decision

Use an approved issue and a reviewed ADR under `docs/decisions/`. Copy the existing
[ADR template](decisions/0000-template.md), complete its substantive decision, and
place these **standalone metadata lines** alongside its date and deciders:

```text
**Status:** accepted
**Decision Type:** application-stack
```

Then, in the reviewed transition, set `PROJECT_PHASE=implementation`,
`ALLOW_APP_STACK=1` and `STACK_DECISION_ADR` to that actual ADR. The path must be a
regular `docs/decisions/NNNN-<title>.md` file, not a symlink, traversal path, the
ADR template or an unrelated foundation ADR. Comments, code fences, blockquotes,
indented code and prose mentions cannot supply metadata. Duplicate/conflicting
active metadata is not approval. A proposed stack ADR may be referenced while
the guard remains up, but cannot authorize implementation.

When legitimately stood down, `no_app_stack` reports **SKIP**, not PASS: that
means only that the foundation stopped rejecting stack artifacts. The same
transition must add the application-specific lint, test and build checks that
apply to the selected stack. They do not exist yet and are not invented here.

### Identity helper (normally a no-op in Ditto)

`bash scripts/init-project.sh` finds Ditto already initialized and changes
nothing. It never replaces repository text, writes provenance or memory,
creates commits, pushes, or changes GitHub settings. `--dry-run` writes nothing.
An explicit `--force --name "..."` changes config identity only, preserving the
phase, allow flag and stack ADR. It refuses invalid configuration rather than
trying to repair it or silently reset the lifecycle. Review any identity change
as a Ditto decision; this utility is not an invitation to rebrand the repository.

## Governance: repository intent versus live GitHub settings

Required CI job names remain **exactly**:

- `Foundation gate`
- `Independent checks`

Work only on the Arena session feature branch. **No direct pushes to main. No
self-merge.** Leave agent-authored PRs open for independent ChatGPT review of the
real diff; an authorized maintainer handles any later merge.

[`config/main-ruleset.json`](../config/main-ruleset.json) is a clean, portable API
request payload, not an export and not proof it has been applied. It contains no
repository IDs, integration IDs, timestamps, links, bypass actors or explanatory
fields. Structural validation checks the actual policy locations, exact two
required contexts, strict/up-to-date checks, review-thread resolution and branch
creation/deletion/force-push protections. CI wiring validates actual job names
and executable steps, not comments or decoy strings; it rejects alternate
checkout targets and shell environment overrides too.

Read-only checks:

```bash
bash scripts/verify.sh --only=ruleset --only=ci_wiring
gh api repos/anthracite-labs/Ditto/rulesets
gh api repos/anthracite-labs/Ditto/rules/branches/main
```

At migration inspection, GitHub's existing **Main** ruleset was active on the
default branch and required those two jobs (bound live to GitHub Actions). It
also protected branch creation, deletion and force pushes, and required PRs,
resolved review threads and strict status checks. The payload retains that
intent, including Ditto's creation protection and extra-approval policy for
unattributed changes; it adopts App-Factory's stale-review dismissal setting.
**This PR does not apply or update a live ruleset.**

The live solo-owner policy has **zero mandatory human approvals**, and the API
reported `current_user_can_bypass=always` for the connection. Therefore neither
`protected: true` nor this JSON proves that independent ChatGPT review or no
self-merge is platform-enforced. Those remain explicit operational rules. Do
not use bypass capability to push to main or merge this PR.

### Human-only admin checklist

1. Confirm the live rule still targets the default branch and requires exactly
   the two named jobs. Preserve the live GitHub Actions association for each
   context; instance IDs do not belong in the portable payload.
2. Compare the existing live ruleset to `config/main-ruleset.json` before any
   administrator applies the desired policy. Update the existing rule through
   GitHub's UI or a separately authorized admin operation; do not blindly create
   a second ruleset. Stale-review dismissal is a proposed hardening, not a claim
   about the already-applied setting.
3. Audit bypass access and decide whether human approvals/last-push approval
   should be required. Do not silently change the existing solo-owner policy
   from a foundation feature PR.
4. Keep independent review before merge. GitHub App installation scope, workflow
   write permission, Actions settings, visibility and rulesets are administrative
   settings; no script here changes them.

Historical notes in `docs/MEMORY.md`, `docs/ROADMAP.md` and `docs/ARCHITECTURE.md`
record protection as pending at the time of the original foundation. They are
preserved as history, not overwritten; the current inspection above supersedes
those observations without erasing them.

## Verification and tooling

```bash
bash scripts/verify.sh
bash scripts/selftest.sh
```

The gate covers the working tree, including untracked files; the executable-bit
check also checks tracked index modes. Core dependencies are Bash, Git, coreutils
and Python 3. Structural CI validation requires PyYAML 6.0.3; it fails closed when
unavailable. CI installs it. ShellCheck runs at style severity when installed
(and is required by CI). Use isolated tooling outside the repository for local
installs; do not add an application manifest just to install engineering tools.

The self-tests exercise the actual gate in throwaway copies, not a replacement
validator. Positive controls prove legitimate states still work. Negative cases
cover metadata/duplicate-key bypasses, init safety, portable policy, CI wiring,
licence/provenance tampering, secret redaction and dotenv files.

AgentShield runs only in static mode. A zero-file result is **SKIP/advisory**,
never security coverage. The secrets scanner has no placeholder exceptions and
reports locations/categories without matched values, including unusual filenames.
`.env*` files at any depth are rejected except regular `.env.example` templates;
examples are still scanned for credential-shaped content. See
[SECURITY.md](SECURITY.md) for the threat model and limitations.

## Future foundation syncs

Inspect and pin the reviewed App-Factory commit; compare reusable files instead
of overwriting Ditto. Preserve project memory, product work and existing ADRs.
Update foundation source records, their reviewed expectations in the provenance
check, and the root version deliberately; run the real
suite, and open a reviewable PR. An ECC upstream upgrade remains its own issue,
ADR, version/pin change and licence verification, never an implication of a
foundation update.
