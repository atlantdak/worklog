#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/lib.sh"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

d="$(wl_run_dir 2026-06-04)"
check "run dir created"      "[ -d \"$d\" ]"
check "run dir carries date" "printf '%s' \"$d\" | grep -q 'worklog-run-2026-06-04'"
check "wl_die exits nonzero" "! ( wl_die 'x' 2>/dev/null )"
t="$(mktemp -d)"
printf 'старое\n' > "$t/f"
printf 'новое\n' | wl_atomic_write "$t/f"
check "atomic write replaces content" "grep -q '^новое$' \"$t/f\""
check "atomic write leaves no temp"   "[ \"\$(ls \"$t\" | wc -l | tr -d ' ')\" = 1 ]"
check "sha256 prints bare hash"       "printf '%s' \"\$(wl_sha256 \"$t/f\")\" | grep -Eq '^[0-9a-f]{64}$'"
check "sha256 is stable"              "[ \"\$(wl_sha256 \"$t/f\")\" = \"\$(wl_sha256 \"$t/f\")\" ]"
rm -rf "$t"
exit $fail
