#!/usr/bin/env sh
set -eu
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi; }

rc="$root/scripts/resolve-config.sh"
tmp="$(mktemp -d)"
proj="$tmp/proj"; mkdir -p "$proj/.claude"

# Global defaults: preferences only (uk + terminology + a naming override).
cat > "$tmp/global.json" <<'JSON'
{ "language": "uk", "terminology": { "avoid": ["епік"], "use": ["задача"] }, "naming": { "start_n": 43 } }
JSON

# --- Case A: minimal project (only the binding), prefs inherited from global/built-in.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "clickup_list_id": "901217650623", "umbrella_task_id": "U1", "github_repo": "OWNER/REPO" }
JSON
effA="$tmp/a.json"
WL_GLOBAL_CONFIG="$tmp/global.json" sh "$rc" "$proj" > "$effA" 2>/dev/null
check "A: list_id is the project binding" "jq -e '.clickup_list_id==\"901217650623\"' '$effA'"
check "A: language inherited from global" "jq -e '.language==\"uk\"' '$effA'"
check "A: naming deep-merged (scheme built-in + start_n global)" \
  "jq -e '.naming.scheme==\"TASK-{n}\" and .naming.start_n==43' '$effA'"
check "A: terminology from global"        "jq -e '.terminology.avoid==[\"епік\"]' '$effA'"
check "A: drafts_dir from built-in"       "jq -e '.drafts_dir==\"ClickUp/_daily\"' '$effA'"
check "A: assignee NOT pinned (dynamic me)" "jq -e '(.assignee_id // null)==null' '$effA'"
check "A: exit 0 (resolvable)"            "WL_GLOBAL_CONFIG='$tmp/global.json' sh '$rc' '$proj' >/dev/null 2>&1"

# --- Case B: project overrides global scalar; assignee pinned.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "clickup_list_id": "L2", "github_repo": "O/R", "language": "en", "assignee_id": "777" }
JSON
effB="$tmp/b.json"
WL_GLOBAL_CONFIG="$tmp/global.json" sh "$rc" "$proj" > "$effB" 2>/dev/null
check "B: project scalar beats global"    "jq -e '.language==\"en\"' '$effB'"
check "B: assignee override honoured"     "jq -e '.assignee_id==\"777\"' '$effB'"

# --- Case C: explicit null must not clobber inherited value.
cat > "$proj/.claude/worklog.config.json" <<'JSON'
{ "clickup_list_id": "L3", "github_repo": "O/R", "language": null }
JSON
effC="$tmp/c.json"
WL_GLOBAL_CONFIG="$tmp/global.json" sh "$rc" "$proj" > "$effC" 2>/dev/null
check "C: null does not clobber (stays uk)" "jq -e '.language==\"uk\"' '$effC'"

# --- Case D: no project config -> NEEDS_ONBOARDING (exit 3).
empty="$tmp/empty"; mkdir -p "$empty"
check "D: missing list_id exits 3" \
  "WL_GLOBAL_CONFIG=/nonexistent sh '$rc' '$empty'; [ \$? -eq 3 ]"

# --- Case E: malformed project JSON fails loudly (exit 2).
printf '{ not json' > "$proj/.claude/worklog.config.json"
check "E: malformed JSON exits non-zero"  "! ( WL_GLOBAL_CONFIG='$tmp/global.json' sh '$rc' '$proj' >/dev/null 2>&1 )"

rm -rf "$tmp"
exit $fail
