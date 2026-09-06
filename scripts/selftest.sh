#!/usr/bin/env bash
# Negative tests for the Ditto verification gate.
#
# A gate that only ever passes proves nothing. This script injects faults into
# a THROWAWAY COPY of the repository and asserts that scripts/verify.sh exits
# non-zero for each one. It never modifies the real working tree.
#
# Cases that exist specifically because of independent review findings:
#
#   secrets/redaction        an injected credential must fail the gate WITHOUT
#                            the credential itself appearing in stdout/stderr,
#                            so the detector cannot become a disclosure path.
#   secrets/bypass-*         a credential must still be caught when the same
#                            line also contains a word such as "example" or
#                            "TODO" - there is no whole-line allowlist.
#
# Lifecycle-specific cases prove the lifecycle guard in BOTH directions: a stack
# artifact is rejected before the transition, and the foundation no-stack guard
# stands down after an explicit, ADR-backed transition - while an unjustified
# transition is still rejected.
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
    -h|--help) sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  printf '  ok   %-40s %s\n' "$1" "$2"
}

bad() {
  FAIL=$((FAIL + 1))
  FAILED_CASES+=("$1: $2")
  printf '  FAIL %-40s %s\n' "$1" "$2"
}

# reset_sandbox restores a pristine copy of the repository.
reset_sandbox() {
  if ! rm -rf -- "$SANDBOX" || ! cp -a -- "$REPO_ROOT" "$SANDBOX"; then
    printf 'selftest.sh: could not reset the throwaway copy; aborting\n' >&2
    exit 1
  fi
  # The copy's git metadata is intact, so index-aware checks behave normally.
  return 0
}

# set_config rewrites one key in the sandbox's lifecycle config.
set_config() {
  local key="$1" value="$2"
  local file="${SANDBOX}/config/project.env"
  awk -v k="$key" -v v="$value" '
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { print k "=" v; next }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
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
  local expected_check="${case_name%%/*}"
  if [ "$GATE_RC" -ne 1 ] ||
     ! printf '%s' "$GATE_OUT" | grep -qE "\[FAIL\][[:space:]]+${expected_check}([[:space:]]|$)"; then
    bad "$case_name" "expected named ${expected_check} failure and exit 1; got exit ${GATE_RC}"
    return 1
  fi
  ok "$case_name" "named failure, exit 1"
}

# expect_pass asserts the gate accepted a legitimate input.
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

# A credential smuggled into the lifecycle config must be caught twice: by the
# secrets sweep and by the lifecycle check's own guard.
reset_sandbox
printf '%s=%s\n' 'DEPLOY_TOKEN' 'SyntheticConfigValue0123456789' >> "${SANDBOX}/config/project.env"
expect_fail "lifecycle/credential-in-project-env" --only=lifecycle

# --- dotenv enforcement ------------------------------------------------------
reset_sandbox
printf 'DITTO_REVIEW_%s=%s\n' 'TOKEN' 'SyntheticDotenvValue0123456789' > "${SANDBOX}/.env"
expect_fail "env_files/dotenv-present" --only=env_files

# .env.example is the one allowed template.
reset_sandbox
printf 'DITTO_REVIEW_TOKEN=\n' > "${SANDBOX}/.env.example"
expect_pass "env_files/dotenv-example-allowed" --only=env_files

# config/project.env is committed lifecycle state, not a dotenv file, and must
# not be caught by the dotenv policy.
reset_sandbox
expect_pass "env_files/project-env-not-a-dotenv" --only=env_files

# --- Lifecycle-aware no-stack guard -----------------------------------------
# 1. Before any transition, an application-stack artifact is rejected.
reset_sandbox
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/package-json" --only=no_app_stack

reset_sandbox
set_config PROJECT_PHASE discovery
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/rejected-in-discovery-phase" --only=no_app_stack

reset_sandbox
set_config PROJECT_PHASE architecture
mkdir -p "${SANDBOX}/src"
printf 'placeholder\n' > "${SANDBOX}/src/.keep"
expect_fail "no_app_stack/rejected-src-dir-in-architecture" --only=no_app_stack

# 2. After an explicit, ADR-backed transition, the FOUNDATION guard stands
#    down. This proves the guard is lifecycle state, not a permanent constant.
# write_stack_adr creates an ADR fixture in the sandbox.
#   $1 file name
#   $2 status line value
#   $3 marker placement: marked | unmarked | commented | fenced
write_stack_adr() {
  local file="$1" status="$2" marked="$3"
  {
    printf '# ADR-0099: Selftest stack decision fixture\n\n'
    printf '**Date:** 2026-09-06\n'
    printf '**Status:** %s\n' "$status"
    case "$marked" in
      marked)
        printf '**Decision Type:** application-stack\n'
        ;;
      commented)
        # The marker present ONLY inside an HTML comment must not count.
        printf '<!-- **Decision Type:** application-stack -->\n'
        ;;
      fenced)
        # The marker present ONLY inside a code fence must not count.
        # shellcheck disable=SC2016  # literal backticks are the point here.
        printf '\n```text\n**Decision Type:** application-stack\n```\n'
        ;;
    esac
    printf '**Deciders:** selftest fixture\n\n'
    printf '## Context\n\nFixture used by scripts/selftest.sh.\n'
  } > "${SANDBOX}/docs/decisions/${file}"
}

# copy_template_adr reproduces the most likely real-world accident: a
# maintainer copies the shipped ADR template to a new filename, flips only the
# status to accepted, and leaves the template's instructional comment intact.
copy_template_adr() {
  local file="$1" status="$2"
  sed "s/^\\*\\*Status:\\*\\* proposed.*/**Status:** ${status}/" \
    "${SANDBOX}/docs/decisions/0000-template.md" \
    > "${SANDBOX}/docs/decisions/${file}"
}

# transition_to points the sandbox at an ADR and enables application mode.
transition_to() {
  set_config PROJECT_PHASE implementation
  set_config ALLOW_APP_STACK 1
  set_config STACK_DECISION_ADR "docs/decisions/$1"
}

reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted marked
transition_to 0099-selftest-stack.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_pass "no_app_stack/stands-down-after-transition" --only=no_app_stack
if printf '%s' "$GATE_OUT" | grep -q 'SKIP.*no_app_stack'; then
  ok "no_app_stack/reports-skip-not-pass" "guard reported as SKIP, not a vacuous PASS"
else
  bad "no_app_stack/reports-skip-not-pass" "expected a SKIP line for no_app_stack"
fi

# The same transitioned state must be accepted by the lifecycle check itself.
expect_pass "lifecycle/valid-transition-accepted" --only=lifecycle

# 3. The transition must be explicit and documented, not an ad-hoc edit.
reset_sandbox
set_config ALLOW_APP_STACK 1
expect_fail "lifecycle/allow-without-phase-or-adr" --only=lifecycle

reset_sandbox
set_config PROJECT_PHASE implementation
set_config ALLOW_APP_STACK 1
expect_fail "lifecycle/allow-without-adr" --only=lifecycle

reset_sandbox
set_config PROJECT_PHASE implementation
set_config ALLOW_APP_STACK 1
set_config STACK_DECISION_ADR docs/decisions/0999-does-not-exist.md
expect_fail "lifecycle/adr-file-missing" --only=lifecycle

