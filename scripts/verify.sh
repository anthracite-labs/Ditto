#!/usr/bin/env bash
# Ditto verification gate.
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

# --- Guard: an app stack is not allowed until a product decision exists. -----
# Flip to 1 only together with an approved issue and an ADR in docs/decisions/.
ALLOW_APP_STACK="${ALLOW_APP_STACK:-0}"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT" || exit 2

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
  ARENA_CAPABILITIES.md
  .ecc/BOOTSTRAP.md
  .ecc/VERSION
  .ecc/UPSTREAM.md
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
  docs/PRODUCT.md
  docs/ARCHITECTURE.md
  docs/DOMAIN.md
  docs/ROADMAP.md
  docs/SECURITY.md
  docs/MEMORY.md
  docs/decisions/README.md
  docs/decisions/0000-template.md
  docs/codemaps/README.md
  scripts/bootstrap.sh
  scripts/verify.sh
  scripts/sync-ecc.sh
  .github/workflows/verify.yml
  .github/PULL_REQUEST_TEMPLATE.md
)

REQUIRED_EXECUTABLES=(
  scripts/bootstrap.sh
  scripts/verify.sh
  scripts/sync-ecc.sh
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

# --- 2. links ----------------------------------------------------------------
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

# --- 3. shell syntax ---------------------------------------------------------
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

# --- 4. shell lint -----------------------------------------------------------
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

# --- 5. executable bits ------------------------------------------------------
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

# --- 6. provenance -----------------------------------------------------------
check_provenance() {
  local name="provenance"
  selected "$name" || return 0
  if [ ! -f .ecc/VERSION ]; then
    fail_lines "$name" ".ecc/VERSION missing"
    return 1
  fi
  local required_keys=(
    ADAPTER_NAME ADAPTER_VERSION UPSTREAM_REPO UPSTREAM_LICENSE
    UPSTREAM_VERSION UPSTREAM_TAG UPSTREAM_COMMIT UPSTREAM_REVIEWED_AT
    AGENTSHIELD_NPM_PACKAGE AGENTSHIELD_NPM_VERSION
  )
  local key value bad=()
  for key in "${required_keys[@]}"; do
    value="$(version_value "$key")"
    if [ -z "$value" ]; then
      bad+=("$key is empty or absent")
    fi
  done
  local upstream_repo
  upstream_repo="$(version_value UPSTREAM_REPO)"
  case "$upstream_repo" in
    https://github.com/*) : ;;
    *) bad+=("UPSTREAM_REPO is not an https GitHub URL: ${upstream_repo:-<empty>}") ;;
  esac
  local commit
  commit="$(version_value UPSTREAM_COMMIT)"
  if ! printf '%s' "$commit" | grep -qE '^[0-9a-f]{40}$'; then
    bad+=("UPSTREAM_COMMIT is not a 40-char sha: ${commit:-<empty>}")
  fi
  if [ ! -f .ecc/UPSTREAM.md ]; then
    bad+=(".ecc/UPSTREAM.md missing")
  else
    grep -qi 'MIT' .ecc/UPSTREAM.md || bad+=(".ecc/UPSTREAM.md does not state the MIT licence")
  fi
  if [ "${#bad[@]}" -gt 0 ]; then
    fail_lines "$name" "${#bad[@]} provenance problem(s)" "${bad[@]}"
    return 1
  fi
  report_pass "$name" "ECC $(version_value UPSTREAM_VERSION) @ ${commit:0:7} recorded with licence"
}

# --- 7. attribution ----------------------------------------------------------
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

# --- 8. skill index ----------------------------------------------------------
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
  local file base
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

# --- 9. bootstrap ------------------------------------------------------------
# Every path BOOTSTRAP.md points at must exist, and it must route to every
# workflow in the index.
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
    scripts/verify.sh
  )
  local f
  for f in "${always_read[@]}"; do
    checked=$((checked + 1))
    [ -e "$f" ] || problems+=("always-read file missing: $f")
  done
  local mention
  while IFS= read -r mention; do
    [ -n "$mention" ] || continue
    mention="${mention%.}"
    checked=$((checked + 1))
    if [ ! -e "$mention" ]; then
      problems+=("bootstrap references missing path: $mention")
    fi
  done < <(grep -oE '(\.ecc|docs|scripts|\.github)/[A-Za-z0-9._/-]+' "$boot" | sort -u)
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
  if [ "${#problems[@]}" -gt 0 ]; then
    fail_lines "$name" "${#problems[@]} bootstrap problem(s)" "${problems[@]}"
    return 1
  fi
  local lines
  lines="$(wc -l < "$boot" | tr -d '[:space:]')"
  report_pass "$name" "$checked path reference(s) resolve; bootstrap is $lines lines"
}

