#!/usr/bin/env bash
# Ditto foundation verification gate.
#
# The authoritative quality gate for this repository. Deterministic, committed,
# and re-run independently by .github/workflows/verify.yml. Exits non-zero when
# any required check fails.
#
# Usage:
#   scripts/verify.sh                     run every check
#   scripts/verify.sh --list              list check names and exit
#   scripts/verify.sh --only=NAME         run one check (repeatable)
#   scripts/verify.sh --skip-agentshield  skip the scanner (offline)
#   scripts/verify.sh --require-agentshield  fail if the scanner cannot run
#   scripts/verify.sh --quiet             only failures and the summary
#
# Environment:
#   VERIFY_AGENTSHIELD=auto|off|require   default: auto
#
# Lifecycle note: whether application-stack artifacts are allowed is NOT a
# constant in this script. It is committed repository state in
# config/project.env, validated by check_lifecycle and consumed by
# check_no_app_stack, so a project can graduate to an application stack through
# a reviewed config diff instead of an edit to the gate.
#
# Design note: .git/hooks/ is deliberately NOT used for enforcement — hooks are
# not committed, so a fresh clone (every new Arena session) has none.
# See docs/decisions/0002-verification-gate.md.

# Lint note: SC2329 ("function never invoked") and SC2317 ("command appears to
# be unreachable") are suppressed file-wide because the check_* functions are
# dispatched by constructed name ("check_${check}") in the run loop at the
# bottom, so the linter cannot see their call sites. Which of the two codes is
# reported depends on the shellcheck version (0.11 reports SC2329 at the
# definition; 0.9 reports SC2317 on every line inside), so both are listed to
# keep the gate stable across local and CI toolchains.
# Every other finding, down to style severity, must still be clean.
# shellcheck disable=SC2317,SC2329

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT" || exit 2

PROJECT_CONFIG="config/project.env"

# --- State -------------------------------------------------------------------
declare -a CHECK_ORDER=()
declare -a SELECTED=()
declare -a FAILURE_MESSAGES=()
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
QUIET=0
AGENTSHIELD_MODE="${VERIFY_AGENTSHIELD:-auto}"
LIST_ONLY=0

# --- Output helpers ----------------------------------------------------------
c_reset='' c_pass='' c_fail='' c_skip='' c_dim=''
if [ -t 1 ]; then
  c_reset=$'\033[0m'; c_pass=$'\033[32m'; c_fail=$'\033[31m'
  c_skip=$'\033[33m'; c_dim=$'\033[2m'
fi

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

report_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '  %s[PASS]%s %-18s %s\n' "$c_pass" "$c_reset" "$1" "$2"
}

report_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILURE_MESSAGES+=("$1: $2")
  printf '  %s[FAIL]%s %-18s %s\n' "$c_fail" "$c_reset" "$1" "$2"
}

report_skip() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf '  %s[SKIP]%s %-18s %s\n' "$c_skip" "$c_reset" "$1" "$2"
}

fail_lines() {
  local name="$1"; shift
  local detail="$1"; shift
  local line
  report_fail "$name" "$detail"
  for line in "$@"; do
    printf '         %s%s%s\n' "$c_dim" "$line" "$c_reset"
  done
}

# --- Utilities ---------------------------------------------------------------
# File discovery walks the WORKING TREE, not the git index, so the gate also
# covers a fresh session's uncommitted work. Only the executable-bit check
# consults the index, and only for files that are already tracked.
md_files() {
  find . -type f \( -name '*.md' -o -name '*.MD' \) -not -path './.git/*' |
    sed 's|^\./||' | LC_ALL=C sort
}

shell_files() {
  find . -type f -name '*.sh' -not -path './.git/*' |
    sed 's|^\./||' | LC_ALL=C sort
}

ecc_files() {
  find "$@" -maxdepth 1 -type f -name '*.md' 2>/dev/null |
    sed 's|^\./||' | LC_ALL=C sort
}

workflow_files() {
  find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null |
    sed 's|^\./||' | LC_ALL=C sort
}

version_value() {
  local key="$1"
  sed -n "s/^${key}=//p" .ecc/VERSION 2>/dev/null | head -n 1
}

version_key_count() {
  awk -F= -v key="$1" '$1 == key { n++ } END { print n + 0 }' .ecc/VERSION 2>/dev/null
}

# config_value reads one key from config/project.env. The file is parsed
# line-by-line and never sourced, so a malformed or hostile value cannot be
# executed by the gate that is supposed to be inspecting it.
config_value() {
  local key="$1"
  [ -f "$PROJECT_CONFIG" ] || return 0
  sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$PROJECT_CONFIG" |
    head -n 1 | sed 's/[[:space:]]*$//'
}

# config_key_count counts how many times a key is assigned. Duplicate
# assignments make committed lifecycle state ambiguous: config_value silently
# takes the first, a human reading the file usually takes the last.
#
# Implementation note: `grep -c` PRINTS 0 and EXITS 1 when nothing matches, so
# `grep -c ... || printf '0'` emits "0\n0" and every later numeric test on the
# result is a syntax error that silently evaluates false. That bug let a
# missing required key pass the cardinality check entirely. Counting lines here
# instead keeps the output a single integer on every path.
config_key_count() {
  local key="$1"
  if [ ! -f "$PROJECT_CONFIG" ]; then
    printf '0'
    return 0
  fi
  # shellcheck disable=SC2126  # `grep -c` is exactly the bug described above:
  # it exits 1 on no match, which corrupted the count. Keep grep | wc -l.
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "$PROJECT_CONFIG" 2>/dev/null |
    wc -l | tr -d '[:space:]'
}

# The marker that makes an ADR machine-identifiable as the record of an
# application-stack decision. A stack ADR must carry BOTH this line and an
# accepted status; existing on disk is not enough.
STACK_ADR_MARKER='**Decision Type:** application-stack'
STACK_ADR_STATUS='**Status:** accepted'

# ADR metadata is deliberately a small, explicit format, not substring search.
# Ignore HTML comments, matching fenced blocks (delimiter AND length), indented
# code and quoted/prose examples. Exactly one active field must match; an
# accepted status plus a second proposed status is ambiguous, not approval.
adr_has_metadata_line() {
  local file="$1" wanted="$2"
  [ -f "$file" ] || return 1
  awk -v want="$wanted" '
    BEGIN {
      found = 0; fields = 0; in_comment = 0; fence_char = ""; fence_len = 0
      label = substr(want, 1, index(want, ":**") + 2)
    }
    {
      line = $0
      probe = line
      sub(/^[[:space:]]+/, "", probe)
      if (fence_len > 0) {
        # Only the same delimiter, at least as long, with no info string closes.
        run = 0
        while (substr(probe, run + 1, 1) == fence_char) { run++ }
        rest = substr(probe, run + 1)
        if (run >= fence_len && rest ~ /^[[:space:]]*$/) { fence_len = 0 }
        next
      }

      # Strip comment spans from left to right, including multiple per line.
      visible = ""
      while (length(line) > 0) {
        if (in_comment) {
          idx = index(line, "-->")
          if (!idx) { line = ""; break }
          line = substr(line, idx + 3); in_comment = 0
        } else {
          idx = index(line, "<!--")
          if (!idx) { visible = visible line; line = ""; break }
          visible = visible substr(line, 1, idx - 1)
          line = substr(line, idx + 4); in_comment = 1
        }
      }
      line = visible
      # Four spaces or a tab introduce code, not metadata.
      if (line ~ /^(    |\t)/) { next }
      probe = line
      sub(/^[[:space:]]+/, "", probe)
      char = substr(probe, 1, 1)
      if (char == "`" || char == "~") {
        run = 0
        while (substr(probe, run + 1, 1) == char) { run++ }
        if (run >= 3) { fence_char = char; fence_len = run; next }
      }
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (index(line, label) == 1) { fields++ }
      if (line == want) { found++ }
    }
    END { exit(found == 1 && fields == 1 ? 0 : 1) }
  ' "$file"
}