reset_sandbox
set_config ALLOW_APP_STACK 1
set_config PROJECT_PHASE discovery
set_config STACK_DECISION_ADR docs/decisions/0000-template.md
expect_fail "lifecycle/allow-in-wrong-phase" --only=lifecycle

# The referenced ADR must actually record an ACCEPTED APPLICATION-STACK
# decision. Existing on disk is not approval: the template ships in every
# repository, and so do the foundation ADRs. Without these cases the
# "ADR-backed" guarantee is decorative.
reset_sandbox
transition_to 0000-template.md
expect_fail "lifecycle/adr-is-the-template" --only=lifecycle

reset_sandbox
transition_to 0002-verification-gate.md
expect_fail "lifecycle/adr-unrelated-but-accepted" --only=lifecycle

reset_sandbox
write_stack_adr 0099-selftest-stack.md proposed marked
transition_to 0099-selftest-stack.md
expect_fail "lifecycle/adr-stack-but-only-proposed" --only=lifecycle

reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted unmarked
transition_to 0099-selftest-stack.md
expect_fail "lifecycle/adr-accepted-but-not-a-stack-decision" --only=lifecycle

# --- Round 3: markers must be REAL metadata lines ---------------------------
# Substring matching was a live bypass. The shipped template carried the
# literal marker inside an instructional HTML comment, so copying it to a new
# filename and flipping only the status produced an "unrelated ADR" that
# satisfied both checks. Comments, code fences and prose must never authorise
# a transition.
reset_sandbox
copy_template_adr 0005-copied-template.md accepted
transition_to 0005-copied-template.md
expect_fail "lifecycle/copied-template-marker-in-comment" --only=lifecycle

reset_sandbox
copy_template_adr 0005-copied-template.md accepted
transition_to 0005-copied-template.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-copied-template-fails-closed" --only=no_app_stack

reset_sandbox
write_stack_adr 0099-selftest-stack.md proposed commented
transition_to 0099-selftest-stack.md
expect_fail "lifecycle/marker-only-in-html-comment" --only=lifecycle

reset_sandbox
write_stack_adr 0099-selftest-stack.md proposed commented
transition_to 0099-selftest-stack.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-marker-in-comment-fails-closed" --only=no_app_stack

reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted fenced
transition_to 0099-selftest-stack.md
expect_fail "lifecycle/marker-only-in-code-fence" --only=lifecycle

# An accepted status that exists only inside a comment must not count either.
reset_sandbox
write_stack_adr 0099-selftest-stack.md proposed marked
printf '<!-- **Status:** accepted -->\n' >> "${SANDBOX}/docs/decisions/0099-selftest-stack.md"
transition_to 0099-selftest-stack.md
expect_fail "lifecycle/accepted-status-only-in-comment" --only=lifecycle

reset_sandbox
write_stack_adr 0099-selftest-stack.md proposed marked
printf '<!-- **Status:** accepted -->\n' >> "${SANDBOX}/docs/decisions/0099-selftest-stack.md"
transition_to 0099-selftest-stack.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-status-in-comment-fails-closed" --only=no_app_stack

# Prose mentioning the marker is not a decision: the match must be whole-line.
reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted unmarked
printf 'This ADR is not **Decision Type:** application-stack related.\n' \
  >> "${SANDBOX}/docs/decisions/0099-selftest-stack.md"
transition_to 0099-selftest-stack.md
expect_fail "lifecycle/marker-as-substring-of-prose" --only=lifecycle

# The shipped template must not itself contain an active marker, or every copy
# of it inherits one. This pins the sanitised template as a durable property.
reset_sandbox
if grep -qE '^[[:space:]]*\*\*Decision Type:\*\* application-stack[[:space:]]*$' \
  "${SANDBOX}/docs/decisions/0000-template.md"; then
  bad "template/no-active-stack-marker" "the ADR template carries an active stack marker"
else
  ok "template/no-active-stack-marker" "template has no active marker line"
fi

# Documentation may show the marker, but only inertly (fenced), so that
# docs/FOUNDATION.md can never authorise a transition if pointed at.
reset_sandbox
sed -i 's|^STACK_DECISION_ADR=.*|STACK_DECISION_ADR=docs/decisions/0000-template.md|' \
  "${SANDBOX}/config/project.env"
set_config PROJECT_PHASE implementation
set_config ALLOW_APP_STACK 1
expect_fail "lifecycle/template-path-still-rejected" --only=lifecycle

# The same rejections must hold when no_app_stack runs ALONE. verify.sh
# supports --only=NAME, so this check must not assume check_lifecycle ran; if
# it trusts an unvalidated ALLOW_APP_STACK=1 it stands the guard down on an
# invalid state.
reset_sandbox
set_config ALLOW_APP_STACK 1
set_config PROJECT_PHASE discovery
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-wrong-phase-fails-closed" --only=no_app_stack

reset_sandbox
set_config PROJECT_PHASE implementation
set_config ALLOW_APP_STACK 1
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-missing-adr-fails-closed" --only=no_app_stack

reset_sandbox
transition_to 0000-template.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-template-adr-fails-closed" --only=no_app_stack

reset_sandbox
transition_to 0002-verification-gate.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-unrelated-adr-fails-closed" --only=no_app_stack

reset_sandbox
write_stack_adr 0099-selftest-stack.md proposed marked
transition_to 0099-selftest-stack.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-unaccepted-adr-fails-closed" --only=no_app_stack

reset_sandbox
transition_to 0999-does-not-exist.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-missing-adr-file-fails-closed" --only=no_app_stack

# Duplicate assignments make committed lifecycle state ambiguous.
reset_sandbox
printf 'PROJECT_PHASE=implementation\n' >> "${SANDBOX}/config/project.env"
expect_fail "lifecycle/duplicate-phase-key" --only=lifecycle

reset_sandbox
printf 'ALLOW_APP_STACK=1\n' >> "${SANDBOX}/config/project.env"
expect_fail "lifecycle/duplicate-allow-key" --only=lifecycle

# --- Round 3: cardinality must be counted correctly -------------------------
# `grep -c` prints 0 AND exits 1 on no match, so the old
# `grep -c ... || printf '0'` emitted "0\n0" and every numeric test on it was
# a silent syntax error. A missing required key that broke no later semantic
# check therefore evaded detection entirely. Each required key is removed
# individually here so the counting cannot regress unnoticed.
for missing_key in PROJECT_NAME PROJECT_SLUG PROJECT_PHASE ALLOW_APP_STACK STACK_DECISION_ADR; do
  reset_sandbox
  sed -i "/^${missing_key}=/d" "${SANDBOX}/config/project.env"
  expect_fail "lifecycle/missing-${missing_key}" --only=lifecycle
done

# Duplicates of the remaining required keys are ambiguous too.
reset_sandbox
printf 'PROJECT_NAME=Second Name\n' >> "${SANDBOX}/config/project.env"
expect_fail "lifecycle/duplicate-name-key" --only=lifecycle

reset_sandbox
printf 'STACK_DECISION_ADR=docs/decisions/0004-foundation-lifecycle-sync.md\n' \
  >> "${SANDBOX}/config/project.env"
expect_fail "lifecycle/duplicate-stack-adr-key" --only=lifecycle

