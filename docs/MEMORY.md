# Project Memory

Append-only ledger of what sessions did, verified, and learned. **Append, never
rewrite** — corrections are new entries. See
[`.ecc/skills/project-memory.md`](../.ecc/skills/project-memory.md) for the
procedure.

Durable trade-offs belong in [decisions/](decisions/README.md), not here.

---

## 2026-09-06 — Independent review round 2 on PR #3 (issue #2)

**Done:** Removed the last secrets-scanner bypass.

Round 1 replaced a whole-line allowlist with "value-specific and structural"
exemptions. The reviewer correctly pointed out that this was still a bypass: a
value made of one repeated alphanumeric character was exempted, so an all-x or
all-zero password assignment passed the gate. `is_placeholder_value` is now
deleted outright — `check_secrets` has no exemptions of any kind.

**Verified:** `bash scripts/verify.sh` → 14 passed, 0 failed, 1 skipped
(AgentShield advisory). `bash scripts/selftest.sh` → 28/28 cases, including the
two the review required (`secrets/repeated-char-password`,
`secrets/repeated-char-token`).

**Learned:**

- Verified empirically before changing code: the real tree had **zero** matches
  with no exemptions at all, so the exemption was protecting nothing. When a
  suppression rule has no demonstrated need, delete it rather than narrowing it.
- Angle-bracket placeholders never matched the credential regex in the first
  place, so that exemption was dead code. Confirmed by testing the regex
  against the literal strings instead of reasoning about it.
- Removing an exemption surfaces self-matches. Two prose comments spelling out
  the credential-shaped example then failed the gate. Comments must describe
  the *shape* ("an all-x assignment"), not spell a matchable instance.
- Narrowing a bypass is not the same as closing it. Round 1's fix was
  directionally right and still exploitable; the reviewer caught it.

**Next:** Configure GitHub branch protection on `main` (PR-only, required
`verify` checks, no direct pushes). Still a repository-admin action.

---

## 2026-09-06 — Independent review round 1 on PR #3 (issue #2)

**Done:** Addressed all four blocking findings from the ChatGPT review.

1. **Secrets detector leaked what it found.** Findings printed the full matched
   line, so a committed credential would be echoed into CI logs. Now reports
   `path:line [category]` only; matched material stays in memory.
2. **Whole-line placeholder allowlist was a real bypass.** A credential on a
   line containing `example`/`todo`/`sample` was skipped entirely. Removed.
   Exemptions are now value-specific and structural only (one repeated
   alphanumeric char, or an angle-bracket placeholder).
3. **AgentShield was a vacuous PASS.** It scans Claude Code config surfaces,
   which this adapter does not have, so it reported `PASS (0 files scanned)`.
   Now `SKIP` when `filesScanned == 0`, and documented as advisory.
4. **Upstream MIT notice was only linked.** MIT requires the copyright *and*
   permission notice to travel with adapted material. Committed byte-exact at
   `.ecc/LICENSE-ECC`; `check_provenance` verifies its text and sha256.

Also added `check_env_files` (a force-added `.env` now fails, rather than
relying on `.gitignore` plus a doc claim) and `scripts/selftest.sh`, a
committed 25-case negative suite that runs in CI.

**Verified:** `bash scripts/verify.sh` → 14 passed, 0 failed, 1 skipped
(AgentShield advisory). `bash scripts/selftest.sh` → 25/25 cases behaved as
asserted, including the two the review required.

**Learned:**

- Test fixtures are a disclosure surface. `selftest.sh` initially contained
  literal credential-shaped strings, and the scanner correctly flagged the
  test file itself. Fixtures must be assembled from fragments at runtime — the
  same technique `verify.sh` uses for its own patterns.
- A detector that reports the secret it found is a second disclosure path.
  Redact at the point of reporting, not at the point of logging.
- "Scanned 0 files, all clean" is not a pass. Any check that can report success
  while examining nothing should report SKIP and say why.
