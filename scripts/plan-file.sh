#!/usr/bin/env sh
# Read and mutate a plan file. The plan is the source of the card link, and the
# nonce that keys idempotency, so every write here goes through wl_atomic_write.
#
# Usage:
#   plan-file.sh read       <plan>
#   plan-file.sh set-origin <plan> <nonce>
#   plan-file.sh set-board  <plan> <tracker> <gid>
#   plan-file.sh set-marker <plan> <unit-number> <id>
# Every command prints the resulting plan as JSON.
# exit 2 : usage, missing file, or a unit number out of range
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

cmd="${1:?usage: plan-file.sh <read|set-origin|set-board|set-marker> <plan> ...}"
plan="${2:?plan path required}"
[ -f "$plan" ] || wl_die "no such plan: $plan"

# The fingerprint covers the substantive plan only: the link lines are stripped,
# so writing the nonce cannot invalidate a preview the human already read.
plan_fingerprint() {
    _t="$(mktemp)"
    grep -v -e '^\*\*Board:\*\*' -e '^\*\*Origin:\*\*' "$plan" > "$_t" || true
    wl_sha256 "$_t"
    rm -f "$_t"
}

read_plan() {
    _board="$(sed -n 's/^\*\*Board:\*\* *//p' "$plan" | head -n1)"
    _origin="$(sed -n 's/^\*\*Origin:\*\* *//p' "$plan" | head -n1)"
    if [ -n "$_board" ]; then _tracker="${_board%%:*}"; _card="${_board#*:}"
    else _tracker=""; _card=""; fi

    # One unit per task heading. A trailing #sN is the marker; the title is what
    # remains once the marker and the "Task N:" prefix are taken off.
    _units="$(grep '^### ' "$plan" | sed 's/^### //' | jq -R -s '
      [ splits("\n") | select(length > 0) |
        capture("^(?<label>.*?)(?: +#(?<id>s[0-9]+))?$") |
        { id: (.id // null),
          title: (.label | sub("^Task [0-9]+: *"; "")) } ]')"

    jq -n --arg path "$plan" --arg tracker "$_tracker" --arg card "$_card" \
          --arg origin "$_origin" --arg fp "$(plan_fingerprint)" \
          --argjson units "$_units" '{
      path: $path,
      tracker: (if $tracker == "" then null else $tracker end),
      card:    (if $card    == "" then null else $card    end),
      origin:  (if $origin  == "" then null else $origin  end),
      fingerprint: $fp,
      units: $units
    }'
}

# Replace a header line, or insert it right after the H1 when absent.
set_header() {
    _key="$1"; _val="$2"
    if grep -q "^\*\*$_key:\*\*" "$plan"; then
        sed "s|^\*\*$_key:\*\* .*|**$_key:** $_val|" "$plan" | wl_atomic_write "$plan"
    else
        awk -v line="**$_key:** $_val" '
            NR == 1 { print; print ""; print line; next }
            NR == 2 && $0 == "" { next }
            { print }' "$plan" | wl_atomic_write "$plan"
    fi
}

set_marker() {
    _n="${1:?unit number required}"; _id="${2:?marker required}"
    _total="$(grep -c '^### ' "$plan" || true)"
    [ "$_n" -ge 1 ] 2>/dev/null && [ "$_n" -le "$_total" ] \
        || wl_die "unit $_n out of range (plan has $_total)"
    awk -v n="$_n" -v id="$_id" '
        /^### / { c++; if (c == n) { sub(/ +#s[0-9]+$/, ""); print $0 " #" id; next } }
        { print }' "$plan" | wl_atomic_write "$plan"
}

case "$cmd" in
  read)       read_plan ;;
  set-origin) set_header Origin "${3:?nonce required}"; read_plan ;;
  set-board)  set_header Board "${3:?tracker required}:${4:?gid required}"; read_plan ;;
  set-marker) set_marker "${3:-}" "${4:-}"; read_plan ;;
  *)          wl_die "unknown command: $cmd" ;;
esac