# --- Round 3: standalone guard must reject ambiguous state ------------------
# config_value takes the FIRST assignment, so a valid transition followed by a
# conflicting duplicate would let --only=no_app_stack stand the guard down on
# a config the full gate rejects. The shared validator now enforces cardinality
# itself. Each case below has a VALID first set of values.
reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted marked
transition_to 0099-selftest-stack.md
printf 'PROJECT_PHASE=discovery\n' >> "${SANDBOX}/config/project.env"
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-duplicate-phase-fails-closed" --only=no_app_stack

reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted marked
transition_to 0099-selftest-stack.md
printf 'ALLOW_APP_STACK=0\n' >> "${SANDBOX}/config/project.env"
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-duplicate-allow-fails-closed" --only=no_app_stack

reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted marked
transition_to 0099-selftest-stack.md
printf 'STACK_DECISION_ADR=docs/decisions/0000-template.md\n' \
  >> "${SANDBOX}/config/project.env"
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/only-duplicate-stack-adr-fails-closed" --only=no_app_stack

# Positive control: the same fixture WITHOUT a duplicate must still stand down,
# so the cardinality rule cannot pass by rejecting everything.
reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted marked
transition_to 0099-selftest-stack.md
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_pass "no_app_stack/only-valid-single-assignment-stands-down" --only=no_app_stack

# 4. Malformed lifecycle configuration is rejected.
reset_sandbox
set_config PROJECT_PHASE shipping
expect_fail "lifecycle/unknown-phase" --only=lifecycle

reset_sandbox
set_config ALLOW_APP_STACK yes
expect_fail "lifecycle/non-boolean-allow-flag" --only=lifecycle

reset_sandbox
set_config PROJECT_SLUG 'Not A Slug'
expect_fail "lifecycle/invalid-slug" --only=lifecycle

reset_sandbox
printf 'this is not a key value line\n' >> "${SANDBOX}/config/project.env"
expect_fail "lifecycle/malformed-line" --only=lifecycle

reset_sandbox
sed -i '/^PROJECT_PHASE=/d' "${SANDBOX}/config/project.env"
expect_fail "lifecycle/required-key-removed" --only=lifecycle

reset_sandbox
rm -f "${SANDBOX}/config/project.env"
expect_fail "lifecycle/config-deleted" --only=lifecycle

# The guard must fail closed when the config cannot be read at all.
reset_sandbox
rm -f "${SANDBOX}/config/project.env"
printf '{"name":"placeholder"}\n' > "${SANDBOX}/package.json"
expect_fail "no_app_stack/fails-closed-without-config" --only=no_app_stack

# --- FOUNDATION_VERSION ------------------------------------------------------
reset_sandbox
printf 'v1\n' > "${SANDBOX}/FOUNDATION_VERSION"
expect_fail "foundation_version/not-semver" --only=foundation_version

reset_sandbox
printf '0.1\n' > "${SANDBOX}/FOUNDATION_VERSION"
expect_fail "foundation_version/incomplete-semver" --only=foundation_version

# Conceptual separation is proved by distinct files/fields, NOT by requiring
# the two versions to differ numerically: they may legitimately coincide, and
# an inequality rule would force an artificial bump. A foundation version that
# happens to equal the ECC version is therefore accepted...
reset_sandbox
printf '2.2.0\n' > "${SANDBOX}/FOUNDATION_VERSION"
expect_pass "foundation_version/may-coincide-with-ecc-version" --only=foundation_version

# ...but the two must remain independently declared. Collapsing ECC provenance
# into the foundation version file, or dropping it from .ecc/VERSION, is a
# real conflation and must fail.
reset_sandbox
printf '0.1.0\nUPSTREAM_VERSION=2.2.0\n' > "${SANDBOX}/FOUNDATION_VERSION"
expect_fail "foundation_version/carries-ecc-provenance" --only=foundation_version

reset_sandbox
sed -i '/^UPSTREAM_VERSION=/d' "${SANDBOX}/.ecc/VERSION"
expect_fail "foundation_version/ecc-version-not-declared" --only=foundation_version

reset_sandbox
rm -f "${SANDBOX}/FOUNDATION_VERSION"
expect_fail "foundation_version/missing" --only=foundation_version

# --- Portable ruleset --------------------------------------------------------
reset_sandbox
printf '{ broken\n' > "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/invalid-json" --only=ruleset

reset_sandbox
sed -i 's/"required_review_thread_resolution": true/"required_review_thread_resolution": false/' \
  "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/thread-resolution-disabled" --only=ruleset

reset_sandbox
sed -i 's/"strict_required_status_checks_policy": true/"strict_required_status_checks_policy": false/' \
  "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/strict-policy-disabled" --only=ruleset

reset_sandbox
sed -i 's/"Foundation gate"/"build"/' "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/required-context-renamed" --only=ruleset

reset_sandbox
sed -i 's/"type": "non_fast_forward"/"type": "creation"/' "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/force-push-protection-removed" --only=ruleset

reset_sandbox
sed -i 's/"type": "deletion"/"type": "creation"/' "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/deletion-protection-removed" --only=ruleset

reset_sandbox
sed -i 's/"bypass_actors": \[\]/"bypass_actors": [{"actor_id": 1, "actor_type": "OrganizationAdmin", "bypass_mode": "always"}]/' \
  "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/bypass-actor-added" --only=ruleset

reset_sandbox
sed -i 's/"name": "Main"/"name": "Main",\n  "id": 12345678,\n  "node_id": "RRS_placeholder"/' \
  "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/instance-ids-present" --only=ruleset

# Structural, not textual. A validator that greps for policy strings can be
# satisfied by putting them in the wrong place; these cases move required
# values to decoy locations while keeping the JSON syntactically valid.
ruleset_py() {
  RULESET="${SANDBOX}/config/main-ruleset.json" python3 - "$@" <<'PYEOF'
import json, os, sys
path = os.environ["RULESET"]
with open(path, encoding="utf-8") as fh:
    doc = json.load(fh)
exec(sys.argv[1])  # noqa: S102 - test fixture mutation, not repository code
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
}

# Required context present, but as a decoy top-level key rather than inside
# the required_status_checks rule.
reset_sandbox
ruleset_py '
for r in doc["rules"]:
    if r["type"] == "required_status_checks":
        r["parameters"]["required_status_checks"] = [{"context": "Independent checks"}]
doc["decoy_contexts"] = ["Foundation gate"]
'
expect_fail "ruleset/context-in-decoy-location" --only=ruleset

# Strict policy flag moved out of the rule parameters to the top level.
reset_sandbox
ruleset_py '
for r in doc["rules"]:
    if r["type"] == "required_status_checks":
        r["parameters"]["strict_required_status_checks_policy"] = False
doc["strict_required_status_checks_policy"] = True
'
expect_fail "ruleset/strict-flag-in-decoy-location" --only=ruleset

# Thread resolution moved out of the pull_request rule parameters.
reset_sandbox
ruleset_py '
for r in doc["rules"]:
    if r["type"] == "pull_request":
        del r["parameters"]["required_review_thread_resolution"]
doc["required_review_thread_resolution"] = True
'
expect_fail "ruleset/thread-resolution-in-decoy-location" --only=ruleset

# A bypass actor hidden behind an empty-looking decoy key.
reset_sandbox
ruleset_py '
doc["bypass_actors"] = [{"actor_id": 1, "actor_type": "OrganizationAdmin", "bypass_mode": "always"}]
doc["bypass_actors_note"] = []
'
expect_fail "ruleset/bypass-actor-with-decoy-empty-key" --only=ruleset

