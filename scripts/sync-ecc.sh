#!/usr/bin/env bash
# Inspect the upstream ECC repository and compare it with this adapter.
#
# Inspection-only by default. This script NEVER writes to .ecc/ — local Arena
# adaptations always win over upstream text, and upgrades are deliberate,
# reviewed edits (see .ecc/UPSTREAM.md and docs/decisions/0001-ecc-on-arena-adapter.md).
#
# Usage:
#   scripts/sync-ecc.sh            report pinned vs current upstream version
#   scripts/sync-ecc.sh --fetch    also download upstream sources to a temp dir
#                                  (outside the repo) and show where to diff
#   scripts/sync-ecc.sh --mapping  print the local-file -> upstream-file map
#   scripts/sync-ecc.sh --help     usage
#
# Requires: git, and either gh (authenticated) or curl for GitHub API access.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT" || exit 2

MODE="report"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fetch) MODE="fetch" ;;
    --mapping) MODE="mapping" ;;
    -h|--help)
      sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'sync-ecc.sh: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

version_value() {
  sed -n "s/^${1}=//p" .ecc/VERSION 2>/dev/null | head -n 1
}

UPSTREAM_REPO="$(version_value UPSTREAM_REPO)"
UPSTREAM_SLUG="${UPSTREAM_REPO#https://github.com/}"
PINNED_TAG="$(version_value UPSTREAM_TAG)"
PINNED_COMMIT="$(version_value UPSTREAM_COMMIT)"
PINNED_VERSION="$(version_value UPSTREAM_VERSION)"

# local-file -> upstream source, mirroring .ecc/UPSTREAM.md
MAPPING=(
  ".ecc/rules/engineering.md|rules/common/development-workflow.md"
  ".ecc/rules/engineering.md|rules/common/code-review.md"
  ".ecc/rules/testing.md|rules/common/testing.md"
  ".ecc/rules/testing.md|skills/tdd-workflow/SKILL.md"
  ".ecc/rules/security.md|rules/common/security.md"
  ".ecc/rules/security.md|skills/security-review/SKILL.md"
  ".ecc/rules/git.md|rules/common/git-workflow.md"
  ".ecc/skills/planning.md|commands/plan.md"
  ".ecc/skills/research.md|skills/search-first/SKILL.md"
  ".ecc/skills/tdd.md|skills/tdd-workflow/SKILL.md"
  ".ecc/skills/debugging.md|skills/agent-introspection-debugging/SKILL.md"
  ".ecc/skills/code-review.md|commands/review-pr.md"
  ".ecc/skills/spec-review.md|commands/review-pr.md"
  ".ecc/skills/security-review.md|skills/security-review/SKILL.md"
  ".ecc/skills/verification.md|skills/verification-loop/SKILL.md"
  ".ecc/skills/project-memory.md|skills/unified-memory/SKILL.md"
  ".ecc/skills/decisions.md|skills/architecture-decision-records/SKILL.md"
  ".ecc/roles/architect.md|agents/architect.md"
  ".ecc/roles/security-reviewer.md|agents/security-reviewer.md"
  ".ecc/roles/spec-reviewer.md|agents/planner.md"
)

api_get() {
  local path="$1"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh api "$path" 2>/dev/null
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "https://api.github.com/${path}" 2>/dev/null
  else
    return 1
  fi
}

