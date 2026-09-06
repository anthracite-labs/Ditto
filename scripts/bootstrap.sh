#!/usr/bin/env bash
# Ditto session bootstrap briefing.
#
# Prints everything a fresh Arena session (or a human) needs to start working:
# foundation version, project lifecycle state, provenance, the always-read set,
# the workflow index, and the verification command. Read-only: this script
# never modifies the repository.
#
# Usage:
#   scripts/bootstrap.sh              print the briefing
#   scripts/bootstrap.sh --issue 12   include issue #12 in the suggested prompt
#   scripts/bootstrap.sh --quiet      paths only, no headings

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT" || exit 2

ISSUE=""
QUIET=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue) shift; ISSUE="${1:-}" ;;
    --issue=*) ISSUE="${1#--issue=}" ;;
    --quiet|-q) QUIET=1 ;;
    -h|--help)
      sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'bootstrap.sh: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

version_value() {
  sed -n "s/^${1}=//p" .ecc/VERSION 2>/dev/null | head -n 1
}

config_value() {
  sed -n "s/^[[:space:]]*${1}[[:space:]]*=[[:space:]]*//p" config/project.env 2>/dev/null |
    head -n 1 | sed 's/[[:space:]]*$//'
}

h1() { [ "$QUIET" -eq 1 ] || printf '\n== %s\n' "$*"; }
line() { printf '%s\n' "$*"; }

project_name="$(config_value PROJECT_NAME)"
phase="$(config_value PROJECT_PHASE)"

# Refuse to brief an agent from ambiguous or hostile lifecycle state.
if ! bash scripts/verify.sh --only=lifecycle --quiet >/dev/null 2>&1; then
  printf 'bootstrap.sh: invalid lifecycle state; run bash scripts/verify.sh --only=lifecycle\n' >&2
  exit 1
fi

h1 "Ditto project"
line "name:       ${project_name:-<not set — run scripts/init-project.sh>}"
line "phase:      ${phase:-unknown}"
line "app stack:  allowed=$(config_value ALLOW_APP_STACK) adr=$(config_value STACK_DECISION_ADR)"
line "foundation: App-Factory v$(head -n 1 FOUNDATION_VERSION 2>/dev/null || echo unknown)"

case "$phase" in
  discovery)
    line "note:       no product definition yet. Do not invent one; see docs/PRODUCT.md."
    ;;
  architecture)
    line "note:       product defined, stack being decided. Record it as an ADR."
    ;;
  implementation)
    line "note:       stack recorded in $(config_value STACK_DECISION_ADR)."
    ;;
  *)
    line "note:       PROJECT_PHASE is unrecognised; check config/project.env."
    ;;
esac

h1 "ECC-on-Arena adapter"
line "adapter:  $(version_value ADAPTER_NAME) v$(version_value ADAPTER_VERSION)"
line "upstream: ECC $(version_value UPSTREAM_VERSION) ($(version_value UPSTREAM_TAG), $(version_value UPSTREAM_COMMIT))"
line "licence:  $(version_value UPSTREAM_LICENSE) — adapted, attributed per file"
line "kind:     $(version_value ADAPTER_KIND) (native ECC runtime: $(version_value ADAPTER_NATIVE_ECC_RUNTIME))"

h1 "Always read"
line ".ecc/BOOTSTRAP.md          session protocol — read this first"
line ".ecc/rules/engineering.md  standing engineering rules"
line ".ecc/skills/INDEX.md       workflow router — pick 1-2 workflows"
line "docs/MEMORY.md             what previous sessions learned (append to it)"
line "config/project.env         the project's actual lifecycle state"
line "ARENA_CAPABILITIES.md      only if the task touches tooling, network, or CI"

h1 "Load on demand (never all at once)"
if [ -f .ecc/skills/INDEX.md ]; then
  grep -oE '\.ecc/skills/[A-Za-z0-9._-]+\.md' .ecc/skills/INDEX.md |
    sort -u |
    while IFS= read -r path; do
      [ "$path" = ".ecc/skills/INDEX.md" ] && continue
      printf '%-34s %s\n' "$path" "$(basename -- "$path" .md)"
    done
fi

h1 "Rules that always apply"
for rule in .ecc/rules/*.md; do
  [ -f "$rule" ] || continue
  line "$rule"
done

h1 "Review personas (sequential, not subagents)"
for role in .ecc/roles/*.md; do
  [ -f "$role" ] || continue
  line "$role"
done

h1 "Verify before claiming done"
line "bash scripts/verify.sh     authoritative gate"
line "bash scripts/selftest.sh   negative tests — the gate must reject faults"

h1 "State"
line "branch:   $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
line "commit:   $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  behind="$(git rev-list --count "HEAD..origin/main" 2>/dev/null || echo '?')"
  ahead="$(git rev-list --count "origin/main..HEAD" 2>/dev/null || echo '?')"
  line "main:     ${behind} behind, ${ahead} ahead of origin/main"
fi
memory_date="$(git log -1 --format=%cs -- docs/MEMORY.md 2>/dev/null)"
if [ -n "$memory_date" ]; then
  line "memory:   last docs/MEMORY.md change committed ${memory_date}"
elif [ -f docs/MEMORY.md ]; then
  line "memory:   docs/MEMORY.md present but not committed yet"
else
  line "memory:   docs/MEMORY.md missing"
fi

h1 "Suggested prompt for this session"
if [ -n "$ISSUE" ]; then
  line "Read \`.ecc/BOOTSTRAP.md\`, initialize the Ditto engineering protocol, inspect"
  line "project memory and the skill index, then work GitHub Issue #${ISSUE}. Load only"
  line "skills relevant to that issue."
else
  line "Read \`.ecc/BOOTSTRAP.md\`, initialize the Ditto engineering protocol, inspect"
  line "project memory and the skill index, then work GitHub Issue #X. Load only skills"
  line "relevant to that issue."
fi

exit 0