# The payload must be exactly the documented request body: no explanatory or
# undocumented keys, because it is applied verbatim.
reset_sandbox
ruleset_py 'doc["_comment"] = ["explanatory text does not belong in an API payload"]'
expect_fail "ruleset/undocumented-comment-key" --only=ruleset

# Rule present but duplicated with conflicting parameters.
reset_sandbox
ruleset_py 'doc["rules"].append({"type": "pull_request", "parameters": {"required_approving_review_count": 3}})'
expect_fail "ruleset/duplicate-rule-type" --only=ruleset

# Targeting a named branch instead of the portable default-branch token.
reset_sandbox
ruleset_py 'doc["conditions"]["ref_name"]["include"] = ["refs/heads/main"]'
expect_fail "ruleset/hardcoded-branch-not-portable" --only=ruleset

reset_sandbox
ruleset_py 'doc["enforcement"] = "evaluate"'
expect_fail "ruleset/not-actively-enforced" --only=ruleset

# --- CI wiring and the ruleset must agree ------------------------------------
reset_sandbox
sed -i 's/^    name: Foundation gate$/    name: Build/' "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "ci_wiring/required-job-renamed" --only=ci_wiring

reset_sandbox
sed -i 's/^    name: Independent checks$/    name: Extra/' "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "ci_wiring/second-required-job-renamed" --only=ci_wiring

reset_sandbox
sed -i 's|bash scripts/selftest.sh|true|' "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "ci_wiring/selftest-decoupled" --only=ci_wiring

reset_sandbox
sed -i 's/^  pull_request:/  merge_group:/' "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "ci_wiring/trigger-removed" --only=ci_wiring

reset_sandbox
sed -i 's|actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683|actions/checkout@v4|' \
  "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "ci_wiring/action-not-pinned-to-sha" --only=ci_wiring

reset_sandbox
sed -i 's/^  contents: read$/  contents: write/' "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "ci_wiring/least-privilege-removed" --only=ci_wiring

# --- Remaining gate checks ---------------------------------------------------
reset_sandbox
printf '\nSee [missing](docs/DOES_NOT_EXIST.md).\n' >> "${SANDBOX}/README.md"
expect_fail "links/broken-markdown-link" --only=links

reset_sandbox
chmod -x "${SANDBOX}/scripts/sync-ecc.sh"
expect_fail "executable/bit-removed" --only=executable

reset_sandbox
chmod -x "${SANDBOX}/scripts/init-project.sh"
expect_fail "executable/init-project-bit-removed" --only=executable

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
sed -i 's/^FOUNDATION_SOURCE_COMMIT=.*/FOUNDATION_SOURCE_COMMIT=unknown/' "${SANDBOX}/.ecc/VERSION"
expect_fail "provenance/foundation-provenance-corrupted" --only=provenance

reset_sandbox
sed -i 's/^ADAPTER_NATIVE_ECC_RUNTIME=false/ADAPTER_NATIVE_ECC_RUNTIME=true/' "${SANDBOX}/.ecc/VERSION"
expect_fail "provenance/false-native-ecc-claim" --only=provenance

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
printf '\nAlso see .ecc/skills/nonexistent.md\n' >> "${SANDBOX}/.ecc/BOOTSTRAP.md"
expect_fail "bootstrap/dangling-path" --only=bootstrap

reset_sandbox
# Remove every mention of the lifecycle config from the bootstrap protocol: a
# session that is never told to read it cannot know what phase it is in.
sed -i '/config\/project\.env/d' "${SANDBOX}/.ecc/BOOTSTRAP.md"
expect_fail "bootstrap/lifecycle-config-not-routed" --only=bootstrap

reset_sandbox
# Startup context must stay small; a bloated bootstrap defeats on-demand loading.
for _ in $(seq 1 250); do
  printf 'padding line that makes startup context large\n' >> "${SANDBOX}/.ecc/BOOTSTRAP.md"
done
expect_fail "bootstrap/startup-context-too-large" --only=bootstrap

reset_sandbox
rm -f "${SANDBOX}/docs/DOMAIN.md"
expect_fail "foundation/required-doc-deleted" --only=foundation

reset_sandbox
rm -f "${SANDBOX}/docs/FOUNDATION.md"
expect_fail "foundation/foundation-doc-deleted" --only=foundation

reset_sandbox
rm -f "${SANDBOX}/scripts/init-project.sh"
expect_fail "foundation/init-script-deleted" --only=foundation

# --- init-project.sh safety --------------------------------------------------
# The script must be non-destructive, idempotent, and must never commit, push,
# or touch provenance.
reset_sandbox
set_config PROJECT_NAME ''
set_config PROJECT_PHASE discovery
before_head="$(cd "$SANDBOX" && git rev-parse HEAD 2>/dev/null || echo none)"
before_version="$(sha256sum "${SANDBOX}/.ecc/VERSION" | cut -d' ' -f1)"
before_licence="$(sha256sum "${SANDBOX}/.ecc/LICENSE-ECC" | cut -d' ' -f1)"
before_foundation="$(sha256sum "${SANDBOX}/FOUNDATION_VERSION" | cut -d' ' -f1)"
init_out="$(cd "$SANDBOX" && bash scripts/init-project.sh --name 'Selftest Project' 2>&1)"
init_rc=$?
if [ "$init_rc" -ne 0 ]; then
  bad "init/first-run-succeeds" "exit $init_rc: $init_out"
else
  ok "init/first-run-succeeds" "exit 0"
fi

if grep -qE '^PROJECT_NAME=Selftest Project$' "${SANDBOX}/config/project.env" &&
   grep -qE '^PROJECT_SLUG=selftest-project$' "${SANDBOX}/config/project.env" &&
   grep -qE '^PROJECT_PHASE=discovery$' "${SANDBOX}/config/project.env"; then
  ok "init/sets-identity-and-phase" "name, slug and discovery phase written"
else
  bad "init/sets-identity-and-phase" "config/project.env was not updated as expected"
fi

if grep -qE '^ALLOW_APP_STACK=0$' "${SANDBOX}/config/project.env"; then
  ok "init/does-not-touch-stack-guard" "ALLOW_APP_STACK still 0"
else
  bad "init/does-not-touch-stack-guard" "init changed the application-stack guard"
fi

after_head="$(cd "$SANDBOX" && git rev-parse HEAD 2>/dev/null || echo none)"
if [ "$before_head" = "$after_head" ]; then
  ok "init/does-not-commit" "HEAD unchanged"
else
  bad "init/does-not-commit" "init created a commit"
fi

if [ "$before_version" = "$(sha256sum "${SANDBOX}/.ecc/VERSION" | cut -d' ' -f1)" ] &&
   [ "$before_licence" = "$(sha256sum "${SANDBOX}/.ecc/LICENSE-ECC" | cut -d' ' -f1)" ] &&
   [ "$before_foundation" = "$(sha256sum "${SANDBOX}/FOUNDATION_VERSION" | cut -d' ' -f1)" ]; then
  ok "init/never-rewrites-provenance" ".ecc/VERSION, LICENSE-ECC, FOUNDATION_VERSION untouched"
else
  bad "init/never-rewrites-provenance" "init modified a provenance or licence file"
fi

# The initialized repository must still pass the full gate.
expect_pass "init/gate-passes-after-init"

