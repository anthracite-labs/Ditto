# Project Memory

Append-only ledger of what sessions did, verified, and learned. **Append, never
rewrite** — corrections are new entries. See
[`.ecc/skills/project-memory.md`](../.ecc/skills/project-memory.md) for the
procedure.

Durable trade-offs belong in [decisions/](decisions/README.md), not here.

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

**Next:** Independent ChatGPT review of the PR diff; then Stage 1 items in
[ROADMAP.md](ROADMAP.md) — the highest-value one is exercising the protocol on
a real issue and recording the friction here.
