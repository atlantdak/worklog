#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
bj="$root/scripts/board-journal.sh"
t="$(mktemp -d)"; j="$t/journal.ndjson"

WL_JOURNAL="$j" sh "$bj" append create docs/p.md asana ok 111 ""
check "journal file created"    "[ -f '$j' ]"
check "one line written"        "[ \"\$(wc -l < '$j' | tr -d ' ')\" = 1 ]"
check "line is valid json"      "jq -e . '$j'"
check "outcome recorded"        "jq -e '.outcome == \"ok\"' '$j'"
check "card recorded"           "jq -e '.card == \"111\"' '$j'"
check "timestamp is utc"        "jq -re '.ts' '$j' | grep -q 'Z$'"

WL_JOURNAL="$j" sh "$bj" append create docs/p.md asana fail "" "network refused"
check "failures are recorded"   "[ \"\$(wc -l < '$j' | tr -d ' ')\" = 2 ]"
check "failure carries a note"  "tail -n1 '$j' | jq -e '.outcome == \"fail\" and .note == \"network refused\"'"
check "bad outcome rejected"    "! ( WL_JOURNAL='$j' sh '$bj' append create docs/p.md asana maybe 2>/dev/null )"
check "bad outcome writes nothing" "[ \"\$(wc -l < '$j' | tr -d ' ')\" = 2 ]"
rm -rf "$t"
exit $fail