# Canonical, regular ADR files only. A lexical prefix alone would permit ../
# traversal and symlinks to unrelated or out-of-repository content.
valid_adr_path() {
  local adr="$1"
  [[ "$adr" =~ ^docs/decisions/[0-9]{4}-[a-z0-9][a-z0-9-]*\.md$ ]] &&
    [ "$adr" != docs/decisions/0000-template.md ] &&
    [ ! -L docs ] && [ ! -L docs/decisions ] && [ ! -L "$adr" ] &&
    [ -f "$adr" ] && [ -r "$adr" ]
}

# Shared authority for the application-stack transition. No caller may trust a
# previous check to have run: --only=no_app_stack must make the same decision.
validate_stack_transition() {
  local -n _transition_problems="$1"
  local phase allow adr key
  phase="$(config_value PROJECT_PHASE)"
  allow="$(config_value ALLOW_APP_STACK)"
  adr="$(config_value STACK_DECISION_ADR)"
  [ "$allow" = 1 ] || return 1
  for key in PROJECT_PHASE ALLOW_APP_STACK STACK_DECISION_ADR; do
    if [ "$(config_key_count "$key")" -ne 1 ]; then
      _transition_problems+=("${key} must be assigned exactly once to authorize a stack transition")
    fi
  done
  if [ "$phase" != implementation ]; then
    _transition_problems+=("ALLOW_APP_STACK=1 requires PROJECT_PHASE=implementation")
  fi
  if ! valid_adr_path "$adr"; then
    _transition_problems+=("STACK_DECISION_ADR must name a regular, existing docs/decisions/NNNN-title.md decision, not the template, traversal or a symlink")
    return 1
  fi
  if ! adr_has_metadata_line "$adr" "$STACK_ADR_MARKER"; then
    _transition_problems+=("stack ADR needs exactly one active standalone ${STACK_ADR_MARKER} line")
  fi
  if ! adr_has_metadata_line "$adr" "$STACK_ADR_STATUS"; then
    _transition_problems+=("stack ADR needs exactly one active standalone ${STACK_ADR_STATUS} line")
  fi
  [ "${#_transition_problems[@]}" -eq 0 ]
}

# Validate ALL committed lifecycle state, even when the guard remains up. This
# helper is called independently by lifecycle and no_app_stack; init invokes
# the actual lifecycle gate before making any identity-only edit.
validate_project_config() {
  local -n _config_problems="$1"
  if [ ! -f "$PROJECT_CONFIG" ] || [ ! -r "$PROJECT_CONFIG" ] ||
     [ -L "$PROJECT_CONFIG" ] || [ -L config ]; then
    _config_problems+=("$PROJECT_CONFIG must be a readable regular file, not a symlink")
    return 1
  fi
  local line lineno=0 key count
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    case "$line" in ''|'#'*) continue ;; esac
    if [[ ! "$line" =~ ^(PROJECT_NAME|PROJECT_SLUG|PROJECT_PHASE|ALLOW_APP_STACK|STACK_DECISION_ADR)= ]]; then
      _config_problems+=("$PROJECT_CONFIG:$lineno must assign a documented lifecycle key in KEY=VALUE form")
    fi
  done < "$PROJECT_CONFIG"
  for key in PROJECT_NAME PROJECT_SLUG PROJECT_PHASE ALLOW_APP_STACK STACK_DECISION_ADR; do
    count="$(config_key_count "$key")"
    [ "$count" -eq 1 ] ||
      _config_problems+=("$PROJECT_CONFIG must assign ${key} exactly once (found ${count})")
  done
  local phase allow adr slug project_name
  phase="$(config_value PROJECT_PHASE)"
  allow="$(config_value ALLOW_APP_STACK)"
  adr="$(config_value STACK_DECISION_ADR)"
  slug="$(config_value PROJECT_SLUG)"
  project_name="$(config_value PROJECT_NAME)"
  case "$phase" in
    discovery|architecture|implementation) : ;;
    *) _config_problems+=("PROJECT_PHASE must be discovery|architecture|implementation (Ditto is not the master template)") ;;
  esac
  case "$allow" in
    0|1) : ;;
    *) _config_problems+=("ALLOW_APP_STACK must be 0 or 1") ;;
  esac
  if [ -n "$project_name" ] && [[ ! "$project_name" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]{0,63}$ ]]; then
    _config_problems+=("PROJECT_NAME must be a plain single-line name of at most 64 characters")
  fi
  if [ -n "$slug" ] && [[ ! "$slug" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]]; then
    _config_problems+=("PROJECT_SLUG must be lowercase kebab-case of at most 64 characters")
  fi
  if [ "$allow" = 1 ]; then
    validate_stack_transition "$1" || :
  elif [ -n "$adr" ] && ! valid_adr_path "$adr"; then
    _config_problems+=("STACK_DECISION_ADR must be empty or name a regular, existing decision under docs/decisions/")
  fi
  [ "${#_config_problems[@]}" -eq 0 ]
}

selected() {
  local name="$1"
  [ "${#SELECTED[@]}" -eq 0 ] && return 0
  local want
  for want in "${SELECTED[@]}"; do
    [ "$want" = "$name" ] && return 0
  done
  return 1
}

# Registers a check in run order.
register() { CHECK_ORDER+=("$1"); }

# --- Required foundation files ----------------------------------------------
REQUIRED_FILES=(
  AGENTS.md
  README.md
  FOUNDATION_VERSION
  .ecc/BOOTSTRAP.md
  .ecc/VERSION
  .ecc/UPSTREAM.md
  .ecc/LICENSE-ECC
  .ecc/rules/engineering.md
  .ecc/rules/security.md
  .ecc/rules/testing.md
  .ecc/rules/git.md
  .ecc/skills/INDEX.md
  .ecc/skills/planning.md
  .ecc/skills/research.md
  .ecc/skills/tdd.md
  .ecc/skills/debugging.md
  .ecc/skills/code-review.md
  .ecc/skills/spec-review.md
  .ecc/skills/security-review.md
  .ecc/skills/verification.md
  .ecc/skills/project-memory.md
  .ecc/skills/decisions.md
  .ecc/roles/architect.md
  .ecc/roles/security-reviewer.md
  .ecc/roles/spec-reviewer.md
  config/project.env
  config/main-ruleset.json
  docs/PRODUCT.md
  docs/ARCHITECTURE.md
  ARENA_CAPABILITIES.md
  docs/DOMAIN.md
  docs/ROADMAP.md
  docs/SECURITY.md
  docs/MEMORY.md
  docs/FOUNDATION.md
  docs/decisions/README.md
  docs/decisions/0000-template.md
  docs/decisions/0001-ecc-on-arena-adapter.md
  docs/decisions/0002-verification-gate.md
  docs/decisions/0003-flat-skill-files.md
  docs/decisions/0004-foundation-lifecycle-sync.md
  docs/codemaps/README.md
  scripts/bootstrap.sh
  scripts/init-project.sh
  scripts/verify.sh
  scripts/sync-ecc.sh
  scripts/selftest.sh
  .github/workflows/verify.yml
  .github/PULL_REQUEST_TEMPLATE.md
)

REQUIRED_EXECUTABLES=(
  scripts/bootstrap.sh
  scripts/init-project.sh
  scripts/verify.sh
  scripts/sync-ecc.sh
  scripts/selftest.sh
)

# The CI job names the branch ruleset requires as status contexts. Renaming a
# job without updating config/main-ruleset.json would silently unprotect the
# default branch, so the two are cross-checked here.
REQUIRED_CI_CONTEXTS=(
  'Foundation gate'
  'Independent checks'
)

# --- 1. foundation -----------------------------------------------------------
check_foundation() {
  local name="foundation"
  selected "$name" || return 0
  local missing=() f
  for f in "${REQUIRED_FILES[@]}"; do
    [ -f "$f" ] || missing+=("$f")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    fail_lines "$name" "${#missing[@]} required file(s) missing" "${missing[@]}"
    return 1
  fi
  report_pass "$name" "${#REQUIRED_FILES[@]} required files present"
}

