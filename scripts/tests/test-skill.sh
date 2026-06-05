#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"; f="$root/skills/worklog-day/SKILL.md"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
check "skill file exists"      "[ -s '$f' ]"
check "has name frontmatter"   "grep -q '^name: worklog-day' '$f'"
check "has description"        "grep -q '^description:' '$f'"
for s in "S0" "S1" "S2" "S3" "S4" "Onboarding" "collect-window.sh" "validate-draft.sh" "worklog.config.json" "clickup_create_task" "clickup_add_task_link"; do
  check "mentions $s" "grep -q '$s' '$f'"
done
check "states no-write-before-approval" "grep -qi 'never write' '$f' || grep -qi 'не пиши' '$f'"
exit $fail