- `.gitignore` is not enforcement: it cannot stop `git add -f`. Rules that
  matter belong in the gate.

**Next:** Configure GitHub branch protection on `main` (PR-only, required
`verify` checks). GitHub reports `main` as unprotected, so the PR-only workflow
is currently convention, not platform-enforced. This is a repo-admin action and
must not be done from a feature PR.

---

## 2026-09-06 — Foundation v0.1: ECC-on-Arena adapter (issue #2)

**Done:** Built the engineering foundation: `.ecc/` adapter (bootstrap, 4
rules, 10 on-demand workflows, 3 review personas), docs skeleton,
`scripts/{bootstrap,verify,sync-ecc}.sh`, `.github/workflows/verify.yml`, and
the PR template. No application code, no stack decisions.

**Verified:** `bash scripts/verify.sh` → exit 0, 14 checks passed, 0 failed,
0 skipped (AgentShield ran; static mode). Details in the PR body.

**Learned (environment, verified this session):**

- A new Arena session gets a **fresh sandbox**: `/tmp/turn_persistence_test.txt`
  from the previous audit session was `ABSENT`. Nothing outside Git survives.
- Upstream ECC moved past its last release: tag `v2.2.0` (commit `5eddf1a3`)
  is the pinned release, while `main` carries `VERSION` = `2.2.1` unreleased at
  commit `e04ea0b9`. `npm view ecc-universal version` reports `2.2.0`.
- AgentShield is a **separate repo** (`affaan-m/agentshield`), published as
  `ecc-agentshield@1.4.0` (MIT). It runs cleanly here via
  `npx -y ecc-agentshield@1.4.0 scan --format json` and returns a
  jq-parseable report (`summary.critical`, `summary.high`).
- AgentShield's default target is a Claude Code config directory; with no
  `.claude/` present it reports `filesScanned: 0` and grade A. It is a
  supplementary check, not a substitute for the secrets scan.
- `shellcheck` is **not** installed in the Arena sandbox, so `shell_lint`
  skips locally and runs in CI. `python3` has no `yaml` module locally;
  `workflows_yaml` therefore uses Node's bundled `node:util`-free JSON/YAML
  parse path only when available, and skips otherwise — CI covers it.
- `gh api` is the reliable route to upstream truth: egress allows
  `github.com`, `api.github.com`, `registry.npmjs.org`, `pypi.org`,
  `files.pythonhosted.org` and little else.

**Dead ends / traps:**

- Upstream ECC ships harness-specific *copies* of many skills under
  `skills/.agents/`, `skills/.cursor/`, `skills/.kiro/`, and `docs/<locale>/`.
  A skill name therefore appears at several paths. Fetch the canonical
  `skills/<name>/SKILL.md`; a wrong prefix returns HTTP 404 with an empty body
  and no useful message. All 17 paths cited in `.ecc/UPSTREAM.md` were
  re-verified to exist at `v2.2.0`.
- `tr -d '\\n'` does not strip the JSON `\n` escapes in a GitHub API base64
  payload — it deletes backslashes and every letter `n`. Use `jq -r
  '.content'` to decode. This silently corrupted 15 of 17 files in the first
  version of `scripts/sync-ecc.sh --fetch`.
- GitHub Actions has no official `setup-shellcheck` action; ubuntu runners
  already ship shellcheck. Pin `actions/checkout` and `actions/setup-node` by
  commit SHA verified against their tags.
- **shellcheck findings are version-dependent.** The runner's apt shellcheck is
  0.9.0; `shellcheck-py` on PyPI is 0.11.0. For dynamically dispatched
  functions, 0.11 reports `SC2329` at the definition while 0.9 reports
  `SC2317` on every line inside. Suppressing only one made the gate pass
  locally and fail in CI on both jobs. Lesson: lint gates must be validated
  against the CI toolchain version, not just the local one — install the
  matching version (`pip install shellcheck-py==0.9.0.5`) before claiming a
  lint gate is green.
