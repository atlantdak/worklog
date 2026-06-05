#!/usr/bin/env sh
set -eu
d="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$d"/test-*.sh; do
  echo "== $t =="
  if ! sh "$t"; then fail=1; fi
done
[ "$fail" -eq 0 ] && echo "ALL GREEN" || echo "SOME FAILED"
exit $fail
