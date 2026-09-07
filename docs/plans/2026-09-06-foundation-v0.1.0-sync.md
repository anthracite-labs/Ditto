# Plan — align Ditto with App-Factory v0.1.0

Written before implementation on `arena/01a0784a-ditto`, 2026-09-06.
This task is the migration request in the Arena session, not a new product issue.

## Requirement

Sync the reusable engineering hardening from the reviewed App-Factory foundation
into Ditto without re-templating the repository. This is an **App-Factory
foundation sync, not an ECC upgrade**. Ditto remains an independent application
repository with its identity, project history, product documents and decisions.

## Inspected sources and baseline

- Ditto base: `5d9cc349d264f73e8da913da9d2cea664522237d`.
- App-Factory source: `ffe4382677c5237d2c86066c96742cf96a5f10fe`.
  GitHub `main` matched that pin when inspected. All 50 files in the downloaded
  archive matched their blob hashes in the pinned Git tree. Source material was
  downloaded outside Ditto's working tree.
- Read Ditto's bootstrap, provenance, version, memory, verification/self-tests,
  engineering/security/git rules, relevant workflows and existing ADRs; inspected
  App-Factory's gate, self-tests, init/bootstrap/sync scripts, lifecycle config,
  ruleset, CI and lifecycle/factory documentation.
- Ditto's product and domain are explicitly undefined. Architecture describes
  the engineering system only. The correct phase is **discovery**, not
  architecture; set `ALLOW_APP_STACK=0` and leave `STACK_DECISION_ADR` empty.
- Baseline `bash scripts/verify.sh`: **14 passed, 0 failed, 1 skipped**
  (AgentShield ran, examined zero files, correctly advisory).
- Baseline `bash scripts/selftest.sh`: **28/28 cases**.
- ShellCheck 0.9.0 and 0.11.0 plus PyYAML 6.0.3 installed in isolated tooling
  directories outside the repository for cross-version verification.
- Live GitHub `Main` ruleset is active on the default branch, with creation,
  deletion, non-fast-forward, PR and strict status-check rules. Required job
  names are exactly `Foundation gate` and `Independent checks`. Zero mandatory
  human approvals and the connection's reported bypass capability mean the
  independent ChatGPT/no-self-merge rule is an operational rule, not something
  the committed JSON can certify. No admin setting will be changed by this PR.

## Acceptance criteria (from the request)

- “Preserve Ditto-specific material”: identity, project history, `docs/MEMORY.md`,
  product/domain/roadmap content, existing ADRs, reviewed ECC provenance, ruleset
  intent and required CI job names.
- Port `FOUNDATION_VERSION`, lifecycle config, explicit discovery/architecture/
  implementation phases, `ALLOW_APP_STACK`, `STACK_DECISION_ADR`, accepted
  application-stack ADR validation, exact metadata parsing, duplicate/missing
  lifecycle-key rejection and “fail-closed standalone `--only=no_app_stack`”.
- Port safe/idempotent initialization where useful, with “`--force` preserving
  lifecycle state”, structural portable ruleset validation, stronger CI wiring,
  provenance/foundation checks and expanded negative tests.
- “secret scanner must never print matched secret values”; no whole-line
  placeholder allowlist; no repeated-character exemption; `.env*` prohibited
  except the deliberate example policy; zero-file AgentShield is SKIP/advisory;
  full ECC MIT licence intact.
- Required CI jobs remain exactly `Foundation gate` and `Independent checks`;
  “no direct pushes to main”; “no self-merge”.
- Run verification, self-tests, both practical ShellCheck versions, licence/
  provenance checks, identity/history comparisons and fail-closed guard tests.
- One PR titled `foundation: align Ditto with App-Factory v0.1.0`, from this
  session branch, left open for independent ChatGPT review. Do not merge.

## Approach and intended differences

1. Start with the pinned App-Factory executable hardening and regression suite;
   adapt the identity, required paths and provenance direction rather than
   copying generic project documents over Ditto.
