#!/usr/bin/env bash
# Negative tests for the Ditto verification gate.
#
# A gate that only ever passes proves nothing. This script injects faults into
# a THROWAWAY COPY of the repository and asserts that scripts/verify.sh exits
# non-zero for each one. It never modifies the real working tree.
#
# Two cases exist specifically because of independent review findings:
#
#   secrets/redaction        an injected credential must fail the gate WITHOUT
#                            the credential itself appearing in stdout/stderr,
#                            so the detector cannot become a disclosure path.
#   secrets/bypass-*         a credential must still be caught when the same
#                            line also contains a word such as "example" or
#                            "TODO" - there is no whole-line allowlist.
#
# Usage:
#   scripts/selftest.sh              run every case
#   scripts/selftest.sh --keep       keep the throwaway copy for inspection
#   scripts/selftest.sh --quiet      summary only
#
# Exit status: 0 when every case behaved as asserted, 1 otherwise.

# Lint note: SC2317/SC2329 are suppressed because cleanup() is invoked only via
# the EXIT trap, which the linter does not treat as a call site. See the same
# note in scripts/verify.sh.
# shellcheck disable=SC2317,SC2329

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

KEEP=0
QUIET=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1 ;;
    --quiet|-q) QUIET=1 ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'selftest.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ditto-selftest.XXXXXX")" || exit 2
SANDBOX="${WORK_DIR}/repo"
cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    printf 'kept throwaway copy at: %s\n' "$SANDBOX"
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

PASS=0
FAIL=0
FAILED_CASES=()

note() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

ok() {
  PASS=$((PASS + 1))
  printf '  ok   %-34s %s\n' "$1" "$2"
}

bad() {
  FAIL=$((FAIL + 1))
  FAILED_CASES+=("$1: $2")
  printf '  FAIL %-34s %s\n' "$1" "$2"
}

# reset_sandbox restores a pristine copy of the repository.
reset_sandbox() {
  rm -rf "$SANDBOX"
  cp -a "$REPO_ROOT" "$SANDBOX" || return 1
  # The copy's git metadata is intact, so index-aware checks behave normally.
  return 0
}

# gate runs verify.sh inside the sandbox, capturing combined output.
# Sets GATE_RC and GATE_OUT.
GATE_RC=0
GATE_OUT=""
gate() {
  GATE_OUT="$(cd "$SANDBOX" && bash scripts/verify.sh --skip-agentshield "$@" 2>&1)"
  GATE_RC=$?
  return 0
}

# expect_fail asserts the gate rejected the injected fault.
expect_fail() {
  local case_name="$1"; shift
  gate "$@"
  if [ "$GATE_RC" -eq 0 ]; then
    bad "$case_name" "gate exited 0; the fault was not caught"
    return 1
  fi
  ok "$case_name" "exit $GATE_RC"
}

# expect_pass asserts the gate accepted a legitimate exemption.
expect_pass() {
  local case_name="$1"; shift
  gate "$@"
  if [ "$GATE_RC" -ne 0 ]; then
    bad "$case_name" "gate exited $GATE_RC on an input that should pass"
    return 1
  fi
  ok "$case_name" "exit 0"
}

# ---------------------------------------------------------------------------
note "Ditto verification gate — negative tests"
note "  source:   $REPO_ROOT"
note "  sandbox:  $SANDBOX"
note "------------------------------------------------------------"

if ! reset_sandbox; then
  printf 'selftest.sh: could not create a throwaway copy\n' >&2
  exit 1
fi

# Baseline: the pristine copy must pass, otherwise every later assertion is
# meaningless.
gate
if [ "$GATE_RC" -ne 0 ]; then
  printf 'selftest.sh: baseline gate run failed (exit %s); aborting\n' "$GATE_RC" >&2
  printf '%s\n' "$GATE_OUT" >&2
  exit 1
fi
ok "baseline/pristine-copy" "exit 0"

# --- Finding 1: redaction ----------------------------------------------------
# A committed credential must fail the gate, and the credential itself must
# never reach stdout or stderr.
CANARY_TOKEN='ghp_''SyntheticLeakCanary0123456789abcdefgh'
reset_sandbox
printf 'DEPLOY_KEY="%s"\n' "$CANARY_TOKEN" > "${SANDBOX}/.selftest-leak.txt"
gate --only=secrets
if [ "$GATE_RC" -eq 0 ]; then
  bad "secrets/redaction" "gate exited 0 on an injected credential"
elif printf '%s' "$GATE_OUT" | grep -qF 'SyntheticLeakCanary'; then
  bad "secrets/redaction" "gate FAILED correctly but LEAKED the value into its output"
else
  ok "secrets/redaction" "exit $GATE_RC, value not present in output"
fi

# --- Finding 2: no whole-line bypass ----------------------------------------
# The same credential must still be caught when the line also contains a word
# that the old allowlist would have used to skip the entire line.
for word in example todo sample placeholder 'n/a'; do
  reset_sandbox
  # Assembled from fragments so the pattern does not match this file's source.
  printf '# %s note: DITTO_REVIEW_%s=%s\n' \
    "$word" 'TOKEN' 'SyntheticBypassValue0123456789' \
    > "${SANDBOX}/.selftest-bypass.txt"
  expect_fail "secrets/bypass-${word}" --only=secrets
done

# A real-looking AWS key id on a line that says "example". AKIA + 16 chars.
reset_sandbox
printf 'aws_key = "AK%s"  # example\n' "IASYNTHETIC0000000" > "${SANDBOX}/.selftest-aws.txt"
expect_fail "secrets/bypass-aws-example" --only=secrets

