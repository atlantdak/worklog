#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
bp="$root/scripts/board-preview.sh"
pf="$root/scripts/plan-file.sh"
t="$(mktemp -d)"; cp "$root/scripts/tests/fixtures/plan-fresh.md" "$t/p.md"

out="$(sh "$bp" build "$t/p.md" backlog)"
check "build prints the path"        "[ \"$out\" = \"$t/p.board-preview.md\" ]"
check "preview exists"               "[ -f \"$t/p.board-preview.md\" ]"
check "preview carries fingerprint"  "head -n1 \"$t/p.board-preview.md\" | grep -Eq 'fingerprint: [0-9a-f]{64}'"
check "preview names the section"    "grep -q 'backlog' \"$t/p.board-preview.md\""
check "preview lists both units"     "[ \"\$(grep -c '^- ' \"$t/p.board-preview.md\")\" = 2 ]"
check "verify passes when unchanged" "sh '$bp' verify \"$t/p.md\""

sh "$pf" set-origin "$t/p.md" wl-ffff6666 >/dev/null
check "verify survives a nonce write" "sh '$bp' verify \"$t/p.md\""

printf '\n### Task 3: Третья единица\n' >> "$t/p.md"
check "verify refuses after an edit" "sh '$bp' verify \"$t/p.md\" 2>/dev/null; [ \$? -eq 4 ]"

rm -f "$t/p.board-preview.md"
check "verify without preview exits 2" "sh '$bp' verify \"$t/p.md\" 2>/dev/null; [ \$? -eq 2 ]"
rm -rf "$t"
exit $fail
