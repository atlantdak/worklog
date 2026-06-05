#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

# Stub gh: copy fixture to an executable `gh` on a temp PATH.
tmp="$(mktemp -d)"; cp "$root/scripts/tests/fixtures/gh-stub" "$tmp/gh"; chmod +x "$tmp/gh"
# Capture stdout to a file so the JSON (with embedded quotes) is never re-parsed by the shell.
outf="$tmp/out.json"
PATH="$tmp:$PATH" sh "$root/scripts/collect-window.sh" OWNER/REPO date 2026-06-04 > "$outf"

check "emits valid json array"   "jq -e 'type==\"array\"' '$outf'"
check "date scope: 2 merged"     "jq -e 'length==2' '$outf'"
check "entry has number+url"     "jq -e '.[0].number and .[0].url' '$outf'"
check "rejects unknown scope"    "! ( PATH=\"$tmp:\$PATH\" sh '$root/scripts/collect-window.sh' OWNER/REPO bogus x )"

# since-scope keeps OPEN + MERGED but drops CLOSED-unmerged (#150 abandoned, #190 open).
sincef="$tmp/since.json"
PATH="$tmp:$PATH" sh "$root/scripts/collect-window.sh" OWNER/REPO since 100 > "$sincef"
check "since: open #190 kept"    "jq -e 'any(.number==190)' '$sincef'"
check "since: closed #150 dropped" "jq -e 'all(.number!=150)' '$sincef'"
check "since: count is 3"        "jq -e 'length==3' '$sincef'"
check "pr-range needs A..B"      "! ( PATH=\"$tmp:\$PATH\" sh '$root/scripts/collect-window.sh' OWNER/REPO pr-range 186 )"
rm -rf "$tmp"
exit $fail