- **Actions log downloads are egress-blocked.** `gh run view --log-failed`
  fails because `results-receiver.actions.githubusercontent.com` is outside the
  allowlist. The check-run annotations API on `api.github.com` works but only
  returns "Process completed with exit code 1". Diagnose CI failures by
  reproducing the runner's toolchain locally.

**Next:** Independent ChatGPT review of the PR diff; then Stage 1 items in
[ROADMAP.md](ROADMAP.md) — the highest-value one is exercising the protocol on
a real issue and recording the friction here.

---

## 2026-09-06 — Sync Ditto with App-Factory foundation v0.1.0

**Done:** Ported the reviewed reusable foundation from
`anthracite-labs/App-Factory@ffe4382677c5237d2c86066c96742cf96a5f10fe` into
Ditto's existing engineering system. This is an **App-Factory foundation sync,
not an ECC upgrade**. The root `FOUNDATION_VERSION` is `0.1.0`; the ECC pin is
still `2.2.0` / `v2.2.0` /
`5eddf1a3ffd311423be2d4ba7d26f7209c91b033`, with AgentShield still `1.4.0`.
The written migration plan was committed before implementation; see
[the plan](plans/2026-09-06-foundation-v0.1.0-sync.md).

- Added committed lifecycle state: Ditto / ditto / **discovery** /
  `ALLOW_APP_STACK=0` / empty `STACK_DECISION_ADR`. The product is still
  undefined, so architecture would have been an invented advancement.
- Ported foundation/version checks, shared accepted-stack validation,
  lifecycle-aware bootstrap, safe identity-only initialization, structural
  ruleset validation, stronger CI contracts and all applicable source tests.
- Extended the source hardening where needed: every lifecycle key is validated
  in standalone mode; ADR metadata is exact and unambiguous, including matching
  fence delimiters/lengths and comment handling; ADR/config paths cannot use
  traversal or symlinks. Init refuses malformed state and newline arguments,
  writes atomically and preserves phase, allow flag and ADR under `--force`.
- Kept the secrets scanner exemption-free and fixed filename-based disclosure:
  matched text is removed before capture, and the gate banner never echoes
  unvalidated foundation/lifecycle values. `.env*` detection has no depth limit;
  only regular `.env.example` templates are allowed and still secret-scanned.
- CI checks actual commands, required jobs, event coverage, pinned actions,
  read-only permissions and checkout/environment settings. Both jobs validate
  the actual contracts; a bare allow flag no longer stands down the independent
  check. The portable JSON rejects duplicate/decoy fields, extra or duplicate
  contexts and nested instance IDs.
- AgentShield still reports zero-file scans as **SKIP/advisory**. Malformed
  summaries are rejected rather than interpreted as zeroes, and the package pin
  is rechecked before any standalone invocation. Test reports never leak values.

**Preserved:** Every prior entry above is byte-for-byte intact. Existing
product/domain/architecture/roadmap documents, `ARENA_CAPABILITIES.md`, the ADR
template and ADRs 0001–0003 are unchanged. Existing `.ecc/VERSION` and
`.ecc/UPSTREAM.md` remain exact prefixes with a separately appended foundation
sync record; `.ecc/LICENSE-ECC` remains unchanged. No product, framework,
database, auth, hosting or UI was chosen. No App-Factory generic project history
or reset documents were imported.

**Verified in this session:**

- Downloaded the pinned App-Factory archive outside Ditto and verified all 50
  files against the pinned Git tree's blob hashes; GitHub `main` matched the pin.
- Before changes: `bash scripts/verify.sh` → **14 passed, 0 failed, 1 skipped**;
  `bash scripts/selftest.sh` → **28/28**.
- New regression cases were run RED against the old/initially ported gate, then
  GREEN after the fixes; negative assertions require the intended named failure
  and exit 1, not an arbitrary runner error.