# --- 2. foundation version ---------------------------------------------------
# FOUNDATION_VERSION identifies the App-Factory release a repository was built
# from. It is deliberately separate from the ECC upstream version and from the
# AgentShield version; conflating them would make provenance unreadable.
check_foundation_version() {
  local name="foundation_version"
  selected "$name" || return 0
  local file="FOUNDATION_VERSION"
  if [ ! -f "$file" ] || [ -L "$file" ]; then
    fail_lines "$name" "$file must be a regular version file, not a symlink"
    return 1
  fi
  local lines value
  lines="$(wc -l < "$file" | tr -d '[:space:]')"
  value="$(cat "$file")"
  local problems=()
  if [ "$lines" -gt 1 ]; then
    problems+=("$file must contain a single version line")
  fi
  # Match the entire value, not one line of it; do not delete whitespace to
  # make malformed text look valid. SemVer pre-release numbers have no leading
  # zeroes, and neither pre-release nor build identifiers can be empty.
  local number='(0|[1-9][0-9]*)'
  local pre='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
  local build='[0-9A-Za-z-]+'
  local semver="${number}\.${number}\.${number}(-${pre}(\.${pre})*)?(\+${build}(\.${build})*)?"
  if [[ ! "$value" =~ ^${semver}$ ]]; then
    problems+=("$file must contain exactly one semantic version, without whitespace or provenance fields")
  fi
  local ecc_version
  ecc_version="$(version_value UPSTREAM_VERSION)"
  # Conceptual separation is proved by the two values living in distinct
  # files/fields with distinct meanings, NOT by requiring them to differ
  # numerically. They may legitimately coincide one day; an inequality rule
  # would then force an artificial version bump for no engineering reason.
  # What must hold is that both are present and independently declared.
  if [ -z "$ecc_version" ]; then
    problems+=("UPSTREAM_VERSION is absent from .ecc/VERSION; the ECC version must be declared separately")
  fi
  if grep -qE '^[[:space:]]*(UPSTREAM|AGENTSHIELD)' FOUNDATION_VERSION 2>/dev/null; then
    problems+=("$file must contain only the foundation version, not ECC or scanner provenance")
  fi
  if [ "${#problems[@]}" -gt 0 ]; then
    fail_lines "$name" "${#problems[@]} problem(s) with $file" "${problems[@]}"
    return 1
  fi
  report_pass "$name" "App-Factory foundation v${value} (ECC upstream v${ecc_version:-unknown})"
}

# --- 3. links ----------------------------------------------------------------
# Every relative Markdown link in a tracked .md file must resolve on disk.
extract_md_links() {
  awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    !fence { print }
  ' "$1" |
    grep -oE '\]\([^)[:space:]]+\)' |
    sed -E 's/^\]\(//; s/\)$//'
}

check_links() {
  local name="links"
  selected "$name" || return 0
  local file dir link target broken=() checked=0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    dir="$(dirname -- "$file")"
    while IFS= read -r link; do
      [ -n "$link" ] || continue
      case "$link" in
        http://*|https://*|mailto:*|'#'*|'<'*) continue ;;
      esac
      target="${link%%#*}"
      [ -n "$target" ] || continue
      checked=$((checked + 1))
      if [ ! -e "$dir/$target" ]; then
        broken+=("$file -> $link")
      fi
    done < <(extract_md_links "$file")
  done < <(md_files)
  if [ "${#broken[@]}" -gt 0 ]; then
    fail_lines "$name" "${#broken[@]} unresolved link(s)" "${broken[@]}"
    return 1
  fi
  report_pass "$name" "$checked relative link(s) resolve"
}

# --- 4. shell syntax ---------------------------------------------------------
check_shell_syntax() {
  local name="shell_syntax"
  selected "$name" || return 0
  local file bad=() count=0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    count=$((count + 1))
    if ! bash -n "$file" 2>/dev/null; then
      bad+=("$file")
    fi
  done < <(shell_files)
  if [ "$count" -eq 0 ]; then
    fail_lines "$name" "no shell scripts tracked"
    return 1
  fi
  if [ "${#bad[@]}" -gt 0 ]; then
    fail_lines "$name" "${#bad[@]} script(s) failed bash -n" "${bad[@]}"
    return 1
  fi
  report_pass "$name" "$count script(s) parse cleanly"
}

# --- 5. shell lint -----------------------------------------------------------
check_shell_lint() {
  local name="shell_lint"
  selected "$name" || return 0
  if ! command -v shellcheck >/dev/null 2>&1; then
    report_skip "$name" "shellcheck not installed (CI runs it)"
    return 0
  fi
  local file bad=() count=0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    count=$((count + 1))
    if ! shellcheck --severity=style "$file" >/dev/null 2>&1; then
      bad+=("$file")
    fi
  done < <(shell_files)
  if [ "${#bad[@]}" -gt 0 ]; then
    fail_lines "$name" "shellcheck findings in ${#bad[@]} script(s)" "${bad[@]}"
    return 1
  fi
  report_pass "$name" "$count script(s) clean under shellcheck"
}

# --- 6. executable bits ------------------------------------------------------
check_executable() {
  local name="executable"
  selected "$name" || return 0
  local file bad=() mode
  for file in "${REQUIRED_EXECUTABLES[@]}"; do
    if [ ! -f "$file" ]; then
      bad+=("$file (missing)")
      continue
    fi
    if [ ! -x "$file" ]; then
      bad+=("$file (not executable on disk)")
      continue
    fi
    mode="$(git ls-files -s -- "$file" | awk '{print $1}' | head -n 1)"
    if [ -z "$mode" ]; then
      # Not committed yet: the on-disk bit is all that exists. `git add`
      # preserves it, so this is a note rather than a failure.
      continue
    fi
    if [ "$mode" != "100755" ]; then
      bad+=("$file (git mode $mode, expected 100755)")
    fi
  done
  if [ "${#bad[@]}" -gt 0 ]; then
    fail_lines "$name" "${#bad[@]} script(s) not properly executable" "${bad[@]}"
    return 1
  fi
  report_pass "$name" "${#REQUIRED_EXECUTABLES[@]} script(s) executable on disk and in the index"
}

