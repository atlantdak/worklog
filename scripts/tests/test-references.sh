#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "config example parses" "jq -e . '$root/references/worklog.config.example.json'"
check "config has clickup_list_id key" "jq -e 'has(\"clickup_list_id\")' '$root/references/worklog.config.example.json'"
check "config has naming.scheme" "jq -e '.naming.scheme' '$root/references/worklog.config.example.json'"
check "project example parses + binding-only" \
  "jq -e 'has(\"clickup_list_id\") and (has(\"language\")|not)' '$root/references/worklog.config.project.example.json'"
check "global example parses + prefs-only (no binding)" \
  "jq -e '.naming.scheme and (has(\"clickup_list_id\")|not)' '$root/references/worklog.config.global.example.json'"
check "format.md has meta-schema anchor" "grep -q 'worklog:meta' '$root/references/format.md'"
check "format.md states date rule" "grep -q 'done' '$root/references/format.md' && grep -q 'in progress' '$root/references/format.md'"
exit $fail
