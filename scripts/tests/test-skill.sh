#!/usr/bin/env sh
# The core skill must stay tracker-neutral: it drives the flow and resolves an
# adapter by config key. Every tracker-specific fact belongs in references/adapters/.
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"; f="$root/skills/worklog-day/SKILL.md"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }
check "skill file exists"      "[ -s '$f' ]"
check "has name frontmatter"   "grep -q '^name: worklog-day' '$f'"
check "has description"        "grep -q '^description:' '$f'"
for s in "S0" "S1" "S2" "S3" "S4" "Onboarding" "collect-window.sh" "validate-draft.sh" "worklog.config.json"; do
  check "mentions $s" "grep -q '$s' '$f'"
done
check "core names no tracker"  "! grep -qiE 'clickup|asana|jira|linear' '$f'"
check "core resolves an adapter by key" "grep -q 'adapters/<eff.tracker>.md' '$f'"
check "core announces which adapter it loaded" "grep -qi 'announce' '$f'"
check "core reads the capability keys" \
  "grep -q 'rich_text' '$f' && grep -q 'nesting' '$f' && grep -q '\`status\`' '$f'"
check "core assigns the authenticated user" "grep -q '\"me\"' '$f'"
check "core uses the root parent value" "grep -q '\"root\"' '$f'"
check "states no-write-before-approval" "grep -qi 'never write' '$f' || grep -qi 'never create or update' '$f'"
check "S3 nests subtasks natively" "grep -qi 'native' '$f'"
check "mentions umbrellas/containers structure" "grep -q 'containers' '$f'"
check "states voice by status" "grep -qi 'Voice by status' '$f'"
check "S0 accepts russian window words" "grep -q 'вчера' '$f' && grep -q 'с #' '$f'"
check "S0 keeps english window words"   "grep -q 'yesterday' '$f' && grep -q 'since' '$f'"
b="$root/skills/worklog-board/SKILL.md"
check "board skill exists"          "[ -s '$b' ]"
check "board skill has name"        "grep -q '^name: worklog-board' '$b'"
check "board skill has description" "grep -q '^description:' '$b'"
for s in plan-file.sh board-state.sh board-preview.sh board-journal.sh resolve-config.sh; do
  check "board skill uses $s"       "grep -q '$s' '$b'"
done
check "board skill mentions no tracker"      "! grep -qiE 'asana|clickup' '$b'"
check "board skill announces its adapter"    "grep -qi 'announce' '$b'"
check "board skill is preview-first"         "grep -qi 'preview' '$b'"
check "board skill requires confirmation"    "grep -qi 'confirm' '$b'"
check "board skill never deletes cards"      "grep -qi 'never delete' '$b'"
check "day skill closes an existing card"    "grep -q 'Board:' '$f'"
exit $fail