# --- 7. provenance -----------------------------------------------------------
check_provenance() {
  local name="provenance"
  selected "$name" || return 0
  if [ ! -f .ecc/VERSION ] || [ -L .ecc/VERSION ] || [ -L .ecc ]; then
    fail_lines "$name" ".ecc/VERSION must be a regular committed provenance record"
    return 1
  fi
  local required_keys=(
    ADAPTER_NAME ADAPTER_VERSION ADAPTER_KIND ADAPTER_TARGET_HARNESS
    ADAPTER_NATIVE_ECC_RUNTIME UPSTREAM_NAME UPSTREAM_REPO UPSTREAM_LICENSE
    UPSTREAM_COPYRIGHT UPSTREAM_LICENSE_FILE UPSTREAM_LICENSE_SHA256
    UPSTREAM_VERSION UPSTREAM_TAG UPSTREAM_COMMIT UPSTREAM_NPM_PACKAGE
    UPSTREAM_NPM_VERSION UPSTREAM_MAIN_COMMIT_AT_REVIEW
    UPSTREAM_MAIN_VERSION_AT_REVIEW UPSTREAM_REVIEWED_AT
    AGENTSHIELD_NPM_PACKAGE AGENTSHIELD_NPM_VERSION AGENTSHIELD_REPO
    AGENTSHIELD_LICENSE AGENTSHIELD_INVOKE
    FOUNDATION_SOURCE_REPO FOUNDATION_SOURCE_COMMIT FOUNDATION_SYNCED_AT
  )
  local key value count line bad=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || bad+=(".ecc/VERSION contains a malformed assignment")
  done < .ecc/VERSION
  for key in "${required_keys[@]}"; do
    count="$(version_key_count "$key")"
    [ "$count" -eq 1 ] || bad+=("$key must occur exactly once (found ${count})")
    value="$(version_value "$key")"
    [ -n "$value" ] || bad+=("$key is empty or absent")
  done

  # Reviewed pins, not merely strings with plausible syntax. Changing these is
  # a separate, explicit provenance review. A sync must not silently upgrade
  # ECC, redirect npx to another package or turn Ditto into a generic template.
  local licence_sha=326146379f01bb137c0a5d3c54770c1aa31076705c8b88a7f6b26a460f6221b2
  local reviewed_values=(
    'ADAPTER_NAME=ditto-ecc-arena-adapter'
    'ADAPTER_VERSION=0.1.0'
    'ADAPTER_KIND=ecc-on-arena-adaptation'
    'ADAPTER_TARGET_HARNESS=arena-agent-mode'
    'ADAPTER_NATIVE_ECC_RUNTIME=false'
    'UPSTREAM_NAME=Everything Claude Code (ECC)'
    'UPSTREAM_REPO=https://github.com/affaan-m/ECC'
    'UPSTREAM_LICENSE=MIT'
    'UPSTREAM_COPYRIGHT=Copyright (c) 2026 Affaan Mustafa'
    'UPSTREAM_LICENSE_FILE=.ecc/LICENSE-ECC'
    "UPSTREAM_LICENSE_SHA256=${licence_sha}"
    'UPSTREAM_VERSION=2.2.0'
    'UPSTREAM_TAG=v2.2.0'
    'UPSTREAM_COMMIT=5eddf1a3ffd311423be2d4ba7d26f7209c91b033'
    'UPSTREAM_NPM_PACKAGE=ecc-universal'
    'UPSTREAM_NPM_VERSION=2.2.0'
    'UPSTREAM_MAIN_COMMIT_AT_REVIEW=e04ea0b9cc8248686edf5ac751cadff550e162b8'
    'UPSTREAM_MAIN_VERSION_AT_REVIEW=2.2.1-unreleased'
    'UPSTREAM_REVIEWED_AT=2026-09-06'
    'AGENTSHIELD_NPM_PACKAGE=ecc-agentshield'
    'AGENTSHIELD_NPM_VERSION=1.4.0'
    'AGENTSHIELD_REPO=https://github.com/affaan-m/agentshield'
    'AGENTSHIELD_LICENSE=MIT'
    'AGENTSHIELD_INVOKE=npx -y ecc-agentshield@1.4.0 scan --format json'
    'FOUNDATION_SOURCE_REPO=https://github.com/anthracite-labs/App-Factory'
    'FOUNDATION_SOURCE_COMMIT=ffe4382677c5237d2c86066c96742cf96a5f10fe'
  )
  local record
  for record in "${reviewed_values[@]}"; do
    key="${record%%=*}"
    [ "$(version_value "$key")" = "${record#*=}" ] ||
      bad+=("$key differs from the reviewed Ditto foundation/ECC record")
  done
  value="$(version_value FOUNDATION_SYNCED_AT)"
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || bad+=("FOUNDATION_SYNCED_AT must be YYYY-MM-DD")

  if [ ! -f .ecc/UPSTREAM.md ] || [ -L .ecc/UPSTREAM.md ]; then
    bad+=(".ecc/UPSTREAM.md missing or not a regular provenance document")
  else
    grep -qi 'MIT' .ecc/UPSTREAM.md || bad+=(".ecc/UPSTREAM.md does not state the MIT licence")
    grep -qF '.ecc/LICENSE-ECC' .ecc/UPSTREAM.md || bad+=(".ecc/UPSTREAM.md does not reference the committed notice")
    for key in FOUNDATION_SOURCE_REPO FOUNDATION_SOURCE_COMMIT UPSTREAM_COMMIT; do
      grep -qF "$(version_value "$key")" .ecc/UPSTREAM.md ||
        bad+=(".ecc/UPSTREAM.md does not record $key")
    done
  fi
  if [ ! -f .ecc/LICENSE-ECC ] || [ -L .ecc/LICENSE-ECC ]; then
    bad+=(".ecc/LICENSE-ECC must carry the full upstream MIT notice as a regular file")
  elif ! command -v sha256sum >/dev/null 2>&1; then
    bad+=("sha256sum required to verify the ECC licence; integrity cannot be skipped")
  else
    [ "$(sha256sum .ecc/LICENSE-ECC | cut -d' ' -f1)" = "$licence_sha" ] ||
      bad+=(".ecc/LICENSE-ECC differs from the byte-exact reviewed MIT notice")
    grep -qF 'Copyright (c) 2026 Affaan Mustafa' .ecc/LICENSE-ECC || bad+=("MIT copyright missing")
    grep -qF 'Permission is hereby granted, free of charge' .ecc/LICENSE-ECC || bad+=("MIT permission notice missing")
    grep -qF 'THE SOFTWARE IS PROVIDED "AS IS"' .ecc/LICENSE-ECC || bad+=("MIT warranty disclaimer missing")
  fi
  if [ "${#bad[@]}" -gt 0 ]; then
    fail_lines "$name" "${#bad[@]} provenance problem(s)" "${bad[@]}"
    return 1
  fi
  report_pass "$name" "Ditto identity, App-Factory source pin and ECC 2.2.0 @ 5eddf1a verified; full MIT notice intact"
}

# --- 8. attribution ----------------------------------------------------------
# Every adapted rule/skill/role must carry an ECC attribution header (MIT terms).
check_attribution() {
  local name="attribution"
  selected "$name" || return 0
  local upstream_version
  upstream_version="$(version_value UPSTREAM_VERSION)"
  if [ -z "$upstream_version" ]; then
    fail_lines "$name" "cannot determine UPSTREAM_VERSION from .ecc/VERSION"
    return 1
  fi
  local needle="Adapted from ECC v${upstream_version}"
  local file bad=() count=0
  while IFS= read -r file; do
    case "$file" in
      .ecc/skills/INDEX.md) continue ;;
    esac
    count=$((count + 1))
    grep -qF "$needle" "$file" || bad+=("$file (missing: ${needle})")
  done < <(ecc_files .ecc/rules .ecc/skills .ecc/roles)
  if [ "$count" -eq 0 ]; then
    fail_lines "$name" "no adapted files found under .ecc/rules, .ecc/skills, .ecc/roles"
    return 1
  fi
  if [ "${#bad[@]}" -gt 0 ]; then
    fail_lines "$name" "${#bad[@]} file(s) missing attribution" "${bad[@]}"
    return 1
  fi
  report_pass "$name" "$count adapted file(s) attributed to ECC v${upstream_version}"
}

# --- 9. skill index ----------------------------------------------------------
# Bidirectional: index rows resolve to files, and every workflow is indexed.
check_skill_index() {
  local name="skill_index"
  selected "$name" || return 0
  local index=".ecc/skills/INDEX.md"
  if [ ! -f "$index" ]; then
    fail_lines "$name" "$index missing"
    return 1
  fi
  local problems=()
  local referenced
  mapfile -t referenced < <(grep -oE '\.ecc/(skills|roles)/[A-Za-z0-9._-]+\.md' "$index" | sort -u)
  if [ "${#referenced[@]}" -eq 0 ]; then
    fail_lines "$name" "$index references no workflow paths"
    return 1
  fi
  local path
  for path in "${referenced[@]}"; do
    [ -f "$path" ] || problems+=("index references missing file: $path")
  done
  local file
  while IFS= read -r file; do
    case "$file" in
      .ecc/skills/INDEX.md) continue ;;
    esac
    if ! grep -qF "$file" "$index"; then
      problems+=("workflow not referenced by index: $file")
    fi
  done < <(ecc_files .ecc/skills .ecc/roles)
  if [ "${#problems[@]}" -gt 0 ]; then
    fail_lines "$name" "${#problems[@]} index inconsistency(ies)" "${problems[@]}"
    return 1
  fi
  local size
  size="$(wc -c < "$index" | tr -d '[:space:]')"
  report_pass "$name" "${#referenced[@]} indexed path(s) resolve bidirectionally (${size} bytes)"
}