# --- 10. CI wiring -----------------------------------------------------------
check_ci_wiring() {
  local name="ci_wiring"
  selected "$name" || return 0
  local wf=".github/workflows/verify.yml"
  if [ ! -f "$wf" ]; then
    fail_lines "$name" "$wf missing"
    return 1
  fi
  local problems=()
  grep -qE '^[[:space:]]*pull_request:' "$wf" || problems+=("no pull_request trigger")
  grep -qE '^[[:space:]]*push:' "$wf" || problems+=("no push trigger")
  grep -qE '^[[:space:]]*workflow_dispatch:' "$wf" || problems+=("no workflow_dispatch trigger")
  grep -qF 'scripts/verify.sh' "$wf" || problems+=("does not invoke scripts/verify.sh")
  grep -qE '^[[:space:]]*contents:[[:space:]]*read' "$wf" || problems+=("no least-privilege 'contents: read'")
  grep -qE 'runs-on:' "$wf" || problems+=("no runner declared")
  if [ "${#problems[@]}" -gt 0 ]; then
    fail_lines "$name" "${#problems[@]} workflow problem(s)" "${problems[@]}"
    return 1
  fi
  report_pass "$name" "CI runs scripts/verify.sh on push, PR, and dispatch"
}

# --- 11. secrets -------------------------------------------------------------
# Credential-shaped values must never be committed. Patterns are assembled from
# fragments so this script does not match itself.
check_secrets() {
  local name="secrets"
  selected "$name" || return 0
  local -a patterns
  patterns=(
    'gh''p_[A-Za-z0-9]{36,}'
    'github_''pat_[A-Za-z0-9_]{22,}'
    'gho_[A-Za-z0-9]{36,}'
    'ghs_[A-Za-z0-9]{36,}'
    'AK''IA[0-9A-Z]{16}'
    'xo''x[baprs]-[A-Za-z0-9-]{10,}'
    'gl''pat-[A-Za-z0-9_-]{20,}'
    'AI''za[0-9A-Za-z_-]{35}'
    'sk''-[A-Za-z0-9_-]{20,}'
    '-----BEGIN ''[A-Z ]*PRIVATE KEY-----'
    '(API_''KEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE_KEY)[A-Z_]*[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{16,}'
  )
  local -a allowlist
  allowlist=(
    placeholder example changeme 'your-' 'xxx' redacted dummy fake sample
    '<' '>' 'n/a' 'todo' 'none' 'undefined'
  )
  local pat hits line allowed token bad=() scanned=0
  for pat in "${patterns[@]}"; do
    hits="$(grep -rnIE --exclude-dir=.git -- "$pat" . 2>/dev/null | sed 's|^\./||')"
    [ -n "$hits" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      scanned=$((scanned + 1))
      allowed=0
      local lowered
      lowered="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
      for token in "${allowlist[@]}"; do
        case "$lowered" in
          *"$token"*) allowed=1; break ;;
        esac
      done
      [ "$allowed" -eq 1 ] || bad+=("$line")
    done <<< "$hits"
  done
  local file_count
  file_count="$(find . -type f -not -path './.git/*' | wc -l | tr -d '[:space:]')"
  if [ "${#bad[@]}" -gt 0 ]; then
    fail_lines "$name" "${#bad[@]} possible secret(s) in repository files" "${bad[@]}"
    return 1
  fi
  report_pass "$name" "$file_count file(s) scanned, no credential-shaped values"
}