2. Add the root `FOUNDATION_VERSION` file containing `0.1.0`. Append foundation
   source fields to `.ecc/VERSION` and a separate sync record to `.ecc/UPSTREAM.md`.
   Keep every existing ECC field, attribution and licence byte intact. The ECC
   pin remains `2.2.0` / `v2.2.0` /
   `5eddf1a3ffd311423be2d4ba7d26f7209c91b033`.
3. Initialize `config/project.env` as Ditto / ditto / discovery / 0 / empty ADR.
   Ditto is not the master template: do not expose a `factory` lifecycle state.
   The init helper is an identity-only, no-op-by-default maintenance utility;
   it must never reset a valid application's lifecycle or rewrite its docs.
4. Add Ditto-specific `docs/FOUNDATION.md` rather than generic `docs/FACTORY.md`.
   Keep `ARENA_CAPABILITIES.md` and existing product, domain, architecture,
   roadmap and numbered ADRs unchanged. Add a new foundation ADR and index entry;
   append to memory (never rewrite historical entries). Update entry points and
   security/verification guidance additively.
5. Preserve live governance intent in an ID-free payload, including Ditto's
   existing branch-creation protection. Document the live-versus-portable
   distinction and human-only review/admin responsibilities. Do not apply it.
6. Tighten relevant failure paths uncovered during inspection instead of
   inheriting avoidable gaps: complete standalone lifecycle validation; confined
   ADR paths and unambiguous metadata/fences; safe init argument handling and
   atomic writes; exact structural CI/ruleset validation (no decoy strings,
   duplicate fields, extra contexts or nested IDs); mandatory provenance values;
   redaction-safe unusual filenames; unrestricted-depth `.env*` detection.
   Add regression cases before these changes and retain the source controls.

## Implementation phases and evidence

1. **RED / characterize** — extend Ditto's tests with representative bypass
   regressions, run them against the old gate, and record expected failures.
   Preserve the original 28 cases, then port all applicable App-Factory tests.
2. **Port** — add config/version, gate, init, bootstrap, CI and provenance
   hardening. Restore green baseline in discovery. Add further adversarial tests
   for the inspected edge cases before addressing them.
3. **Integrate documents** — explain lifecycle transitions, accepted-stack
   metadata, source pin, tooling and governance in Ditto's own documentation.
   Keep the original memory as an exact prefix; preserve existing product and
   decision files byte-for-byte. Record the foundation trade-off without
   choosing any application stack.
4. **Verify and review** — run the real `bash scripts/verify.sh` and
   `bash scripts/selftest.sh` with ShellCheck 0.9.0 and 0.11.0; check shell syntax,
   ECC upstream licence bytes, source pins, working-tree identity/history, diff
   whitespace and the live ruleset (read only). Inspect the entire diff in code,
   security and specification review modes. Explain every skip and limitation.
5. **PR** — commit on the fixed Arena branch, push only that branch, open one PR,
   inspect both real CI job results, update the PR with the exact evidence and
   deliberate differences, and leave it open and unmerged for ChatGPT review.

## Risks, boundaries and out of scope

- Foundation configuration and CI are executable policy: a false green from
  missing tools, malformed metadata or a disabled job is unacceptable. Tests
  must verify the intended named failure, not merely any non-zero process exit.
- A regex scanner is still a credential-shape heuristic, not complete secret
  detection. Never print injected credential values, including on failed tests.
- AgentShield's zero-file result is advisory, not coverage of this Arena adapter.
- Ruleset JSON is desired portable policy, not proof of live administration.
  The agent will not change visibility, rulesets, review settings, App permissions
  or Actions permissions, and will not push to main or merge its own PR.
- No ECC/scanner upgrade, product definition, framework, database, authentication,
  hosting, UI or application code. No generic App-Factory history is imported.
- No history rewriting, branch switching, repository replacement, generated
  archives, tooling environments or downloaded source committed into Ditto.