# --- 10. bootstrap -----------------------------------------------------------
# Every path BOOTSTRAP.md points at must exist, and it must route to every
# workflow in the index. Startup context must also stay small.
check_bootstrap() {
  local name="bootstrap"
  selected "$name" || return 0
  local boot=".ecc/BOOTSTRAP.md"
  if [ ! -f "$boot" ]; then
    fail_lines "$name" "$boot missing"
    return 1
  fi
  local problems=() checked=0
  local always_read=(
    .ecc/BOOTSTRAP.md
    .ecc/rules/engineering.md
    .ecc/skills/INDEX.md
    docs/MEMORY.md
    config/project.env
    scripts/verify.sh
  )
  local f
  for f in "${always_read[@]}"; do
    checked=$((checked + 1))
    [ -e "$f" ] || problems+=("always-read file missing: $f")
    grep -qF "$f" "$boot" || problems+=("bootstrap does not mention always-read file: $f")
  done
  local mention
  while IFS= read -r mention; do
    [ -n "$mention" ] || continue
    mention="${mention%.}"
    checked=$((checked + 1))
    if [ ! -e "$mention" ]; then
      problems+=("bootstrap references missing path: $mention")
    fi
  done < <(grep -oE '(\.ecc|docs|scripts|config|\.github)/[A-Za-z0-9._/-]+' "$boot" | sort -u)
  while IFS= read -r mention; do
    [ -n "$mention" ] || continue
    checked=$((checked + 1))
    [ -f "$mention" ] || problems+=("bootstrap references missing root file: $mention")
  done < <(
    # Root-level UPPERCASE.md mentions only: a preceding path separator means
    # the mention belongs to the path scan above, not to this one.
    grep -oE '(^|[^A-Za-z0-9._/-])[A-Z][A-Za-z0-9_-]*\.md' "$boot" |
      sed -E 's/^[^A-Za-z0-9]//' | sort -u
  )
  local file base
  while IFS= read -r file; do
    case "$file" in
      .ecc/skills/INDEX.md) continue ;;
    esac
    base="$(basename -- "$file")"
    grep -qF "$base" "$boot" || problems+=("bootstrap does not route to workflow: $base")
  done < <(ecc_files .ecc/skills)
  # Startup context must stay small: the whole point of on-demand loading.
  local lines
  lines="$(wc -l < "$boot" | tr -d '[:space:]')"
  if [ "$lines" -gt 220 ]; then
    problems+=("bootstrap is $lines lines; startup context must stay small (<= 220)")
  fi
  if [ "${#problems[@]}" -gt 0 ]; then
    fail_lines "$name" "${#problems[@]} bootstrap problem(s)" "${problems[@]}"
    return 1
  fi
  report_pass "$name" "$checked path reference(s) resolve; bootstrap is $lines lines"
}

# --- 11. CI wiring -----------------------------------------------------------
# CI must invoke the same committed gate, keep least privilege, and keep the
# exact job names that config/main-ruleset.json requires as status contexts.
check_ci_wiring() {
  local name="ci_wiring"
  selected "$name" || return 0
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import yaml' >/dev/null 2>&1; then
    fail_lines "$name" "Python 3 and PyYAML required for structural CI validation (CI installs PyYAML)"
    return 1
  fi
  local out rc
  out="$(python3 - "${REQUIRED_CI_CONTEXTS[@]}" <<'PYEOF' 2>&1
import copy
import json
import re
import sys
import yaml

wanted_names = sys.argv[1:]
problems = []

# SafeLoader with YAML 1.2-style booleans: GitHub's `on` is a key, not True.
# Reject duplicate mapping keys at every level instead of taking the last one.
class WorkflowLoader(yaml.SafeLoader):
    pass
WorkflowLoader.yaml_implicit_resolvers = copy.deepcopy(yaml.SafeLoader.yaml_implicit_resolvers)
for key, resolvers in WorkflowLoader.yaml_implicit_resolvers.items():
    WorkflowLoader.yaml_implicit_resolvers[key] = [(tag, regex) for tag, regex in resolvers if tag != 'tag:yaml.org,2002:bool']
WorkflowLoader.add_implicit_resolver('tag:yaml.org,2002:bool', re.compile(r'^(?:true|false)$', re.I), list('tTfF'))

def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, str) or key in result:
            raise ValueError('ambiguous YAML key')
        result[key] = loader.construct_object(value_node, deep=deep)
    return result
WorkflowLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)

def unique_json(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError('duplicate JSON key')
        obj[key] = value
    return obj

try:
    with open('.github/workflows/verify.yml', encoding='utf-8') as fh:
        wf = yaml.load(fh, Loader=WorkflowLoader)
    with open('config/main-ruleset.json', encoding='utf-8') as fh:
        policy = json.load(fh, object_pairs_hook=unique_json)
except (OSError, ValueError, yaml.YAMLError):
    print('workflow/ruleset must be readable, valid data without duplicate keys')
    sys.exit(1)
if not isinstance(wf, dict):
    print('workflow must be a mapping')
    sys.exit(1)

# Required checks must actually run for main pushes and every PR, not just
# contain the names of those events in a comment, filtered mapping or run block.
events = wf.get('on')
if not isinstance(events, dict) or set(events) != {'push', 'pull_request', 'workflow_dispatch'}:
    problems.append('workflow must declare push, pull_request and workflow_dispatch events')
else:
    if events['push'] != {'branches': ['main']}:
        problems.append('push trigger must cover main without path or other filters')
    if events['pull_request'] not in (None, {}):
        problems.append('pull_request must not be filtered')
    if events['workflow_dispatch'] not in (None, {}):
        problems.append('workflow_dispatch must remain unconditional')
if wf.get('permissions') != {'contents': 'read'}:
    problems.append('workflow permissions must be exactly contents: read')
# No alternate shell, workspace or environment may quietly change what these
# literal commands execute. Such additions need an explicit policy review.
if 'defaults' in wf or 'env' in wf:
    problems.append('workflow-level execution overrides are not permitted in foundation CI')

jobs = wf.get('jobs')
if not isinstance(jobs, dict) or set(jobs) != {'gate', 'independent-checks'}:
    problems.append('workflow must contain exactly gate and independent-checks jobs')
    jobs = jobs if isinstance(jobs, dict) else {}
names = []
for job_id, job in jobs.items():
    if not isinstance(job, dict):
        problems.append('job must be a mapping')
        continue
    names.append(job.get('name'))
    if not isinstance(job.get('runs-on'), str) or not job['runs-on']:
        problems.append('each required job needs an actual runner')
    if any(key in job for key in ('if', 'needs', 'strategy', 'defaults', 'env', 'uses')):
        problems.append('required jobs must execute independently without conditions, matrices or execution overrides')
    if job.get('continue-on-error', False) is not False:
        problems.append('required jobs cannot ignore failures')
    if 'permissions' in job and job['permissions'] != {'contents': 'read'}:
        problems.append('job permissions must be exactly contents: read when overridden')
    steps = job.get('steps')
    if not isinstance(steps, list) or not steps:
        problems.append('required jobs must have executable steps')
        continue
    checkout = False
    for step in steps:
        if not isinstance(step, dict):
            problems.append('step must be a mapping')
            continue
        if 'if' in step or step.get('continue-on-error', False) is not False:
            problems.append('foundation steps cannot be skipped or ignore failures')
        if step.get('working-directory', '.') != '.' or step.get('shell', 'bash') != 'bash':
            problems.append('foundation steps must use the repository root and default bash semantics')
        if 'env' in step:
            is_gate_env = (job_id == 'gate' and isinstance(step.get('run'), str)
                           and step['run'].strip() == 'bash scripts/verify.sh'
                           and step['env'] == {'VERIFY_AGENTSHIELD': 'require'})
            if not is_gate_env:
                problems.append('step environment overrides must not alter the shell or bypass required checks')
        action = step.get('uses')
        if action is not None:
            if not isinstance(action, str) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}', action):
                problems.append('every action must be pinned to a full commit SHA, including quoted uses values')
            elif action.startswith('actions/checkout@'):
                checkout = True
                if step.get('with') != {'persist-credentials': False}:
                    problems.append('checkout must use the actual triggering ref/repository/path and not persist credentials')
            if 'run' in step:
                problems.append('a step cannot combine uses and run')
    if not checkout:
        problems.append('every required job must check out the repository with a pinned action')
