#!/usr/bin/env sh
# One line per finished operation, successes and failures alike. This is a trail
# for a human looking back, not state: nothing reads it to decide anything, and
# deleting it changes no behaviour.
#
# Usage: board-journal.sh append <op> <plan> <tracker> <ok|fail> [card] [note]
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wl_need jq

[ "${1:-}" = "append" ] || wl_die "usage: board-journal.sh append <op> <plan> <tracker> <ok|fail> [card] [note]"
op="${2:?op required}"; plan="${3:?plan required}"
tracker="${4:?tracker required}"; outcome="${5:?outcome required}"
card="${6:-}"; note="${7:-}"

# Only two outcomes exist. A third would quietly become a category nobody reads.
case "$outcome" in
  ok|fail) ;;
  *) wl_die "outcome must be ok or fail (got: $outcome)" ;;
esac

journal="${WL_JOURNAL:-$HOME/.claude/worklog/journal.ndjson}"
mkdir -p "$(dirname "$journal")" || wl_die "cannot create journal directory"

jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg op "$op" \
  --arg plan "$plan" --arg tracker "$tracker" --arg outcome "$outcome" \
  --arg card "$card" --arg note "$note" \
  '{ts:$ts, op:$op, plan:$plan, tracker:$tracker, outcome:$outcome, card:$card, note:$note}' \
  >> "$journal"