# --- 12. no application stack ------------------------------------------------
check_no_app_stack() {
  local name="no_app_stack"
  selected "$name" || return 0
  if [ "$ALLOW_APP_STACK" = "1" ]; then
    report_skip "$name" "ALLOW_APP_STACK=1 (product decision recorded)"
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
  local found=() entry
  for entry in "${forbidden_files[@]}"; do
    [ -e "$entry" ] && found+=("$entry")
  done
  for entry in "${forbidden_dirs[@]}"; do
    if [ -d "$entry" ]; then
      found+=("${entry}/")
    fi
  done
  if [ "${#found[@]}" -gt 0 ]; then
    fail_lines "$name" "${#found[@]} application-stack artifact(s) present" \
      "${found[@]}" \
      "A stack choice requires an approved issue and an ADR in docs/decisions/." \
      "If that has happened, set ALLOW_APP_STACK=1 in scripts/verify.sh."
    return 1
  fi
  report_pass "$name" "no framework, database, build, or UI artifacts committed"
}

# --- 13. AgentShield ---------------------------------------------------------
check_agentshield() {
  local name="agentshield"
  selected "$name" || return 0
  if [ "$AGENTSHIELD_MODE" = "off" ]; then
    report_skip "$name" "disabled (VERIFY_AGENTSHIELD=off)"
    return 0
  fi
  local pkg ver
  pkg="$(version_value AGENTSHIELD_NPM_PACKAGE)"
  ver="$(version_value AGENTSHIELD_NPM_VERSION)"
  if [ -z "$pkg" ] || [ -z "$ver" ]; then
    if [ "$AGENTSHIELD_MODE" = "require" ]; then
      fail_lines "$name" "scanner not pinned in .ecc/VERSION"
      return 1
    fi
    report_skip "$name" "scanner not pinned in .ecc/VERSION"
    return 0
  fi
  if ! command -v npx >/dev/null 2>&1; then
    if [ "$AGENTSHIELD_MODE" = "require" ]; then
      fail_lines "$name" "npx unavailable in required mode"
      return 1
    fi
    report_skip "$name" "npx unavailable"
    return 0
  fi
  local out rc
  # Static mode only. The deep modes (--injection, --sandbox, --taint, --deep)
  # execute or actively probe configuration and are never run automatically.
  out="$(timeout 600 npx --yes "${pkg}@${ver}" scan --format json 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    if [ "$AGENTSHIELD_MODE" = "require" ]; then
      fail_lines "$name" "scan failed or produced no output (exit $rc)"
      return 1
    fi
    report_skip "$name" "scanner unreachable (exit $rc); not counted as passed"
    return 0
  fi
  local critical high files
  if command -v jq >/dev/null 2>&1; then
    critical="$(printf '%s' "$out" | jq -r '.summary.critical // 0')"
    high="$(printf '%s' "$out" | jq -r '.summary.high // 0')"
    files="$(printf '%s' "$out" | jq -r '.summary.filesScanned // 0')"
  else
    critical="$(printf '%s' "$out" | sed -n 's/.*"critical":[[:space:]]*\([0-9]*\).*/\1/p' | head -n 1)"
    high="$(printf '%s' "$out" | sed -n 's/.*"high":[[:space:]]*\([0-9]*\).*/\1/p' | head -n 1)"
    files="$(printf '%s' "$out" | sed -n 's/.*"filesScanned":[[:space:]]*\([0-9]*\).*/\1/p' | head -n 1)"
  fi
  critical="${critical:-0}"; high="${high:-0}"; files="${files:-0}"
  if [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then
    fail_lines "$name" "${pkg}@${ver}: $critical critical, $high high finding(s)"
    return 1
  fi
  report_pass "$name" "${pkg}@${ver} static scan clean ($files file(s) scanned)"
}

# --- 14. workflow YAML -------------------------------------------------------
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
register no_app_stack
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
say "Ditto verification gate"
say "  repo:     $REPO_ROOT"
say "  branch:   $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
say "  commit:   $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
say "  mode:     agentshield=${AGENTSHIELD_MODE}, allow_app_stack=${ALLOW_APP_STACK}"
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

if [ "$PASS_COUNT" -eq 0 ]; then
  printf '%sRESULT: NO CHECKS RAN%s — nothing was verified\n' "$c_fail" "$c_reset"
  exit 1
fi

printf '%sRESULT: PASS%s — %d passed, %d failed, %d skipped\n' \
  "$c_pass" "$c_reset" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
exit 0