if len(names) != len(wanted_names) or any(not isinstance(n, str) for n in names) or sorted(names) != sorted(wanted_names):
    problems.append('actual job names must be exactly Foundation gate and Independent checks')
if isinstance(jobs.get('gate'), dict) and jobs['gate'].get('name') != wanted_names[0]:
    problems.append('gate must retain its required Foundation gate context')
if isinstance(jobs.get('independent-checks'), dict) and jobs['independent-checks'].get('name') != wanted_names[1]:
    problems.append('independent-checks must retain its required Independent checks context')

def command_steps(job_id, command):
    job = jobs.get(job_id, {})
    if not isinstance(job, dict) or not isinstance(job.get('steps'), list):
        return []
    return [step for step in job['steps'] if isinstance(step, dict)
            and isinstance(step.get('run'), str) and step['run'].strip() == command]

full_gate = command_steps('gate', 'bash scripts/verify.sh')
if len(full_gate) != 1:
    problems.append('Foundation gate must execute the full bash scripts/verify.sh exactly once, not echo/comment/partial checks')
elif full_gate[0].get('env') != {'VERIFY_AGENTSHIELD': 'require'}:
    problems.append('the real gate step must require the pinned AgentShield invocation (zero files remains advisory)')
if len(command_steps('gate', 'bash scripts/selftest.sh')) != 1:
    problems.append('Foundation gate must execute bash scripts/selftest.sh exactly once')
independent_command = 'bash scripts/verify.sh --only=foundation_version --only=provenance --only=lifecycle --only=no_app_stack --only=ruleset --only=ci_wiring'
if len(command_steps('independent-checks', independent_command)) != 1:
    problems.append('Independent checks must run the standalone foundation, provenance, lifecycle, stack, ruleset and CI contracts')

# Cross-check the actual required_status_checks rule, not decoy names elsewhere.
try:
    rules = [r for r in policy['rules'] if r['type'] == 'required_status_checks']
    contexts = [c['context'] for c in rules[0]['parameters']['required_status_checks']]
    if len(rules) != 1 or sorted(contexts) != sorted(wanted_names):
        raise ValueError('wrong contexts')
except (KeyError, IndexError, TypeError, ValueError):
    problems.append('ruleset must require exactly the two actual CI job contexts')
for problem in problems:
    print(problem)
sys.exit(1 if problems else 0)
PYEOF
  )"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_lines "$name" "structural CI contract failed" "$out"
    return 1
  fi
  report_pass "$name" "actual gate/self-test steps, exact required job contexts, pinned actions and read-only permissions verified"
}

# --- 12. secrets -------------------------------------------------------------
# Credential-shaped values must never be committed.
#
# Two properties are load-bearing here and both are covered by
# scripts/selftest.sh:
#
#   1. REDACTION. A finding is reported as "path:line [category]" only. The
#      matched text and the source line are never printed, so a real
#      credential that is accidentally committed cannot be echoed into CI logs
#      by the very check meant to catch it. Matched material stays in memory.
#   2. NO EXEMPTIONS. There is no allowlist of any kind - not "line contains a
#      word like example/todo", and not "value looks like a placeholder". Every
#      match is a finding. A repeated-character value - an all-x or all-zero
#      PASSWORD assignment - is still caught, because a structurally simple
#      value can be a real password. Documentation examples should therefore
#      simply not be credential-shaped: leave the value empty, or use angle
#      brackets, neither of which matches the patterns below.
#
# Patterns are assembled from string fragments so this script does not match
# itself.
check_secrets() {
  local name="secrets"
  selected "$name" || return 0

  # "category|regex" pairs. The category is the only thing reported.
  local -a rules
  rules=(
    'github-classic-token|gh''p_[A-Za-z0-9]{36,}'
    'github-fine-grained-pat|github_''pat_[A-Za-z0-9_]{22,}'
    'github-oauth-token|gho_[A-Za-z0-9]{36,}'
    'github-app-token|ghs_[A-Za-z0-9]{36,}'
    'aws-access-key-id|AK''IA[0-9A-Z]{16}'
    'slack-token|xo''x[baprs]-[A-Za-z0-9-]{10,}'
    'gitlab-pat|gl''pat-[A-Za-z0-9_-]{20,}'
    'google-api-key|AI''za[0-9A-Za-z_-]{35}'
    'openai-style-key|sk''-[A-Za-z0-9_-]{20,}'
    'private-key-block|-----BEGIN ''[A-Z ]*PRIVATE KEY-----'
    'generic-credential-assignment|(API_''KEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE_KEY)[A-Z_]*[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{16,}'
  )

  local -a findings=() unreadable=()
  local file category regex rule lines rc lineno safe_path file_count=0
  # Discover filenames with NUL separators, then ask grep for line numbers in
  # ONE file at a time. Strip everything after the first colon in that stream
  # before capturing it. Unlike path:line:match parsing, neither colons nor
  # newlines in a filename can make matched text reach a finding or CI log.
  while IFS= read -r -d '' file; do
    file_count=$((file_count + 1))
    printf -v safe_path '%q' "${file#./}"
    # Even a credential-shaped filename must not become a disclosure path.
    for rule in "${rules[@]}"; do
      regex="${rule#*|}"
      if [[ "$file" =~ $regex ]]; then
        safe_path="<redacted-filename-${file_count}>"
        break
      fi
    done
    for rule in "${rules[@]}"; do
      category="${rule%%|*}"
      regex="${rule#*|}"
      lines="$(LC_ALL=C grep -noIE -- "$regex" "$file" 2>/dev/null | cut -d: -f1)"
      rc=$?
      if [ "$rc" -gt 1 ]; then
        unreadable+=("$safe_path (scan could not read file)")
        break
      fi
      [ -n "$lines" ] || continue
      while IFS= read -r lineno; do
        # Defensive: only numbers are reportable, never arbitrary grep output.
        if [[ "$lineno" =~ ^[0-9]+$ ]]; then
          findings+=("${safe_path}:${lineno} [${category}]")
        else
          unreadable+=("$safe_path (unrecognized scan result)")
        fi
      done <<< "$lines"
    done
  done < <(find . -type d -name .git -prune -o -type f -print0)
  if [ "${#unreadable[@]}" -gt 0 ]; then
    fail_lines "$name" "scan incomplete; unreadable files cannot be treated as clean" "${unreadable[@]}"
    return 1
  fi
  if [ "${#findings[@]}" -gt 0 ]; then
    fail_lines "$name" "${#findings[@]} credential-shaped value(s) found (values redacted)" \
      "${findings[@]}" \
      "Matched material is intentionally not printed. Inspect the locations" \
      "above locally, and rotate anything already exposed."
    return 1
  fi
  report_pass "$name" "$file_count file(s) scanned, no credential-shaped values"
}

# --- 13. dotenv files --------------------------------------------------------
# .gitignore cannot stop `git add -f`, so the presence of a dotenv file is
# enforced here rather than left to documentation. config/project.env is NOT a
# dotenv file: it is committed lifecycle state, parsed line-by-line and never
# sourced, and it is separately validated by check_lifecycle.
check_env_files() {
  local name="env_files"
  selected "$name" || return 0
  local found=() file base safe_path
  while IFS= read -r -d '' file; do
    base="${file##*/}"
    # The deliberate example exception is a regular file only, and the
    # secrets sweep still scans its content. No depth or suffix escape hatch.
    if [ "$base" = .env.example ] && [ -f "$file" ] && [ ! -L "$file" ]; then
      continue
    fi
    printf -v safe_path '%q' "${file#./}"
    found+=("$safe_path")
  done < <(find . -type d -name .git -prune -o -name '.env*' -print0)
  if [ "${#found[@]}" -gt 0 ]; then
    fail_lines "$name" "${#found[@]} prohibited dotenv path(s) present" "${found[@]}" \
      "Only regular .env.example templates are allowed. Secrets belong in the environment."
    return 1
  fi
  report_pass "$name" "no prohibited .env* paths (only regular .env.example templates allowed)"
}