# --- Placeholder-shaped values are NOT exempt --------------------------------
# A structurally simple value can still be a real password, so repeated-character
# values must be caught. These cases exist because an earlier revision exempted
# them, which was a bypass: an all-x PASSWORD assignment passed the gate.
reset_sandbox
printf '%s=%s\n' 'PASSWORD' 'xxxxxxxxxxxxxxxxxxxxxxxx' > "${SANDBOX}/.selftest-repeat-x.txt"
expect_fail "secrets/repeated-char-password" --only=secrets

reset_sandbox
printf '%s=%s\n' 'TOKEN' '0000000000000000' > "${SANDBOX}/.selftest-repeat-0.txt"
expect_fail "secrets/repeated-char-token" --only=secrets

# Documentation placeholders must not be credential-shaped in the first place.
# An angle-bracket value does not match the credential patterns, so it passes -
# because it never matches, not because the scanner exempts it.
reset_sandbox
printf 'DITTO_REVIEW_%s=%s\n' 'TOKEN' '<your-token-here-0123456789>' > "${SANDBOX}/.selftest-angle.txt"
expect_pass "secrets/angle-bracket-not-credential-shaped" --only=secrets

# An empty value is likewise not credential-shaped.
reset_sandbox
printf 'DITTO_REVIEW_%s=\n' 'TOKEN' > "${SANDBOX}/.selftest-empty.txt"
expect_pass "secrets/empty-value-not-credential-shaped" --only=secrets

# Redaction must hold for the repeated-char shape too, since that is now a
# finding rather than an exemption.
reset_sandbox
printf '%s=%s\n' 'PASSWORD' 'SyntheticRepeatCanary0123456789' > "${SANDBOX}/.selftest-leak2.txt"
gate --only=secrets
if [ "$GATE_RC" -eq 0 ]; then
  bad "secrets/redaction-repeated-char" "gate exited 0 on an injected credential"
elif printf '%s' "$GATE_OUT" | grep -qF 'SyntheticRepeatCanary'; then
  bad "secrets/redaction-repeated-char" "gate FAILED correctly but LEAKED the value"
else
  ok "secrets/redaction-repeated-char" "exit $GATE_RC, value not present in output"
fi

# --- dotenv enforcement ------------------------------------------------------
reset_sandbox
printf 'DITTO_REVIEW_%s=%s\n' 'TOKEN' 'SyntheticDotenvValue0123456789' > "${SANDBOX}/.env"
expect_fail "env_files/dotenv-present" --only=env_files

# .env.example is the one allowed template.
reset_sandbox
printf 'DITTO_REVIEW_TOKEN=\n' > "${SANDBOX}/.env.example"
expect_pass "env_files/dotenv-example-allowed" --only=env_files

# --- Remaining gate checks ---------------------------------------------------
reset_sandbox
printf '\nSee [missing](docs/DOES_NOT_EXIST.md).\n' >> "${SANDBOX}/README.md"
expect_fail "links/broken-markdown-link" --only=links

reset_sandbox
chmod -x "${SANDBOX}/scripts/sync-ecc.sh"
expect_fail "executable/bit-removed" --only=executable

reset_sandbox
printf '{"name":"ditto"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/package-json" --only=no_app_stack

reset_sandbox
sed -i 's/Adapted from ECC v2.2.0/Adapted from nowhere/' "${SANDBOX}/.ecc/rules/git.md"
expect_fail "attribution/header-removed" --only=attribution

reset_sandbox
printf '\n# unrouted\n' > "${SANDBOX}/.ecc/skills/unrouted.md"
expect_fail "skill_index/unrouted-workflow" --only=skill_index

reset_sandbox
# Single quotes are deliberate: the injected index row must contain literal
# backticks, not a command substitution.
# shellcheck disable=SC2016
printf '\n| Ghost | `.ecc/skills/ghost.md` | x | y |\n' >> "${SANDBOX}/.ecc/skills/INDEX.md"
expect_fail "skill_index/dangling-row" --only=skill_index

reset_sandbox
sed -i 's/^UPSTREAM_COMMIT=.*/UPSTREAM_COMMIT=deadbeef/' "${SANDBOX}/.ecc/VERSION"
expect_fail "provenance/commit-corrupted" --only=provenance

reset_sandbox
printf 'tampered\n' >> "${SANDBOX}/.ecc/LICENSE-ECC"
expect_fail "provenance/mit-notice-tampered" --only=provenance

reset_sandbox
rm -f "${SANDBOX}/.ecc/LICENSE-ECC"
expect_fail "provenance/mit-notice-missing" --only=provenance

reset_sandbox
printf '\n  bad: [unclosed\n' >> "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "workflows_yaml/corrupted" --only=workflows_yaml

reset_sandbox
sed -i 's/^  pull_request:/  merge_group:/' "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "ci_wiring/trigger-removed" --only=ci_wiring

reset_sandbox
printf '\nAlso see .ecc/skills/nonexistent.md\n' >> "${SANDBOX}/.ecc/BOOTSTRAP.md"
expect_fail "bootstrap/dangling-path" --only=bootstrap

reset_sandbox
rm -f "${SANDBOX}/docs/DOMAIN.md"
expect_fail "foundation/required-doc-deleted" --only=foundation

note "------------------------------------------------------------"
if [ "$FAIL" -gt 0 ]; then
  printf 'SELFTEST: FAIL — %d passed, %d failed\n' "$PASS" "$FAIL"
  printf '\nFailed cases:\n'
  for c in "${FAILED_CASES[@]}"; do
    printf '  - %s\n' "$c"
  done
  exit 1
fi
printf 'SELFTEST: PASS — %d cases behaved as asserted\n' "$PASS"
exit 0