# Second run must be a safe no-op, not an overwrite.
second_out="$(cd "$SANDBOX" && bash scripts/init-project.sh --name 'Different Name' 2>&1)"
second_rc=$?
if [ "$second_rc" -eq 0 ] && grep -qE '^PROJECT_NAME=Selftest Project$' "${SANDBOX}/config/project.env"; then
  ok "init/idempotent-second-run" "exit 0, existing identity preserved"
else
  bad "init/idempotent-second-run" \
    "exit $second_rc; identity may have been overwritten: $(printf '%s' "$second_out" | head -n 1)"
fi

# A hostile name must be refused rather than written into a parsed config file.
reset_sandbox
set_config PROJECT_NAME ''
set_config PROJECT_PHASE discovery
if (cd "$SANDBOX" && bash scripts/init-project.sh --name 'evil$(touch /tmp/pwned)' >/dev/null 2>&1); then
  bad "init/rejects-unsafe-name" "a name with shell metacharacters was accepted"
else
  ok "init/rejects-unsafe-name" "refused"
fi

# --force must never leave the lifecycle in a state the gate rejects. Starting
# from a valid implementation-phase project, --force previously rewrote the
# phase back to discovery while leaving ALLOW_APP_STACK=1 in place, producing
# an invalid config: a "safe" script corrupting the repository it set up.
reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted marked
transition_to 0099-selftest-stack.md
set_config PROJECT_NAME 'Existing Project'
set_config PROJECT_SLUG existing-project
expect_pass "init/force-precondition-is-valid"

force_out="$(cd "$SANDBOX" && bash scripts/init-project.sh --force --name 'Renamed Project' 2>&1)"
force_rc=$?
if [ "$force_rc" -ne 0 ]; then
  bad "init/force-succeeds" "exit $force_rc: $(printf '%s' "$force_out" | head -n 1)"
else
  ok "init/force-succeeds" "exit 0"
fi

if grep -qE '^PROJECT_NAME=Renamed Project$' "${SANDBOX}/config/project.env"; then
  ok "init/force-updates-identity" "name rewritten"
else
  bad "init/force-updates-identity" "--force did not update the project name"
fi

if grep -qE '^PROJECT_PHASE=implementation$' "${SANDBOX}/config/project.env" &&
   grep -qE '^ALLOW_APP_STACK=1$' "${SANDBOX}/config/project.env"; then
  ok "init/force-preserves-lifecycle" "phase and stack state preserved"
else
  bad "init/force-preserves-lifecycle" "--force regressed the lifecycle state"
fi

# The decisive assertion: whatever --force did, the config must still be valid.
expect_pass "init/force-leaves-valid-lifecycle"

# --dry-run must write nothing.
reset_sandbox
set_config PROJECT_NAME ''
set_config PROJECT_PHASE discovery
dry_before="$(sha256sum "${SANDBOX}/config/project.env" | cut -d' ' -f1)"
(cd "$SANDBOX" && bash scripts/init-project.sh --name 'Dry Run' --dry-run >/dev/null 2>&1)
if [ "$dry_before" = "$(sha256sum "${SANDBOX}/config/project.env" | cut -d' ' -f1)" ]; then
  ok "init/dry-run-writes-nothing" "config/project.env unchanged"
else
  bad "init/dry-run-writes-nothing" "--dry-run modified the config"
fi

# No repository script may perform GitHub administration or remote execution.
reset_sandbox
# The pattern is assembled from fragments so this file does not match itself —
# the same technique check_secrets uses in verify.sh.
admin_pattern="gh ""api .*--method (POST|PUT|PATCH|DELETE)|gh ""repo edit"
admin_pattern="${admin_pattern}|git ""push|curl[^|]*\\| *(ba)?sh"
admin_hits="$(grep -nE "$admin_pattern" "${SANDBOX}"/scripts/*.sh || true)"
if [ -z "$admin_hits" ]; then
  ok "scripts/no-admin-or-remote-execution" "no push, admin API call, or curl-pipe-shell"
else
  bad "scripts/no-admin-or-remote-execution" "found: $(printf '%s' "$admin_hits" | head -n 1)"
fi

# --- Ditto migration regressions: retained through the foundation sync --------
# The environment must never authorize an otherwise unrecorded stack choice.
reset_sandbox
printf '{"name":"ditto-test-fixture"}\n' > "${SANDBOX}/package.json"
ALLOW_APP_STACK=1 expect_fail "no_app_stack/environment-override-full-gate"

# Filename separators must not confuse the redaction of grep output.
for filename_case in colon newline; do
  if [ "$filename_case" = colon ]; then unusual_name='has:colon.txt'; else unusual_name=$'has\nnewline.txt'; fi
  reset_sandbox
  printf '%s=%s\n' 'TOKEN' 'SyntheticFilenameCanary0123456789' > "${SANDBOX}/${unusual_name}"
  gate --only=secrets
  if [ "$GATE_RC" -ne 1 ] || printf '%s' "$GATE_OUT" | grep -qF 'SyntheticFilenameCanary'; then
    bad "secrets/unusual-filename-redaction-${filename_case}" "fault missed or matched material disclosed"
  else
    ok "secrets/unusual-filename-redaction-${filename_case}" "exit 1, value absent from combined output"
  fi
done

reset_sandbox
mkdir -p "${SANDBOX}/fixtures/nested/deep/path"
printf 'EMPTY=\n' > "${SANDBOX}/fixtures/nested/deep/path/.env.local"
expect_fail "env_files/no-depth-limit" --only=env_files

reset_sandbox
printf 'EMPTY=\n' > "${SANDBOX}/.envrc"
expect_fail "env_files/all-dotenv-prefixes" --only=env_files

reset_sandbox
printf 'EMPTY=\n' > "${SANDBOX}/.selftest-env-target"
ln -s .selftest-env-target "${SANDBOX}/.env.production"
expect_fail "env_files/symlink-prohibited" --only=env_files

reset_sandbox
sed -i 's|run: bash scripts/verify.sh$|run: echo "gate disabled" # bash scripts/verify.sh|' \
  "${SANDBOX}/.github/workflows/verify.yml"
expect_fail "ci_wiring/comment-is-not-invocation" --only=ci_wiring

# --- Complete standalone lifecycle validation -------------------------------
# Every required key matters, in both blocked and permitted states, even when
# no application artifact happens to exist yet.
for state in blocked permitted; do
  for lifecycle_key in PROJECT_NAME PROJECT_SLUG PROJECT_PHASE ALLOW_APP_STACK STACK_DECISION_ADR; do
    for fault in missing duplicate; do
      reset_sandbox
      if [ "$state" = permitted ]; then
        write_stack_adr 0099-selftest-stack.md accepted marked
        transition_to 0099-selftest-stack.md
      fi
      if [ "$fault" = missing ]; then
        sed -i "/^${lifecycle_key}=/d" "${SANDBOX}/config/project.env"
      else
        grep "^${lifecycle_key}=" "${SANDBOX}/config/project.env" > "${WORK_DIR}/duplicate-line"
        cat "${WORK_DIR}/duplicate-line" >> "${SANDBOX}/config/project.env"
      fi
      expect_fail "no_app_stack/${state}-${fault}-${lifecycle_key}" --only=no_app_stack
    done
  done
done

for invalid_phase in factory unknown; do
  reset_sandbox
  set_config PROJECT_PHASE "$invalid_phase"
  expect_fail "lifecycle/reject-${invalid_phase}-in-application-repo" --only=lifecycle
  expect_fail "no_app_stack/reject-${invalid_phase}-standalone" --only=no_app_stack