# --- 14. lifecycle -----------------------------------------------------------
# The project lifecycle configuration must be well-formed AND internally
# consistent. In particular, standing the no-stack guard down is only valid as
# a deliberate, documented transition: implementation phase plus an ADR that
# actually exists. This is what stops ALLOW_APP_STACK=1 from being smuggled in
# as a one-character edit, and it is why the guard is no longer a constant
# inside this script.
check_lifecycle() {
  local name="lifecycle"
  selected "$name" || return 0
  local problems=()
  if ! validate_project_config problems; then
    fail_lines "$name" "${#problems[@]} lifecycle configuration problem(s)" "${problems[@]}"
    return 1
  fi
  report_pass "$name" "phase=$(config_value PROJECT_PHASE), allow_app_stack=$(config_value ALLOW_APP_STACK)"
}

# --- 15. no application stack ------------------------------------------------
# Lifecycle-aware. In discovery/architecture phases the foundation
# rejects application-stack artifacts. After an explicit, ADR-backed transition
# recorded in config/project.env, this FOUNDATION guard stands down — which is
# not the same as the project being tested: stack-specific lint/test/build
# gates are added separately at that point.
check_no_app_stack() {
  local name="no_app_stack"
  selected "$name" || return 0
  local problems=()
  if ! validate_project_config problems; then
    fail_lines "$name" "invalid lifecycle state; guard cannot stand down" "${problems[@]}"
    return 1
  fi
  local allow phase adr
  allow="$(config_value ALLOW_APP_STACK)"
  phase="$(config_value PROJECT_PHASE)"
  adr="$(config_value STACK_DECISION_ADR)"
  if [ "$allow" = 1 ]; then
    report_skip "$name" "guard stood down: phase=${phase}, ADR=${adr} (stack-specific checks apply instead)"
    return 0
  fi
  local -a forbidden_files
  forbidden_files=(
    package.json package-lock.json yarn.lock pnpm-lock.yaml bun.lockb
    requirements.txt pyproject.toml Pipfile poetry.lock setup.py
    go.mod Cargo.toml Gemfile composer.json pom.xml build.gradle
    Dockerfile docker-compose.yml tsconfig.json Makefile
  )
  local -a forbidden_dirs
  forbidden_dirs=(src app lib client server frontend backend api)
  local found=() entry file base safe_path
  while IFS= read -r -d '' file; do
    base="${file##*/}"
    for entry in "${forbidden_files[@]}"; do
      if [ "$base" = "$entry" ]; then
        printf -v safe_path '%q' "${file#./}"
        found+=("$safe_path")
        break
      fi
    done
  done < <(find . -type d -name .git -prune -o \( -type f -o -type l \) -print0)
  for entry in "${forbidden_dirs[@]}"; do
    if [ -d "$entry" ]; then
      found+=("${entry}/")
    fi
  done
  if [ "${#found[@]}" -gt 0 ]; then
    fail_lines "$name" "${#found[@]} application-stack artifact(s) present" \
      "${found[@]}" \
      "This repository is in the '${phase:-unknown}' phase, where a stack is not yet allowed." \
      "A stack choice requires an approved issue and an ADR in docs/decisions/." \
      "If that has happened, transition the repository in ${PROJECT_CONFIG}:" \
      "  PROJECT_PHASE=implementation, ALLOW_APP_STACK=1, STACK_DECISION_ADR=docs/decisions/NNNN-....md" \
      "Do not edit this script to make the guard pass."
    return 1
  fi
  report_pass "$name" "no framework, database, build, or UI artifacts committed (phase=${phase:-unknown})"
}

# --- 16. ruleset -------------------------------------------------------------
# config/main-ruleset.json must parse, be portable (no instance-specific ids),
# and encode the branch-protection intent the workflow depends on.
check_ruleset() {
  local name="ruleset"
  selected "$name" || return 0
  local file=config/main-ruleset.json
  if [ ! -f "$file" ]; then
    fail_lines "$name" "$file missing"
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    fail_lines "$name" "python3 required for structural ruleset validation; cannot skip policy"
    return 1
  fi
  local out rc
  out="$(python3 - "$file" "${REQUIRED_CI_CONTEXTS[@]}" <<'PYEOF' 2>&1
import json
import sys

path, *wanted_contexts = sys.argv[1:]
problems = []

def unique_object(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError('duplicate JSON key')
        obj[key] = value
    return obj

def exact_keys(obj, keys, location):
    if not isinstance(obj, dict) or set(obj) != set(keys):
        problems.append(location + ': missing or unexpected fields (no export/instance IDs allowed)')
        return False
    return True

def boolean(obj, key, expected, location):
    if obj.get(key) is not expected:
        problems.append(location + '.' + key + ': incorrect boolean policy')

try:
    with open(path, encoding='utf-8') as fh:
        doc = json.load(fh, object_pairs_hook=unique_object)
except (OSError, ValueError):
    print('ruleset must be readable JSON without duplicate keys')
    sys.exit(1)

if not exact_keys(doc, ('name', 'target', 'enforcement', 'conditions', 'bypass_actors', 'rules'), 'ruleset'):
    print('\n'.join(problems))
    sys.exit(1)
if not isinstance(doc['name'], str) or not doc['name'].strip():
    problems.append('ruleset.name must be a non-empty string')
if doc['target'] != 'branch' or doc['enforcement'] != 'active':
    problems.append('ruleset must actively enforce branch policy')
if doc['bypass_actors'] != []:
    problems.append('bypass_actors must be an empty list')
conditions = doc['conditions']
if exact_keys(conditions, ('ref_name',), 'conditions'):
    ref = conditions['ref_name']
    if exact_keys(ref, ('include', 'exclude'), 'conditions.ref_name'):
        if ref['include'] != ['~DEFAULT_BRANCH'] or ref['exclude'] != []:
            problems.append('scope must include only ~DEFAULT_BRANCH, with no exclusions')

# Ditto also retains its existing creation protection, absent from the master
# template. Index by rule type, never by array position or a decoy text match.
required_types = {'creation', 'deletion', 'non_fast_forward', 'pull_request', 'required_status_checks'}
by_type = {}
if not isinstance(doc['rules'], list):
    problems.append('rules must be a list')
else:
    for rule in doc['rules']:
        if not isinstance(rule, dict) or not isinstance(rule.get('type'), str):
            problems.append('every rule must be an object with a string type')
            continue
        kind = rule['type']
        if kind not in required_types or kind in by_type:
            problems.append('unexpected or duplicate rule type')
            continue
        by_type[kind] = rule
        fields = ('type', 'parameters') if kind in ('pull_request', 'required_status_checks') else ('type',)
        exact_keys(rule, fields, 'rule.' + kind)
if set(by_type) != required_types:
    problems.append('creation, deletion, non_fast_forward, pull_request and required_status_checks rules are required')

pr = by_type.get('pull_request', {}).get('parameters')
pr_fields = (
    'required_approving_review_count', 'dismiss_stale_reviews_on_push',
    'require_code_owner_review', 'require_last_push_approval',
    'required_review_thread_resolution', 'allowed_merge_methods',
    'require_extra_approval_for_unattributed_changes',
)
if exact_keys(pr, pr_fields, 'pull_request.parameters'):
    if type(pr['required_approving_review_count']) is not int or pr['required_approving_review_count'] != 0:
        problems.append('required_approving_review_count must be integer 0 (existing solo-owner policy)')
    for key in ('dismiss_stale_reviews_on_push', 'required_review_thread_resolution', 'require_extra_approval_for_unattributed_changes'):
        boolean(pr, key, True, 'pull_request')
    for key in ('require_code_owner_review', 'require_last_push_approval'):
        boolean(pr, key, False, 'pull_request')
    methods = pr['allowed_merge_methods']
    if not isinstance(methods, list) or not all(isinstance(x, str) for x in methods) or sorted(methods) != ['merge', 'rebase', 'squash']:
        problems.append('allowed_merge_methods must retain merge, rebase and squash exactly once')

sc = by_type.get('required_status_checks', {}).get('parameters')
if exact_keys(sc, ('strict_required_status_checks_policy', 'do_not_enforce_on_create', 'required_status_checks'), 'required_status_checks.parameters'):
    boolean(sc, 'strict_required_status_checks_policy', True, 'required_status_checks')
    boolean(sc, 'do_not_enforce_on_create', False, 'required_status_checks')
    checks = sc['required_status_checks']
    found = []
    if not isinstance(checks, list):
        problems.append('required_status_checks must be a list')
    else:
        for check in checks:
            if exact_keys(check, ('context',), 'required_status_checks.entry'):
                if not isinstance(check['context'], str):
                    problems.append('status context must be a string')
                else:
                    found.append(check['context'])
    if sorted(found) != sorted(wanted_contexts):
        problems.append('required status contexts must be exactly Foundation gate and Independent checks, once each')

for problem in problems:
    print(problem)
sys.exit(1 if problems else 0)
PYEOF
  )"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    fail_lines "$name" "structural ruleset validation failed" "$out"
    return 1
  fi
  if ! grep -qF 'config/main-ruleset.json' docs/FOUNDATION.md 2>/dev/null; then
    fail_lines "$name" "docs/FOUNDATION.md must explain the payload and human-only administration"
    return 1
  fi
  report_pass "$name" "portable policy: exact CI contexts, strict PR rules, branch protections, no bypass or instance IDs"
}

