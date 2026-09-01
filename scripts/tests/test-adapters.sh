#!/usr/bin/env sh
# Structure of the tracker adapters: one tracker per file, a complete capability
# frontmatter, every section the core references, and a tracker the config
# resolver actually knows.
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

dir="$root/references/adapters"
check "adapters dir exists" "[ -d '$dir' ]"
[ -d "$dir" ] || exit 1

# Value of a frontmatter key (the block between the first two --- lines).
fm_get() {
  awk -v k="$2:" 'NR==1 && /^---$/ { f=1; next }
                  f && /^---$/ { exit }
                  f && $1==k { sub(/^[^:]*: */, ""); print; exit }' "$1"
}

found=0
for f in "$dir"/*.md; do
  b="$(basename "$f" .md)"
  found=$((found + 1))

  check "$b: tracker matches filename" "[ \"$(fm_get "$f" tracker)\" = '$b' ]"
  check "$b: rich_text is a known value" \
    "case \"$(fm_get "$f" rich_text)\" in markdown|html_subset|plain) true ;; *) false ;; esac"
  check "$b: nesting is a known value" \
    "case \"$(fm_get "$f" nesting)\" in native|link) true ;; *) false ;; esac"
  check "$b: status is a known value" \
    "case \"$(fm_get "$f" status)\" in named|section|completed_flag) true ;; *) false ;; esac"

  for s in Capabilities Config Assignee "Read state" Create Update Nesting Links Gotchas; do
    check "$b: has section $s" "grep -q '^## $s' '$f'"
  done

  # The assignee is always the authenticated user, never a hardcoded id.
  check "$b: assignee is dynamic (\"me\")" "grep -q '\"me\"' '$f'"

  # One tracker per file: an adapter never mentions another adapter's tracker.
  for other in "$dir"/*.md; do
    ob="$(basename "$other" .md)"
    [ "$ob" = "$b" ] && continue
    check "$b: does not mention $ob" "! grep -qi '$ob' '$f'"
  done

  # The resolver must know this tracker: a config carrying only the tracker key
  # exits 3 (binding missing), never 2 (unknown tracker).
  tmp="$(mktemp -d)"; mkdir -p "$tmp/.claude"
  printf '{ "tracker": "%s", "github_repo": "O/R" }' "$b" > "$tmp/.claude/worklog.config.json"
  WL_GLOBAL_CONFIG=/nonexistent sh "$root/scripts/resolve-config.sh" "$tmp" >/dev/null 2>&1 && rc=0 || rc=$?
  check "$b: resolve-config knows this tracker" "[ $rc -eq 3 ]"
  rm -rf "$tmp"
done

check "at least one adapter exists" "[ $found -gt 0 ]"
exit $fail