done

reset_sandbox
set_config ALLOW_APP_STACK yes
expect_fail "no_app_stack/invalid-flag-without-artifact" --only=no_app_stack

reset_sandbox
rm "${SANDBOX}/config/project.env"
expect_fail "no_app_stack/missing-config-without-artifact" --only=no_app_stack

reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted marked
transition_to 0099-selftest-stack.md
printf 'not an assignment\n' >> "${SANDBOX}/config/project.env"
expect_fail "no_app_stack/malformed-config-cannot-stand-down" --only=no_app_stack

reset_sandbox
mv "${SANDBOX}/config/project.env" "${SANDBOX}/.selftest-config"
ln -s ../.selftest-config "${SANDBOX}/config/project.env"
expect_fail "lifecycle/symlink-config-refused" --only=lifecycle
expect_fail "no_app_stack/symlink-config-refused" --only=no_app_stack

# Config text is never sourced, even when hostile.
reset_sandbox
# shellcheck disable=SC2016  # this must remain literal data, never execute.
printf 'PROJECT_NAME=$(touch .selftest-executed)\n' >> "${SANDBOX}/config/project.env"
expect_fail "lifecycle/command-substitution-is-data" --only=lifecycle
if [ -e "${SANDBOX}/.selftest-executed" ]; then
  bad "lifecycle/config-never-executed" "config executed shell syntax"
else
  ok "lifecycle/config-never-executed" "no side effect"
fi

# Known application artifacts cannot hide inside a new subdirectory.
reset_sandbox
mkdir -p "${SANDBOX}/packages/widget"
printf '{}\n' > "${SANDBOX}/packages/widget/package.json"
expect_fail "no_app_stack/nested-manifest" --only=no_app_stack

# --- Exact, unambiguous ADR metadata and confined paths ----------------------
for placement in mixed-fences shorter-fence fake-fence-close indented quoted multiline-comment status-in-fence duplicate-status duplicate-type traversal symlink; do
  reset_sandbox
  write_stack_adr 0099-selftest-stack.md accepted unmarked
  fixture="${SANDBOX}/docs/decisions/0099-selftest-stack.md"
  transition_to 0099-selftest-stack.md
  case "$placement" in
    mixed-fences)
      # shellcheck disable=SC2016
      printf '\n```text\n~~~\n**Decision Type:** application-stack\n~~~\n```\n' >> "$fixture"
      ;;
    shorter-fence)
      # shellcheck disable=SC2016
      printf '\n````text\n```\n**Decision Type:** application-stack\n```\n````\n' >> "$fixture"
      ;;
    fake-fence-close)
      # shellcheck disable=SC2016
      printf '\n```text\n```not-a-closer\n**Decision Type:** application-stack\n```\n' >> "$fixture"
      ;;
    indented) printf '\n    **Decision Type:** application-stack\n' >> "$fixture" ;;
    quoted) printf '\n> **Decision Type:** application-stack\n' >> "$fixture" ;;
    multiline-comment)
      printf '\n<!-- instructions\n**Decision Type:** application-stack\n-->\n' >> "$fixture"
      ;;
    status-in-fence)
      write_stack_adr 0099-selftest-stack.md proposed marked
      # shellcheck disable=SC2016
      printf '\n~~~text\n```\n**Status:** accepted\n```\n~~~\n' >> "$fixture"
      ;;
    duplicate-status)
      write_stack_adr 0099-selftest-stack.md accepted marked
      printf '**Status:** proposed\n' >> "$fixture"
      ;;
    duplicate-type)
      write_stack_adr 0099-selftest-stack.md accepted marked
      printf '**Decision Type:** application-stack\n' >> "$fixture"
      ;;
    traversal)
      write_stack_adr 0099-selftest-stack.md accepted marked
      mv "$fixture" "${SANDBOX}/.selftest-outside.md"
      set_config STACK_DECISION_ADR docs/decisions/../../.selftest-outside.md
      ;;
    symlink)
      write_stack_adr 0099-selftest-stack.md accepted marked
      mv "$fixture" "${SANDBOX}/.selftest-outside.md"
      ln -s ../../.selftest-outside.md "$fixture"
      ;;
  esac
  expect_fail "lifecycle/metadata-${placement}" --only=lifecycle
  expect_fail "no_app_stack/metadata-${placement}" --only=no_app_stack
done

# A valid decision still works with inert examples and ordinary whitespace.
reset_sandbox
write_stack_adr 0099-selftest-stack.md accepted marked
fixture="${SANDBOX}/docs/decisions/0099-selftest-stack.md"
printf '\n<!--\n**Status:** proposed\n-->\n~~~text\n<!--\n**Status:** proposed\n~~~\n' >> "$fixture"
sed -i 's/^\*\*Decision Type:\*\* application-stack$/  **Decision Type:** application-stack  /' "$fixture"
transition_to 0099-selftest-stack.md
expect_pass "lifecycle/active-metadata-with-inert-examples" --only=lifecycle
expect_pass "no_app_stack/active-metadata-with-inert-examples" --only=no_app_stack

# --- Portable policy: duplicate keys, exact contexts, no nested instance IDs --
for policy_fault in extra-context duplicate-context integration-id nested-id unknown-condition missing-exclude wrong-create-policy bool-review-count creation-removed stale-review-policy unattributed-policy; do
  reset_sandbox
  case "$policy_fault" in
    extra-context) ruleset_py 'next(r for r in doc["rules"] if r["type"] == "required_status_checks")["parameters"]["required_status_checks"].append({"context": "build"})' ;;
    duplicate-context) ruleset_py 'next(r for r in doc["rules"] if r["type"] == "required_status_checks")["parameters"]["required_status_checks"].append({"context": "Foundation gate"})' ;;
    integration-id) ruleset_py 'next(r for r in doc["rules"] if r["type"] == "required_status_checks")["parameters"]["required_status_checks"][0]["integration_id"] = 123' ;;
    nested-id) ruleset_py 'doc["rules"][0]["id"] = 123' ;;
    unknown-condition) ruleset_py 'doc["conditions"]["repository_id"] = 123' ;;
    missing-exclude) ruleset_py 'del doc["conditions"]["ref_name"]["exclude"]' ;;
    wrong-create-policy) ruleset_py 'next(r for r in doc["rules"] if r["type"] == "required_status_checks")["parameters"]["do_not_enforce_on_create"] = True' ;;
    bool-review-count) ruleset_py 'next(r for r in doc["rules"] if r["type"] == "pull_request")["parameters"]["required_approving_review_count"] = False' ;;
    creation-removed) ruleset_py 'doc["rules"] = [r for r in doc["rules"] if r["type"] != "creation"]' ;;
    stale-review-policy) ruleset_py 'next(r for r in doc["rules"] if r["type"] == "pull_request")["parameters"]["dismiss_stale_reviews_on_push"] = False' ;;
    unattributed-policy) ruleset_py 'next(r for r in doc["rules"] if r["type"] == "pull_request")["parameters"]["require_extra_approval_for_unattributed_changes"] = False' ;;
  esac
  expect_fail "ruleset/${policy_fault}" --only=ruleset
done

reset_sandbox
sed -i 's/"enforcement": "active"/"enforcement": "evaluate", "enforcement": "active"/' "${SANDBOX}/config/main-ruleset.json"
expect_fail "ruleset/duplicate-json-key" --only=ruleset