- With **both ShellCheck 0.9.0 and 0.11.0**, `bash scripts/verify.sh` →
  **17 passed, 0 failed, 1 skipped** (only AgentShield, which ran but scanned
  zero files); `bash scripts/selftest.sh` → **257/257 cases**. Style-level
  ShellCheck also ran directly against all five shell scripts under both versions.
- Fetched ECC's upstream licence at the unchanged commit and compared bytes:
  sha256 `326146379f01bb137c0a5d3c54770c1aa31076705c8b88a7f6b26a460f6221b2`.
  Peeled the annotated `v2.2.0` tag to confirm the exact ECC commit. Also checked
  both Actions pins against their recorded release tags.
- Read the live main ruleset and effective branch rules. **Main is protected**,
  with PRs, review-thread resolution, strict checks and creation/deletion/
  force-push protections. Required job names are exactly **Foundation gate**
  and **Independent checks**. No live administrative settings were changed.

**Learned / corrections to older observations:**

- Earlier entries correctly recorded main protection as pending *then*. It is
  active now. Preserve those observations rather than rewriting project history.
- The live solo-owner ruleset requires zero human approvals and the connection
  reports bypass capability. That is not platform enforcement of independent
  ChatGPT review or no self-merge. Those remain explicit operational rules;
  administrators should audit bypass and approval policy separately.
- A portable request body must not be a raw GitHub export. Ditto retains its
  creation and unattributed-change protections; App-Factory's stale-review
  dismissal is proposed in the payload but not silently applied to live settings.
- Line-oriented matching is unsafe at several boundaries: filename delimiters
  can disclose secrets, multiline init arguments can inject assignments, and
  arbitrary fence toggling can turn examples into approval metadata.
- Python/PyYAML are now required for structural CI validation. Install tooling in
  an isolated directory outside the repo; no application dependency manifest
  was introduced to run engineering tests.

**Next:** Leave the migration PR open for independent ChatGPT review of the real
diff; never self-merge or push to main. Check the PR's actual GitHub CI results,
not just this local record. [ADR-0004](decisions/0004-foundation-lifecycle-sync.md)
remains proposed until review is accepted. See [FOUNDATION.md](FOUNDATION.md) for
the explicit source differences, lifecycle contract and human-only admin audit.
Product definition remains the product owner's next decision, not an agent's.

---

## 2026-09-07 — PR #4 ADR/review-status consistency

**Done:** Addressed the [latest independent ChatGPT review](https://github.com/anthracite-labs/Ditto/pull/4#pullrequestreview-5127176109),
which accepted the implementation on `ead7d10f618b21d19a81b723eb7e2023f2918ef7`
and requested only ADR/review-status consistency. ADR-0004 and its index now
record **accepted**, and its directly related wording records the completed
review rather than a pending one. The PR review checkbox/body is updated to
match. This entry supersedes the earlier pending-review observation without
rewriting that historical entry.

**Scope:** Documentation/status only. No changes to scripts, self-tests, CI,
config, provenance, application lifecycle, or earlier ADRs. Acceptance of this
foundation ADR does not authorize an application stack: Ditto remains discovery
with `ALLOW_APP_STACK=0` and an empty stack ADR.

**Verified:** Serial runs with both ShellCheck **0.9.0** and **0.11.0** passed:
`bash scripts/verify.sh` **17 passed, 0 failed, 1 skipped** (AgentShield ran but
scanned zero files; advisory only); `bash scripts/selftest.sh` **257/257**.
Style-level ShellCheck passed under both versions. One initial parallel local
run reported a `skill_index/unrouted-workflow` assertion failure (256/257); the
same gate/assertion pair passed 50 isolated executions and both full serial
reruns passed. The cause was not established; no harness change was made.

**Next:** Check fresh CI on the status-only follow-up and leave PR #4 open for
reviewer/maintainer handling. No self-merge, main push or administrative change.
