#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"; f="$root/commands/log-day.md"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
check "command file exists"        "[ -s '$f' ]"
check "has frontmatter description" "grep -q '^description:' '$f'"
check "invokes worklog-day skill"  "grep -q 'worklog-day' '$f'"
check "passes \$ARGUMENTS"          "grep -q 'ARGUMENTS' '$f'"
check "allows clickup write tools" "grep -q 'mcp__clickup__clickup_create_task' '$f'"
check "allows asana write tools"   "grep -q 'mcp__asana__create_tasks' '$f'"
check "allows asana update+comment" \
  "grep -q 'mcp__asana__update_tasks' '$f' && grep -q 'mcp__asana__add_comment' '$f'"
check "description is tracker-neutral" "! grep -q '^description:.*ClickUp' '$f'"
for c in plan-to-board board-move board-cancel board-relink; do
  cf="$root/commands/$c.md"
  check "$c: command file exists"    "[ -s '$cf' ]"
  check "$c: declares description"   "grep -q '^description:' '$cf'"
  check "$c: declares allowed-tools" "grep -q '^allowed-tools:' '$cf'"
  check "$c: invokes the board skill" "grep -q 'worklog-board' '$cf'"
  check "$c: description is neutral" "! grep -qiE '^description:.*(ClickUp|Asana)' '$cf'"
done
exit $fail
