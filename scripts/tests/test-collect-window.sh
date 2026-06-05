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
check "has 2 entries"            "jq -e 'length==2' '$outf'"
check "entry has number+url"     "jq -e '.[0].number and .[0].url' '$outf'"
check "rejects unknown scope"    "! ( PATH=\"$tmp:\$PATH\" sh '$root/scripts/collect-window.sh' OWNER/REPO bogus x )"
rm -rf "$tmp"
exit $fail
