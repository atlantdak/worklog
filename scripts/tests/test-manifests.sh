#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

check "plugin.json parses"      "jq -e . '$root/.claude-plugin/plugin.json'"
check "plugin.json has name"    "jq -e '.name==\"worklog\"' '$root/.claude-plugin/plugin.json'"
check "marketplace.json parses" "jq -e . '$root/.claude-plugin/marketplace.json'"
check "marketplace lists worklog" "jq -e '.plugins[] | select(.name==\"worklog\")' '$root/.claude-plugin/marketplace.json'"
exit $fail