# Downloads one upstream file at the pinned tag to $2, decoding the API's
# base64 payload. jq is preferred because it unescapes the JSON string
# correctly; the sed fallback strips the literal \n escapes before decoding.
fetch_upstream_file() {
  local upstream_path="$1" out="$2" payload
  payload="$(api_get "repos/${UPSTREAM_SLUG}/contents/${upstream_path}?ref=${PINNED_TAG}")"
  [ -n "$payload" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.content // empty' | base64 -d > "$out" 2>/dev/null
  else
    printf '%s' "$payload" |
      sed -n 's/.*"content": *"\([^"]*\)".*/\1/p' |
      sed 's/\\n//g' | tr -d '\n' | base64 -d > "$out" 2>/dev/null
  fi
  [ -s "$out" ]
}

print_mapping() {
  printf '%-34s %s\n' "LOCAL FILE" "UPSTREAM SOURCE (at ${PINNED_TAG})"
  local entry
  for entry in "${MAPPING[@]}"; do
    printf '%-34s %s\n' "${entry%%|*}" "${entry##*|}"
  done
}

if [ "$MODE" = "mapping" ]; then
  print_mapping
  exit 0
fi

printf 'Ditto ECC sync report (inspection only)\n'
printf '=======================================\n'
printf 'upstream repo:      %s\n' "$UPSTREAM_REPO"
printf 'pinned version:     %s (%s)\n' "$PINNED_VERSION" "$PINNED_TAG"
printf 'pinned commit:      %s\n' "$PINNED_COMMIT"
printf 'last reviewed:      %s\n' "$(version_value UPSTREAM_REVIEWED_AT)"
printf 'agentshield pin:    %s@%s\n' \
  "$(version_value AGENTSHIELD_NPM_PACKAGE)" "$(version_value AGENTSHIELD_NPM_VERSION)"

printf '\nLive upstream state:\n'
latest_json="$(api_get "repos/${UPSTREAM_SLUG}/releases/latest")"
if [ -n "$latest_json" ] && command -v jq >/dev/null 2>&1; then
  latest_tag="$(printf '%s' "$latest_json" | jq -r '.tag_name // empty')"
  latest_date="$(printf '%s' "$latest_json" | jq -r '.published_at // empty')"
  printf '  latest release:   %s (%s)\n' "${latest_tag:-unknown}" "${latest_date:-unknown}"
  if [ "$latest_tag" = "$PINNED_TAG" ]; then
    printf '  status:           up to date with the pinned tag\n'
  else
    printf '  status:           UPSTREAM MOVED — review before adopting anything\n'
  fi
elif [ -n "$latest_json" ]; then
  printf '  latest release:   fetched, but jq is unavailable to parse it\n'
else
  printf '  latest release:   unavailable (no gh auth, no network, or API blocked)\n'
fi

if command -v npm >/dev/null 2>&1; then
  npm_latest="$(npm view "$(version_value UPSTREAM_NPM_PACKAGE)" version 2>/dev/null | head -n 1)"
  printf '  npm %s: %s\n' \
    "$(version_value UPSTREAM_NPM_PACKAGE)" "${npm_latest:-unavailable}"
fi

printf '\nLocal adaptation surface:\n'
# Counted from the working tree so the report is correct before `git add` too.
count_md() {
  find "$1" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]'
}
printf '  rules:    %s file(s)\n' "$(count_md .ecc/rules)"
printf '  skills:   %s file(s)\n' "$(count_md .ecc/skills)"
printf '  roles:    %s file(s)\n' "$(count_md .ecc/roles)"
printf '  mapped:   %s upstream source reference(s)\n' "${#MAPPING[@]}"

if [ "$MODE" = "fetch" ]; then
  printf '\nFetching upstream sources for comparison (never written into .ecc/):\n'
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ditto-ecc-upstream.XXXXXX")"
  if [ ! -d "$tmp_dir" ]; then
    printf '  ERROR: could not create a temporary directory\n' >&2
    exit 1
  fi
  fetched=0
  missing=0
  seen=""
  for entry in "${MAPPING[@]}"; do
    upstream_path="${entry##*|}"
    case " $seen " in
      *" $upstream_path "*) continue ;;
    esac
    seen="$seen $upstream_path"
    out="${tmp_dir}/$(printf '%s' "$upstream_path" | tr '/' '_')"
    if fetch_upstream_file "$upstream_path" "$out"; then
      fetched=$((fetched + 1))
    else
      missing=$((missing + 1))
      printf '  could not fetch: %s\n' "$upstream_path"
      rm -f "$out"
    fi
  done
  printf '  fetched %s file(s) to: %s\n' "$fetched" "$tmp_dir"
  [ "$missing" -gt 0 ] && printf '  %s path(s) not found at %s (upstream may have moved)\n' "$missing" "$PINNED_TAG"
  printf '\nCompare by hand, then edit .ecc/ deliberately:\n'
  printf '  diff -u %s/rules_common_development-workflow.md .ecc/rules/engineering.md\n' "$tmp_dir"
  printf '\nThis directory is outside the repository. Delete it when done:\n'
  printf '  rm -rf %s\n' "$tmp_dir"
fi

printf '\nAdopting an upstream change requires:\n'
printf '  1. hand-edit the affected .ecc/ file, keeping Arena-specific behaviour\n'
printf '  2. bump UPSTREAM_VERSION / UPSTREAM_TAG / UPSTREAM_COMMIT / UPSTREAM_REVIEWED_AT\n'
printf '  3. record the upgrade as an ADR in docs/decisions/\n'
printf '  4. bash scripts/verify.sh must pass\n'

printf '\nAn ECC upgrade is never implied by a FOUNDATION_VERSION bump.\n'
printf 'It requires its own reviewed issue, ADR, pins and licence verification.\n'

exit 0