# --- Actual CI structure, not merely strings that look reassuring ------------
workflow_mutation() {
  WORKFLOW="${SANDBOX}/.github/workflows/verify.yml" python3 - "$1" <<'PYEOF'
import os, sys
from pathlib import Path
p = Path(os.environ['WORKFLOW'])
s = p.read_text()
fault = sys.argv[1]
if fault == 'job-skipped':
    s = s.replace('  gate:\n', '  gate:\n    if: false\n', 1)
elif fault == 'selftest-env-override':
    s = s.replace('        run: bash scripts/selftest.sh\n', '        env:\n          BASH_ENV: .selftest-shell\n        run: bash scripts/selftest.sh\n', 1)
elif fault == 'independent-env-override':
    s = s.replace('        run: bash scripts/verify.sh --only=foundation_version', '        env:\n          BASH_ENV: .selftest-shell\n        run: bash scripts/verify.sh --only=foundation_version', 1)
elif fault == 'checkout-ref-override':
    s = s.replace('          persist-credentials: false', '          persist-credentials: false\n          ref: main', 1)
elif fault == 'job-continue-on-error':
    s = s.replace('  gate:\n', '  gate:\n    continue-on-error: true\n', 1)
elif fault == 'step-skipped':
    s = s.replace('        run: bash scripts/verify.sh\n', '        if: false\n        run: bash scripts/verify.sh\n', 1)
elif fault == 'step-continue-on-error':
    s = s.replace('        run: bash scripts/verify.sh\n', '        continue-on-error: true\n        run: bash scripts/verify.sh\n', 1)
elif fault == 'job-name-only-in-step':
    s = s.replace('    name: Foundation gate\n', '    name: Build\n', 1)
    s = s.replace('      - name: Checkout\n', '      - name: Foundation gate\n', 1)
elif fault in ('write-all', 'inline-write-permission'):
    replacement = 'permissions: write-all' if fault == 'write-all' else 'permissions: {contents: write}'
    s = s.replace('permissions:\n  contents: read', replacement, 1)
    s = s.replace('  independent-checks:\n', '  independent-checks:\n    permissions:\n      contents: read\n', 1)
elif fault == 'pr-filtered':
    s = s.replace('  pull_request:\n', '  pull_request:\n    branches: [never-main]\n', 1)
elif fault == 'push-not-main':
    s = s.replace('branches: [main]', 'branches: [never-main]', 1)
elif fault == 'partial-gate':
    s = s.replace('run: bash scripts/verify.sh\n', 'run: bash scripts/verify.sh --only=foundation\n', 1)
elif fault == 'selftest-only-echoed':
    s = s.replace('run: bash scripts/selftest.sh\n', 'run: echo bash scripts/selftest.sh\n', 1)
elif fault == 'quoted-unpinned-action':
    s = s.replace('uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683', 'uses: "actions/checkout@v4"')
elif fault == 'duplicate-job-key':
    s += '\n  gate:\n    name: Replaced\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n'
p.write_text(s)
PYEOF
}
for workflow_fault in selftest-env-override independent-env-override checkout-ref-override job-skipped job-continue-on-error step-skipped step-continue-on-error job-name-only-in-step write-all inline-write-permission pr-filtered push-not-main partial-gate selftest-only-echoed quoted-unpinned-action duplicate-job-key; do
  reset_sandbox
  workflow_mutation "$workflow_fault"
  expect_fail "ci_wiring/${workflow_fault}" --only=ci_wiring
done

# --- Foundation and ECC records must be real, complete, unambiguous pins ------
for record_key in UPSTREAM_LICENSE_SHA256 UPSTREAM_COPYRIGHT UPSTREAM_LICENSE_FILE ADAPTER_KIND FOUNDATION_SYNCED_AT; do
  reset_sandbox
  sed -i "/^${record_key}=/d" "${SANDBOX}/.ecc/VERSION"
  expect_fail "provenance/missing-${record_key}" --only=provenance
done
reset_sandbox
printf 'UPSTREAM_VERSION=9.9.9\n' >> "${SANDBOX}/.ecc/VERSION"
expect_fail "provenance/duplicate-version-key" --only=provenance
reset_sandbox
sed -i 's/^UPSTREAM_COMMIT=.*/UPSTREAM_COMMIT=0000000000000000000000000000000000000000/' "${SANDBOX}/.ecc/VERSION"
expect_fail "provenance/wrong-but-well-formed-ecc-pin" --only=provenance
reset_sandbox
sed -i 's/^ADAPTER_NAME=.*/ADAPTER_NAME=generic-template-adapter/' "${SANDBOX}/.ecc/VERSION"
expect_fail "provenance/ditto-adapter-identity" --only=provenance
reset_sandbox
printf 'tampered\n' >> "${SANDBOX}/.ecc/LICENSE-ECC"
tampered_hash="$(sha256sum "${SANDBOX}/.ecc/LICENSE-ECC" | cut -d' ' -f1)"
sed -i "s/^UPSTREAM_LICENSE_SHA256=.*/UPSTREAM_LICENSE_SHA256=${tampered_hash}/" "${SANDBOX}/.ecc/VERSION"
expect_fail "provenance/licence-and-record-tampered-together" --only=provenance

for version_case in whitespace second-unterminated-line leading-zero-prerelease empty-prerelease-component; do
  case "$version_case" in
    whitespace) version_fault='0.1 .0' ;;
    second-unterminated-line) version_fault=$'0.1.0\n2.0.0' ;;
    leading-zero-prerelease) version_fault='0.1.0-01' ;;
    empty-prerelease-component) version_fault='0.1.0-alpha..one' ;;
  esac
  reset_sandbox
  printf '%s' "$version_fault" > "${SANDBOX}/FOUNDATION_VERSION"
  expect_fail "foundation_version/${version_case}" --only=foundation_version
done

# --- Init must reject bad input without writing any part of it ----------------
expect_init_refusal() {
  local label="$1"; shift
  local before after rc
  before="$(sha256sum "${SANDBOX}/config/project.env" | cut -d' ' -f1)"
  (cd "$SANDBOX" && bash scripts/init-project.sh "$@" >/dev/null 2>&1)
  rc=$?
  after="$(sha256sum "${SANDBOX}/config/project.env" | cut -d' ' -f1)"
  if [ "$rc" -ne 0 ] && [ "$before" = "$after" ]; then
    ok "$label" "refused without changing config"
  else
    bad "$label" "unsafe input accepted or config modified"
  fi
}
reset_sandbox
expect_init_refusal "init/newline-name" --force --name $'Valid Name\nPROJECT_PHASE=implementation'
reset_sandbox
expect_init_refusal "init/newline-slug" --force --name 'Valid Name' --slug $'valid\nALLOW_APP_STACK=1'
reset_sandbox
expect_init_refusal "init/name-argument-missing" --force --name
reset_sandbox
printf 'PROJECT_PHASE=implementation\n' >> "${SANDBOX}/config/project.env"
expect_init_refusal "init/duplicate-config-refused" --force --name 'Valid Name'
reset_sandbox
sed -i '/^STACK_DECISION_ADR=/d' "${SANDBOX}/config/project.env"
expect_init_refusal "init/missing-config-key-refused" --force --name 'Valid Name'
reset_sandbox
set_config PROJECT_PHASE unknown
expect_init_refusal "init/invalid-phase-refused" --force --name 'Valid Name'
reset_sandbox
mv "${SANDBOX}/config/project.env" "${SANDBOX}/.selftest-config"
ln -s ../.selftest-config "${SANDBOX}/config/project.env"
expect_init_refusal "init/symlink-config-refused" --force --name 'Valid Name'

