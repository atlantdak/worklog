#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"; f="$root/commands/log-day.md"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
check "command file exists"        "[ -s '$f' ]"
check "has frontmatter description" "grep -q '^description:' '$f'"
check "invokes worklog-day skill"  "grep -q 'worklog-day' '$f'"
check "passes \$ARGUMENTS"          "grep -q 'ARGUMENTS' '$f'"
exit $fail