# --- 17. AgentShield ---------------------------------------------------------
check_agentshield() {
  local name="agentshield"
  selected "$name" || return 0
  if [ "$AGENTSHIELD_MODE" = off ]; then
    report_skip "$name" "disabled (VERIFY_AGENTSHIELD=off)"
    return 0
  fi
  local pkg ver
  pkg="$(version_value AGENTSHIELD_NPM_PACKAGE)"
  ver="$(version_value AGENTSHIELD_NPM_VERSION)"
  # Revalidate before execution even when --only skips provenance. A failed
  # earlier check must not cause us to run an unreviewed replacement package.
  if [ "$pkg" != ecc-agentshield ] || [ "$ver" != 1.4.0 ] ||
     [ "$(version_key_count AGENTSHIELD_NPM_PACKAGE)" != 1 ] ||
     [ "$(version_key_count AGENTSHIELD_NPM_VERSION)" != 1 ]; then
    fail_lines "$name" "scanner must retain its unique reviewed ecc-agentshield@1.4.0 pin; not executed"
    return 1
  fi
  if ! command -v npx >/dev/null 2>&1; then
    if [ "$AGENTSHIELD_MODE" = require ]; then
      fail_lines "$name" "npx unavailable in required mode"
      return 1
    fi
    report_skip "$name" "npx unavailable"
    return 0
  fi
  local out rc
  # Static mode only; deep/injection/sandbox/taint probes are never automatic.
  out="$(timeout 600 npx --yes "${pkg}@${ver}" scan --format json 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    if [ "$AGENTSHIELD_MODE" = require ]; then
      fail_lines "$name" "scan failed or produced no output (exit $rc)"
      return 1
    fi
    report_skip "$name" "scanner unreachable (exit $rc); not counted as passed"
    return 0
  fi
  local counts critical high files
  # Never default missing/unparseable fields to zero. Only normalized counters
  # leave this parser; the report (which may include credentials) is not logged.
  if ! counts="$(printf '%s' "$out" | python3 -c '
import json, sys

def unique_object(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError("duplicate report key")
        obj[key] = value
    return obj

report = json.load(sys.stdin, object_pairs_hook=unique_object)
summary = report["summary"]
counts = [summary[key] for key in ("critical", "high", "filesScanned")]
if not all(type(n) is int and 0 <= n <= 2147483647 for n in counts):
    raise ValueError("report counters must be non-negative bounded integers")
print(*counts)
' 2>/dev/null)"; then
    fail_lines "$name" "scanner returned an invalid summary (Python 3 and complete integer counters required); report not printed"
    return 1
  fi
  read -r critical high files <<< "$counts"
  if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
    fail_lines "$name" "${pkg}@${ver}: $critical critical, $high high finding(s)"
    return 1
  fi
  # A zero-file scan proves nothing, including when invocation is required.
  if [ "$files" -eq 0 ]; then
    report_skip "$name" "${pkg}@${ver} ran but scanned 0 file(s): no Claude config surface here (advisory only)"
    return 0
  fi
  report_pass "$name" "${pkg}@${ver} static scan clean ($files file(s) scanned)"
}

# --- 18. workflow YAML -------------------------------------------------------
check_workflows_yaml() {
  local name="workflows_yaml"
  selected "$name" || return 0
  local parser=""
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    parser="python3"
  fi
  if [ -z "$parser" ]; then
    report_skip "$name" "no YAML parser available (CI installs PyYAML)"
    return 0
  fi
  local file bad=() count=0
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    count=$((count + 1))
    if ! python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$file" >/dev/null 2>&1; then
      bad+=("$file")
    fi
  done < <(workflow_files)
  if [ "$count" -eq 0 ]; then
    fail_lines "$name" "no workflow files tracked"
    return 1
  fi
  if [ "${#bad[@]}" -gt 0 ]; then
    fail_lines "$name" "${#bad[@]} workflow file(s) failed to parse" "${bad[@]}"
    return 1
  fi
  report_pass "$name" "$count workflow file(s) parse as YAML"
}

# --- Registration ------------------------------------------------------------
register foundation
register foundation_version
register links
register shell_syntax
register shell_lint
register executable
register provenance
register attribution
register skill_index
register bootstrap
register ci_wiring
register secrets
register env_files
register lifecycle
register no_app_stack
register ruleset
register agentshield
register workflows_yaml

usage() {
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Argument parsing --------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) LIST_ONLY=1 ;;
    --only=*) SELECTED+=("${1#--only=}") ;;
    --only) shift; SELECTED+=("${1:-}") ;;
    --skip-agentshield) AGENTSHIELD_MODE="off" ;;
    --require-agentshield) AGENTSHIELD_MODE="require" ;;
    --quiet|-q) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      printf 'verify.sh: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$LIST_ONLY" -eq 1 ]; then
  printf '%s\n' "${CHECK_ORDER[@]}"
  exit 0
fi

for want in "${SELECTED[@]}"; do
  known=0
  for name in "${CHECK_ORDER[@]}"; do
    [ "$name" = "$want" ] && known=1 && break
  done
  if [ "$known" -eq 0 ]; then
    printf 'verify.sh: unknown check: %s\n' "$want" >&2
    printf 'available: %s\n' "${CHECK_ORDER[*]}" >&2
    exit 2
  fi
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf 'verify.sh: must run inside a git repository\n' >&2
  exit 2
fi

# --- Run ---------------------------------------------------------------------
say "Ditto foundation verification gate"
say "  repo:       $REPO_ROOT"
say "  foundation: FOUNDATION_VERSION (validated below)"
say "  branch:     $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
say "  commit:     $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
say "  lifecycle:  config/project.env (validated below; no environment override)"
say "  mode:       agentshield=${AGENTSHIELD_MODE}"
say "------------------------------------------------------------"

for check in "${CHECK_ORDER[@]}"; do
  "check_${check}"
done

say "------------------------------------------------------------"
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf '%sRESULT: FAIL%s — %d passed, %d failed, %d skipped\n' \
    "$c_fail" "$c_reset" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  printf '\nFailures:\n'
  for msg in "${FAILURE_MESSAGES[@]}"; do
    printf '  - %s\n' "$msg"
  done
  exit 1
fi

# A run in which nothing was even attempted is a failure: it would otherwise
# report success having verified nothing. A SKIP is a reported outcome, not an
# absence of one, so it counts here (a selected check that legitimately stands
# down still produced a verdict).
if [ "$((PASS_COUNT + SKIP_COUNT))" -eq 0 ]; then
  printf '%sRESULT: NO CHECKS RAN%s — nothing was verified\n' "$c_fail" "$c_reset"
  exit 1
fi

printf '%sRESULT: PASS%s — %d passed, %d failed, %d skipped\n' \
  "$c_pass" "$c_reset" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
exit 0