# In discovery and architecture too, forcing identity changes must retain the
# exact lifecycle key lines, ADR pointer and all project/history documents.
for safe_phase in discovery architecture; do
  reset_sandbox
  set_config PROJECT_PHASE "$safe_phase"
  write_stack_adr 0099-selftest-stack.md proposed marked
  set_config STACK_DECISION_ADR docs/decisions/0099-selftest-stack.md
  before_state="$(grep -E '^(PROJECT_PHASE|ALLOW_APP_STACK|STACK_DECISION_ADR)=' "${SANDBOX}/config/project.env")"
  before_docs="$(find "${SANDBOX}/docs" "${SANDBOX}/.ecc" -type f -exec sha256sum {} + | LC_ALL=C sort)"
  (cd "$SANDBOX" && bash scripts/init-project.sh --force --name 'Renamed Project' >/dev/null 2>&1)
  force_rc=$?
  after_state="$(grep -E '^(PROJECT_PHASE|ALLOW_APP_STACK|STACK_DECISION_ADR)=' "${SANDBOX}/config/project.env")"
  after_docs="$(find "${SANDBOX}/docs" "${SANDBOX}/.ecc" -type f -exec sha256sum {} + | LC_ALL=C sort)"
  if [ "$force_rc" -eq 0 ] && [ "$before_state" = "$after_state" ] && [ "$before_docs" = "$after_docs" ]; then
    ok "init/force-preserves-${safe_phase}-state-and-history" "only config identity changed"
  else
    bad "init/force-preserves-${safe_phase}-state-and-history" "state/history changed or init failed"
  fi
done

reset_sandbox
printf 'EMPTY=\n' > "${SANDBOX}/.selftest-env-target"
ln -s .selftest-env-target "${SANDBOX}/.env.example"
expect_fail "env_files/example-must-be-regular-file" --only=env_files
reset_sandbox
printf '%s=%s\n' 'TOKEN' 'SyntheticExampleCanary0123456789' > "${SANDBOX}/.env.example"
expect_fail "secrets/example-file-is-not-exempt" --only=secrets

# --- AgentShield outcomes are deterministic and honestly classified ----------
# Stub only the external scanner, never the committed gate. No network needed.
mkdir -p "${WORK_DIR}/scanner-bin"
cat > "${WORK_DIR}/scanner-bin/npx" <<'SHEOF'
#!/usr/bin/env bash
printf '%s\n' "$SELFTEST_SCANNER_REPORT"
SHEOF
chmod +x "${WORK_DIR}/scanner-bin/npx"
scanner_gate() {
  PATH="${WORK_DIR}/scanner-bin:$PATH" SELFTEST_SCANNER_REPORT="$1" \
    gate --only=agentshield --require-agentshield
}
reset_sandbox
scanner_gate '{"summary":{"critical":0,"high":0,"filesScanned":0}}'
if [ "$GATE_RC" -eq 0 ] && [[ "$GATE_OUT" == *'[SKIP] agentshield'* ]] && [[ "$GATE_OUT" != *'[PASS] agentshield'* ]]; then
  ok "agentshield/zero-files-is-skip" "never counted as PASS"
else
  bad "agentshield/zero-files-is-skip" "incorrect zero-file outcome"
fi
reset_sandbox
scanner_gate '{"summary":{"critical":0,"high":0,"filesScanned":2}}'
if [ "$GATE_RC" -eq 0 ] && [[ "$GATE_OUT" == *'[PASS] agentshield'* ]]; then
  ok "agentshield/nonempty-clean-scan" "positive coverage reported"
else
  bad "agentshield/nonempty-clean-scan" "valid report rejected"
fi
for report_case in critical high malformed missing-counter negative-counter string-counter boolean-counter; do
  case "$report_case" in
    critical) report='{"summary":{"critical":1,"high":0,"filesScanned":0}}' ;;
    high) report='{"summary":{"critical":0,"high":1,"filesScanned":2}}' ;;
    malformed) report='{broken' ;;
    missing-counter) report='{"summary":{"critical":0,"high":0}}' ;;
    negative-counter) report='{"summary":{"critical":0,"high":0,"filesScanned":-1}}' ;;
    string-counter) report='{"summary":{"critical":0,"high":0,"filesScanned":"2"}}' ;;
    boolean-counter) report='{"summary":{"critical":0,"high":0,"filesScanned":true}}' ;;
  esac
  reset_sandbox
  scanner_gate "$report"
  if [ "$GATE_RC" -eq 1 ] && [[ "$GATE_OUT" == *'[FAIL] agentshield'* ]]; then
    ok "agentshield/reject-${report_case}" "named failure, exit 1"
  else
    bad "agentshield/reject-${report_case}" "unsafe or invalid report not rejected"
  fi
done
reset_sandbox
sed -i 's/^AGENTSHIELD_NPM_PACKAGE=.*/AGENTSHIELD_NPM_PACKAGE=unreviewed-package/' "${SANDBOX}/.ecc/VERSION"
scanner_gate '{"summary":{"critical":0,"high":0,"filesScanned":2}}'
if [ "$GATE_RC" -eq 1 ] && [[ "$GATE_OUT" == *'[FAIL] agentshield'* ]]; then
  ok "agentshield/standalone-rejects-unreviewed-package" "scanner pin checked before execution"
else
  bad "agentshield/standalone-rejects-unreviewed-package" "unreviewed scanner was allowed"
fi

# Metadata and even pathnames can contain a credential. Neither the gate
# banner nor a location diagnostic may echo it during a secrets-only run.
for leak_surface in foundation-metadata filename; do
  reset_sandbox
  if [ "$leak_surface" = foundation-metadata ]; then
    printf '%s\n' "$CANARY_TOKEN" > "${SANDBOX}/FOUNDATION_VERSION"
  else
    printf '%s\n' "$CANARY_TOKEN" > "${SANDBOX}/${CANARY_TOKEN}.txt"
  fi
  gate --only=secrets
  if [ "$GATE_RC" -eq 1 ] && [[ "$GATE_OUT" != *"$CANARY_TOKEN"* ]]; then
    ok "secrets/redaction-${leak_surface}" "named scan failure without matched value"
  else
    bad "secrets/redaction-${leak_surface}" "credential missed or echoed into output"
  fi
done

reset_sandbox
mv "${SANDBOX}/FOUNDATION_VERSION" "${SANDBOX}/.selftest-version"
ln -s .selftest-version "${SANDBOX}/FOUNDATION_VERSION"
expect_fail "foundation_version/symlink-refused" --only=foundation_version

reset_sandbox
scanner_gate "{\"summary\":{\"critical\":1,\"high\":0,\"filesScanned\":1},\"finding\":\"${CANARY_TOKEN}\"}"
if [ "$GATE_RC" -eq 1 ] && [[ "$GATE_OUT" != *"$CANARY_TOKEN"* ]]; then
  ok "agentshield/report-values-not-logged" "only normalized counters reported"
else
  bad "agentshield/report-values-not-logged" "finding missed or report content echoed"
fi

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
