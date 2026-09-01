#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
pf="$root/scripts/plan-file.sh"
fx="$root/scripts/tests/fixtures"

fresh="$(sh "$pf" read "$fx/plan-fresh.md")"
check "fresh: card is null"        "printf '%s' '$fresh' | jq -e '.card == null'"
check "fresh: origin parsed"       "printf '%s' '$fresh' | jq -e '.origin == \"wl-aaaa1111\"'"
check "fresh: two units"           "printf '%s' '$fresh' | jq -e '.units | length == 2'"
check "fresh: unit ids are null"   "printf '%s' '$fresh' | jq -e '[.units[].id] == [null, null]'"
check "fresh: titles carried"      "printf '%s' '$fresh' | jq -e '.units[0].title == \"Первая единица\"'"
check "fresh: fingerprint is sha"  "printf '%s' '$fresh' | jq -re '.fingerprint' | grep -Eq '^[0-9a-f]{64}$'"

linked="$(sh "$pf" read "$fx/plan-linked.md")"
check "linked: tracker parsed"     "printf '%s' '$linked' | jq -e '.tracker == \"asana\"'"
check "linked: card parsed"        "printf '%s' '$linked' | jq -e '.card == \"1210987654321\"'"
check "linked: ids parsed"         "printf '%s' '$linked' | jq -e '[.units[].id] == [\"s1\", \"s2\"]'"
check "linked: marker off title"   "printf '%s' '$linked' | jq -e '.units[0].title == \"Первая единица\"'"

check "missing file exits 2"       "! sh '$pf' read /nonexistent/x.md 2>/dev/null"
t="$(mktemp -d)"; cp "$fx/plan-fresh.md" "$t/p.md"
before="$(sh "$pf" read "$t/p.md" | jq -r .fingerprint)"

sh "$pf" set-board "$t/p.md" asana 999 >/dev/null
check "set-board writes the line"   "grep -q '^\*\*Board:\*\* asana:999$' \"$t/p.md\""
check "set-board is readable back"  "sh '$pf' read \"$t/p.md\" | jq -e '.card == \"999\"'"
check "set-board keeps fingerprint" "[ \"\$(sh '$pf' read \"$t/p.md\" | jq -r .fingerprint)\" = \"$before\" ]"

sh "$pf" set-marker "$t/p.md" 2 s7 >/dev/null
check "set-marker tags the unit"    "grep -q '^### Task 2: Вторая единица #s7$' \"$t/p.md\""
check "set-marker leaves others"    "grep -q '^### Task 1: Первая единица$' \"$t/p.md\""

sh "$pf" set-origin "$t/p.md" wl-cccc3333 >/dev/null
check "set-origin replaces, not adds" "[ \"\$(grep -c '^\*\*Origin:\*\*' \"$t/p.md\")\" = 1 ]"
check "set-origin value applied"      "grep -q '^\*\*Origin:\*\* wl-cccc3333$' \"$t/p.md\""
check "no temp files left"            "! ls \"$t\"/.wl.* >/dev/null 2>&1"
check "set-marker out of range fails" "! sh '$pf' set-marker \"$t/p.md\" 99 s9 2>/dev/null"
rm -rf "$t"
exit $fail
