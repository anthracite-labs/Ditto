#!/usr/bin/env bash
# Safe identity maintenance for Ditto's App-Factory-derived foundation.
#
# Ditto is already initialized. By default this is a no-op, not a template
# reset. For an explicitly requested rename, --force changes only PROJECT_NAME
# and PROJECT_SLUG in config/project.env. It preserves the lifecycle phase,
# ALLOW_APP_STACK and STACK_DECISION_ADR, including implementation state.
#
# Never rewrites documents, project memory, history, ECC provenance, licences or
# FOUNDATION_VERSION. Never commits, pushes, creates branches or changes GitHub
# settings. Invalid lifecycle state is refused, not silently repaired.
#
# Usage:
#   scripts/init-project.sh                       normally a no-op in Ditto
#   scripts/init-project.sh --name "Project Name"  initialize empty identity only
#   scripts/init-project.sh --slug project-name    override the derived slug
#   scripts/init-project.sh --dry-run              show the change; write nothing
#   scripts/init-project.sh --force --name "Name"  reviewed identity-only change
#   scripts/init-project.sh --help                 usage
#
# Exit status: 0 on success or no-op, 1 on refusal, 2 on usage error.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$REPO_ROOT" || exit 2
CONFIG=config/project.env
NAME='' SLUG=''
DRY_RUN=0 FORCE=0

usage() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'init-project.sh: %s\n' "$*" >&2; exit 1; }
usage_error() { printf 'init-project.sh: %s\n' "$*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name|--slug)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
        usage_error 'a non-empty value is required after --name/--slug'
      fi
      if [ "$1" = --name ]; then NAME="$2"; else SLUG="$2"; fi
      shift
      ;;
    --name=*) NAME="${1#--name=}"; [ -n "$NAME" ] || usage_error '--name cannot be empty' ;;
    --slug=*) SLUG="${1#--slug=}"; [ -n "$SLUG" ] || usage_error '--slug cannot be empty' ;;
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage_error 'unknown argument (see --help)' ;;
  esac
  shift
done

config_value() {
  sed -n "s/^[[:space:]]*${1}[[:space:]]*=[[:space:]]*//p" "$CONFIG" |
    head -n 1 | sed 's/[[:space:]]*$//'
}

# Use the real shared lifecycle validator. This also rejects duplicate/missing
# keys and config/ADR symlinks before reading or writing any identity values.
if ! bash scripts/verify.sh --only=lifecycle --quiet >/dev/null 2>&1; then
  die 'invalid lifecycle configuration; run bash scripts/verify.sh --only=lifecycle and review the state before initializing'
fi
CURRENT_NAME="$(config_value PROJECT_NAME)"
CURRENT_PHASE="$(config_value PROJECT_PHASE)"
if [ "$FORCE" -eq 0 ] && [ -n "$CURRENT_NAME" ]; then
  printf 'Already initialized as %s — nothing to do.\n' "$CURRENT_NAME"
  printf 'Lifecycle, identity and project documents are unchanged.\n'
  printf 'Only an explicit --force requests an identity change; it never resets lifecycle state.\n'
  exit 0
fi

# Origin is a naming convenience only, not a product or architectural decision.
if [ -z "$NAME" ]; then
  origin="$(git config --get remote.origin.url 2>/dev/null || true)"
  [ -z "$origin" ] || NAME="$(basename -- "${origin%.git}")"
fi
# Match the entire argument. Line-oriented grep would accept a valid first
# line followed by newline-injected config assignments.
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]{0,63}$ ]] ||
  die 'invalid name: use 1-64 letters, digits, spaces, dots, underscores or hyphens on one line'
if [ -z "$SLUG" ]; then
  SLUG="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
fi
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] ||
  die 'invalid slug: use at most 64 lowercase kebab-case characters on one line'

printf 'Project identity change\n'
printf '  PROJECT_NAME:  %s -> %s\n' "${CURRENT_NAME:-<empty>}" "$NAME"
printf '  PROJECT_SLUG:  %s -> %s\n' "$(config_value PROJECT_SLUG)" "$SLUG"
printf '  PROJECT_PHASE: %s (preserved)\n' "$CURRENT_PHASE"
printf '  ALLOW_APP_STACK and STACK_DECISION_ADR: preserved\n'
if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n--dry-run: nothing was written.\n'
  exit 0
fi

# Stage in the same directory, retain permissions, then rename atomically.
# Never truncate the live file with a copy from a potentially different device.
TMP="$(mktemp "${CONFIG}.init.XXXXXX")" || die 'could not create a sibling temporary file'
# shellcheck disable=SC2317,SC2329  # cleanup is invoked by the EXIT trap.
cleanup() { rm -f -- "$TMP"; }
trap cleanup EXIT
awk -v name="$NAME" -v slug="$SLUG" '
  /^PROJECT_NAME=/ { print "PROJECT_NAME=" name; next }
  /^PROJECT_SLUG=/ { print "PROJECT_SLUG=" slug; next }
  { print }
' "$CONFIG" > "$TMP" || die 'could not stage the identity update'
[ -s "$TMP" ] || die 'refusing an empty config update'
chmod --reference="$CONFIG" "$TMP" || die 'could not preserve config permissions'
if [ -L config ] || [ -L "$CONFIG" ]; then
  die 'refusing to replace a symlinked configuration'
fi
mv -f -- "$TMP" "$CONFIG" || die 'could not atomically update config'

printf '\nUpdated %s only. No commit, push or GitHub setting change.\n' "$CONFIG"
printf 'Review the diff, then run bash scripts/verify.sh and bash scripts/selftest.sh.\n'
printf 'Keep any identity decision in a reviewed PR; see docs/FOUNDATION.md.\n'
exit 0
