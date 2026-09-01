#!/usr/bin/env sh
# Build the preview a human reads before anything is written to the tracker,
# and refuse a confirmation that no longer matches what was read.
#
# Usage:
#   board-preview.sh build  <plan> <section-key>   -> path on stdout
#   board-preview.sh verify <plan>
# exit 4 : the plan changed after the preview was built — a normal refusal, and
#          the caller must tell it apart from a missing file
# exit 2 : usage, missing plan, or missing preview
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

cmd="${1:?usage: board-preview.sh <build|verify> <plan> [section]}"
plan="${2:?plan path required}"
[ -f "$plan" ] || wl_die "no such plan: $plan"
preview="${plan%.md}.board-preview.md"

build() {
    _section="${1:?section key required}"
    _json="$(sh "$here/plan-file.sh" read "$plan")"
    _title="$(head -n1 "$plan" | sed 's/^# *//')"
    {
        printf '<!-- fingerprint: %s -->\n\n' "$(printf '%s' "$_json" | jq -r .fingerprint)"
        printf '# Будет создано\n\n'
        printf '**Карточка:** %s\n\n' "$_title"
        printf '**Секция:** %s\n\n' "$_section"
        printf '**Подзадачи:**\n\n'
        printf '%s' "$_json" | jq -r '.units[] | "- " + .title'
        printf '\nПодтверди, чтобы записать. Отмена — просто не подтверждай.\n'
    } | wl_atomic_write "$preview"
    printf '%s\n' "$preview"
}

verify() {
    [ -f "$preview" ] || { printf 'no preview for %s\n' "$plan" >&2; exit 2; }
    _was="$(sed -n '1s/.*fingerprint: \([0-9a-f]*\).*/\1/p' "$preview")"
    _now="$(sh "$here/plan-file.sh" read "$plan" | jq -r .fingerprint)"
    [ "$_was" = "$_now" ] || {
        printf 'plan changed after the preview was built\n' >&2
        exit 4
    }
}

case "$cmd" in
  build)  build "${3:-}" ;;
  verify) verify ;;
  *)      wl_die "unknown command: $cmd" ;;
esac
