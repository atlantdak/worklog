#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
bs="$root/scripts/board-state.sh"
t="$(mktemp -d)"; printf '# p\n' > "$t/p.md"

check "empty map reads as {}"   "[ \"\$(sh '$bs' map-read \"$t/p.md\")\" = '{}' ]"
sh "$bs" map-init "$t/p.md" asana 111 wl-dddd4444 >/dev/null
check "map file is beside plan"  "[ -f \"$t/p.board.json\" ]"
check "map-init stores card"     "sh '$bs' map-read \"$t/p.md\" | jq -e '.card == \"111\"'"
check "map-init stores origin"   "sh '$bs' map-read \"$t/p.md\" | jq -e '.origin == \"wl-dddd4444\"'"
check "subtasks start empty"     "sh '$bs' map-read \"$t/p.md\" | jq -e '.subtasks == {}'"

sh "$bs" map-set "$t/p.md" s1 222 >/dev/null
sh "$bs" map-set "$t/p.md" s2 333 >/dev/null
check "map-set accumulates"      "sh '$bs' map-read \"$t/p.md\" | jq -e '.subtasks | length == 2'"
check "map-set keeps card"       "sh '$bs' map-read \"$t/p.md\" | jq -e '.card == \"111\"'"
check "map-set is idempotent"    "sh '$bs' map-set \"$t/p.md\" s1 222 >/dev/null && sh '$bs' map-read \"$t/p.md\" | jq -e '.subtasks | length == 2'"
check "map-set refuses rebind"   "! sh '$bs' map-set \"$t/p.md\" s1 999 2>/dev/null"
check "no temp files left"       "! ls \"$t\"/.wl.* >/dev/null 2>&1"
rm -rf "$t"

check "dir-of maps in_progress" "[ \"\$(sh '$bs' dir-of in_progress)\" = 'in-progress' ]"
check "dir-of maps to_do"       "[ \"\$(sh '$bs' dir-of to_do)\" = 'to-do' ]"
check "dir-of maps done"        "[ \"\$(sh '$bs' dir-of done)\" = 'done' ]"
check "dir-of rejects unknown"  "! sh '$bs' dir-of nonsense 2>/dev/null"

u="$(mktemp -d)"; mkdir -p "$u/backlog"; printf '# p\n' > "$u/backlog/p.md"
sh "$bs" map-init "$u/backlog/p.md" asana 111 wl-e5 >/dev/null
new="$(sh "$bs" place "$u/backlog/p.md" in_progress)"
check "place moves the plan"    "[ -f \"$u/in-progress/p.md\" ]"
check "place moves the map"     "[ -f \"$u/in-progress/p.board.json\" ]"
check "place clears the source" "[ ! -f \"$u/backlog/p.md\" ]"
check "place prints new path"   "[ \"$new\" = \"$u/in-progress/p.md\" ]"
check "place is idempotent"     "sh '$bs' place \"$u/in-progress/p.md\" in_progress >/dev/null"
rm -rf "$u"
exit $fail
