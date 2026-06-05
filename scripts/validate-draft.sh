#!/usr/bin/env sh
# Validate a worklog draft against the format contract.
# Usage: validate-draft.sh DRAFT_MD LOGGED_PRS_TXT
# Exits 0 if valid (prints "SP total: N"), 1 if any rule fails (prints reasons), 2 on usage error.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

draft="${1:?draft path required}"; logged="${2:-/dev/null}"
[ -s "$draft" ] || wl_die "draft missing or empty: $draft"

# Extract JSON between the worklog:meta markers.
meta="$(awk '/worklog:meta -->/{f=0} f; /<!-- worklog:meta/{f=1}' "$draft")"
printf '%s' "$meta" | jq -e . >/dev/null 2>&1 || wl_die "no valid worklog:meta JSON block"
# Guard the shape before any `.entries`-walking jq runs, so a malformed block fails
# as a clean usage error (exit 2) instead of leaking a raw jq error.
printf '%s' "$meta" | jq -e '(.entries|type)=="array" and (.entries|length>0)' >/dev/null 2>&1 \
  || wl_die "worklog:meta has no non-empty entries[] array"

errs=0
note() { printf 'INVALID: %s\n' "$1" >&2; errs=1; }

# Per-entry structural + date rule, via jq returning offending indexes.
# sp must be a positive whole number (no fractions).
bad_struct="$(printf '%s' "$meta" | jq -r '
  [ .entries | to_entries[]
    | select((.value.title|type)!="string"
        or (.value.sp|type)!="number" or .value.sp <= 0 or (.value.sp != (.value.sp|floor))
        or (.value.status|IN("done","in progress")|not)
        or (.value.start|type)!="string")
    | .key ] | join(",")')"
[ -z "$bad_struct" ] || note "entries with bad title/sp/status/start: [$bad_struct]"

bad_date="$(printf '%s' "$meta" | jq -r '
  [ .entries | to_entries[]
    | select( (.value.status=="done"   and ((.value.due|type)!="string"))
           or (.value.status=="in progress" and (.value.due!=null and (.value.due|type)=="string")) )
    | .key ] | join(",")')"
[ -z "$bad_date" ] || note "date-rule violations (done needs due; in progress must not have due): [$bad_date]"

# Dedup: any PR already in logged-prs.txt.
if [ -s "$logged" ]; then
  for pr in $(printf '%s' "$meta" | jq -r '.entries[].prs[]?'); do
    if grep -qx "$pr" "$logged"; then note "PR #$pr already logged (dedup)"; fi
  done
fi

total="$(printf '%s' "$meta" | jq '[.entries[].sp] | add // 0')"
[ "$errs" -eq 0 ] || exit 1
printf 'SP total: %s\n' "$total"
