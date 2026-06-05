#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fx="$root/scripts/tests/fixtures"; v="$root/scripts/validate-draft.sh"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "valid draft passes"          "sh '$v' '$fx/draft-ok.md' '$fx/logged-prs.txt'"
check "in-progress+due fails"       "! sh '$v' '$fx/draft-baddate.md' '$fx/logged-prs.txt'"
check "dedup violation fails"       "! sh '$v' '$fx/draft-dupe.md' '$fx/logged-prs.txt'"
check "prints SP total"             "sh '$v' '$fx/draft-ok.md' '$fx/logged-prs.txt' | grep -q 'SP total: 11'"
check "missing entries[] fails"     "! sh '$v' '$fx/draft-noentries.md' '$fx/logged-prs.txt'"
check "fractional sp fails"         "! sh '$v' '$fx/draft-fracsp.md' '$fx/logged-prs.txt'"
exit $fail
